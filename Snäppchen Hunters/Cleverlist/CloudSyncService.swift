import Foundation
import Observation
import CloudKit
import CryptoKit
import UserNotifications

private struct CloudSyncDiskState: Codable {
    var version = 1
    var bindings: [CloudListBinding] = []
    var lastAccountName: String?
    var engineStates: [String: CKSyncEngine.State.Serialization] = [:]
    var systemFields: [String: Data] = [:]
    var acknowledged: [String: String] = [:]
}

@MainActor @Observable
final class CloudSyncService: NSObject {
    static let containerIdentifier = "iCloud.com.Flygare.Cleverlist"
    let container = CKContainer(identifier: containerIdentifier)
    private(set) var bindings: [CloudListBinding] = []
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var accountName: String?
    var errorMessage: String?
    private(set) var pendingCount = 0

    @ObservationIgnored private let store: CleverlistStore
    @ObservationIgnored private var disk = CloudSyncDiskState()
    @ObservationIgnored private var engines: [CKDatabase.Scope: CKSyncEngine] = [:]
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceFailed = false
    @ObservationIgnored private var busyListIDs: Set<UUID> = []

    init(store: CleverlistStore) {
        self.store = store
        super.init()
        do {
            if FileManager.default.fileExists(atPath: store.cloudStateURL.path) {
                disk = try JSONDecoder().decode(CloudSyncDiskState.self, from: Data(contentsOf: store.cloudStateURL))
                guard disk.version == 1 else { throw CloudListError.invalidRecord }
            }
            bindings = disk.bindings
            // Cached identity enables local offline editing after relaunch. Engines
            // are never created until connectAccount verifies the live account.
            accountName = disk.lastAccountName
        } catch {
            persistenceFailed = true
            errorMessage = CloudListError.persistence.localizedDescription
        }
        updateAccess()
        UNUserNotificationCenter.current().delegate = self
        store.onLocalChange = { [weak self] in self?.localChanges() }
        store.onRemoteItemsChanged = { [weak self] items in self?.notify(items) }
        accountTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { return }
                await self.resetAccount()
                self.resumeIfNeeded()
            }
        }
    }

    func binding(for listID: UUID) -> CloudListBinding? {
        bindings.first { $0.id == listID && $0.isActive }
    }

    func status(for listID: UUID) -> String {
        guard let binding = binding(for: listID) else {
            return store.text("Private list", "Privat lista", "Private Liste")
        }
        if binding.accountName != accountName {
            return store.text("Waiting for iCloud", "Väntar på iCloud", "Warten auf iCloud")
        }
        if !binding.canWrite {
            return store.text("Shared · read only", "Delad · skrivskyddad", "Geteilt · nur lesen")
        }
        return store.text("Shared with invited people", "Delad med inbjudna personer", "Mit eingeladenen Personen geteilt")
    }

    func resumeIfNeeded() {
        guard startupTask == nil, !persistenceFailed else { return }
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer { self.startupTask = nil }
            await self.syncNow()
        }
    }

    // JSON shopping data is the durable outbox. On every launch we compare it with
    // acknowledged server payloads, so a crash between saving data and engine state
    // cannot lose an edit.
    private func localChanges() {
        guard accountName != nil, !persistenceFailed else { return }
        do { try enqueueChanges() } catch { report(error) }
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard !isSyncing, !persistenceFailed else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        do {
            try await connectAccount()
            let expectedAccount = accountName
            for scope in [CKDatabase.Scope.private, .shared] {
                try await engines[scope]?.fetchChanges()
                guard expectedAccount == accountName else { throw CloudListError.accountChanged }
            }
            try await refreshPermissions()
            try enqueueChanges()
            for scope in [CKDatabase.Scope.private, .shared] {
                try await engines[scope]?.sendChanges()
                guard expectedAccount == accountName else { throw CloudListError.accountChanged }
            }
            if errorMessage == nil { lastSync = Date() }
            updatePendingCount()
        } catch { report(error) }
    }

    private func connectAccount() async throws {
        guard !persistenceFailed else { throw CloudListError.persistence }
        let status = try await container.accountStatus()
        switch status {
        case .available:
            break
        case .noAccount:
            await resetAccount()
            throw CloudListError.noCloudAccount
        case .restricted:
            await resetAccount()
            throw CloudListError.cloudAccountRestricted
        case .couldNotDetermine:
            throw CloudListError.cloudAccountUndetermined
        case .temporarilyUnavailable:
            throw CloudListError.cloudAccountTemporarilyUnavailable
        @unknown default:
            throw CloudListError.cloudAccountUndetermined
        }
        let user = try await container.userRecordID().recordName
        if let accountName, accountName != user { await resetAccount() }
        accountName = user
        disk.lastAccountName = user
        try checkpoint()
        if engines.isEmpty {
            for scope in [CKDatabase.Scope.private, .shared] {
                let database = container.database(with: scope)
                var config = CKSyncEngine.Configuration(
                    database: database, stateSerialization: disk.engineStates[stateKey(scope)], delegate: self)
                config.automaticallySync = true
                config.subscriptionID = "cleverlist-v1-\(scope.rawValue)"
                engines[scope] = CKSyncEngine(config)
            }
        }
        updateAccess()
    }

    private func resetAccount() async {
        let oldEngines = Array(engines.values)
        engines.removeAll()
        accountName = nil
        disk.lastAccountName = nil
        do { try checkpoint() } catch { report(error) }
        updateAccess()
        changeTask?.cancel()
        for engine in oldEngines { await engine.cancelOperations() }
    }

    private func updateAccess() {
        if persistenceFailed {
            store.hiddenCloudListIDs = Set(store.lists.map(\.id))
            store.readOnlyCloudListIDs = store.hiddenCloudListIDs
            return
        }
        store.linkedCloudListIDs = Set(bindings.filter(\.isActive).map(\.id))
        store.hiddenCloudListIDs = Set(bindings.filter {
            (!$0.isActive && !$0.isOwner) || ($0.isActive && $0.accountName != accountName)
        }.map(\.id))
        store.readOnlyCloudListIDs = Set(bindings.filter {
            $0.isActive && (!$0.canWrite || $0.accountName != accountName)
        }.map(\.id))
    }

    private func checkpoint() throws {
        guard !persistenceFailed else { throw CloudListError.persistence }
        disk.bindings = bindings
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(disk).write(to: store.cloudStateURL, options: .atomic)
        } catch {
            persistenceFailed = true
            store.readOnlyCloudListIDs.formUnion(bindings.map(\.id))
            throw CloudListError.persistence
        }
    }

    private func stateKey(_ scope: CKDatabase.Scope) -> String {
        "\(accountName ?? "")|\(scope.rawValue)"
    }

    private func key(_ id: CKRecord.ID) -> String {
        "\(accountName ?? "")|\(id.zoneID.ownerName)|\(id.zoneID.zoneName)|\(id.recordName)"
    }

    private func zoneID(_ binding: CloudListBinding) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: binding.zoneName, ownerName: binding.ownerName)
    }

    private func scope(_ binding: CloudListBinding) -> CKDatabase.Scope {
        binding.isOwner ? .private : .shared
    }

    private func bindingIndex(_ zone: CKRecordZone.ID) -> Int? {
        bindings.firstIndex {
            $0.zoneName == zone.zoneName && $0.ownerName == zone.ownerName &&
                $0.accountName == accountName && $0.isActive
        }
    }

    private func remoteListID(_ binding: CloudListBinding) throws -> UUID {
        guard binding.zoneName.hasPrefix("cleverlist-v1-"),
              let id = UUID(uuidString: String(binding.zoneName.dropFirst("cleverlist-v1-".count))) else {
            throw CloudListError.invalidRecord
        }
        return id
    }

    private func discover(_ zone: CKRecordZone.ID, scope: CKDatabase.Scope) throws {
        guard let accountName, zone.zoneName.hasPrefix("cleverlist-v1-"),
              UUID(uuidString: String(zone.zoneName.dropFirst("cleverlist-v1-".count))) != nil else { return }
        // Inactive bindings are deliberate leaves/revocations, never auto-rejoin them.
        guard !bindings.contains(where: {
            $0.zoneName == zone.zoneName && $0.ownerName == zone.ownerName && $0.accountName == accountName
        }) else { return }
        bindings.append(CloudListBinding(id: UUID(), zoneName: zone.zoneName,
                                        ownerName: zone.ownerName, accountName: accountName,
                                        isOwner: scope == .private, canWrite: scope == .private))
        try checkpoint()
        updateAccess()
    }

    private func encoded(_ payload: CloudListPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard data.count < 800_000 else { throw CloudListError.invalidRecord }
        return data
    }

    private func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func payload(for recordID: CKRecord.ID) throws -> CloudListPayload? {
        guard let index = bindingIndex(recordID.zoneID) else { return nil }
        let binding = bindings[index]
        guard !(binding.retiredRecordNames ?? []).contains(recordID.recordName) else { return nil }
        let remoteID = try remoteListID(binding)
        if recordID.recordName == "list" {
            guard var list = store.lists.first(where: { $0.id == binding.id }) else { return nil }
            list.id = remoteID
            return CloudListPayload(list: list)
        }
        guard let localID = binding.itemIDs[recordID.recordName],
              var item = store.items.first(where: { $0.id == localID && $0.listID == binding.id }),
              let recordUUID = UUID(uuidString: recordID.recordName) else { return nil }
        item.sharedDetails = store.sharingDetails(for: item)
        if let sharedProduct = item.sharedDetails?.product {
            item.productID = sharedProduct.id
        }
        item.id = recordUUID
        item.listID = remoteID
        return CloudListPayload(item: item)
    }

    private func record(for id: CKRecord.ID) throws -> CKRecord? {
        guard let payload = try payload(for: id) else { return nil }
        let record: CKRecord
        if let fields = disk.systemFields[key(id)] {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: fields)
            decoder.requiresSecureCoding = true
            defer { decoder.finishDecoding() }
            guard let restored = CKRecord(coder: decoder) else { throw CloudListError.invalidRecord }
            record = restored
        } else {
            record = CKRecord(recordType: "CleverlistRecord", recordID: id)
        }
        record["payload"] = try encoded(payload) as CKRecordValue
        return record
    }

    private func remember(_ record: CKRecord) throws {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        disk.systemFields[key(record.recordID)] = encoder.encodedData
        if let data = record["payload"] as? Data {
            disk.acknowledged[key(record.recordID)] = fingerprint(data)
        }
    }

    private func enqueueChanges() throws {
        guard !persistenceFailed else { return }
        for index in bindings.indices where bindings[index].isActive &&
            bindings[index].accountName == accountName && bindings[index].canWrite {
            let localListID = bindings[index].id
            for item in store.items where item.listID == localListID {
                if !bindings[index].itemIDs.values.contains(item.id) {
                    bindings[index].itemIDs[item.id.uuidString] = item.id
                }
            }
        }
        // Persist ID routing before giving any outgoing work to CloudKit.
        try checkpoint()
        for binding in bindings where binding.isActive &&
            binding.accountName == accountName && binding.canWrite {
            guard let engine = engines[scope(binding)] else { continue }
            let names = ["list"] + binding.itemIDs.keys.filter { !(binding.retiredRecordNames ?? []).contains($0) }
            for name in names {
                let id = CKRecord.ID(recordName: name, zoneID: zoneID(binding))
                guard let payload = try payload(for: id) else { continue }
                let hash = fingerprint(try encoded(payload))
                if disk.acknowledged[key(id)] != hash {
                    engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                }
            }
        }
        updatePendingCount()
    }

    private func pendingID(_ change: CKSyncEngine.PendingRecordZoneChange) -> CKRecord.ID {
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): id
        @unknown default: CKRecord.ID(recordName: "unsupported")
        }
    }

    private func updatePendingCount() {
        var count = 0
        for binding in bindings where binding.isActive && binding.accountName == accountName && binding.canWrite {
            for name in ["list"] + Array(binding.itemIDs.keys) {
                let id = CKRecord.ID(recordName: name, zoneID: zoneID(binding))
                if let payload = try? payload(for: id), let data = try? encoded(payload),
                   fingerprint(data) != disk.acknowledged[key(id)] { count += 1 }
            }
        }
        pendingCount = count
    }

    private func receive(_ record: CKRecord, engine: CKSyncEngine) throws {
        guard record.recordType == "CleverlistRecord" else { return }
        try discover(record.recordID.zoneID, scope: engine.database.databaseScope)
        // A late delivery for a deliberately retired zone must not reopen it.
        if bindings.contains(where: { !$0.isActive && $0.zoneName == record.recordID.zoneID.zoneName &&
            $0.ownerName == record.recordID.zoneID.ownerName && $0.accountName == accountName }) { return }
        guard let index = bindingIndex(record.recordID.zoneID),
              let data = record["payload"] as? Data, data.count < 800_000 else {
            throw CloudListError.invalidRecord
        }
        let binding = bindings[index]
        guard !(binding.retiredRecordNames ?? []).contains(record.recordID.recordName) else { return }
        let incoming = try JSONDecoder().decode(CloudListPayload.self, from: data)
            .validated(listID: remoteListID(binding), recordName: record.recordID.recordName)
        var list = incoming.list
        list?.id = binding.id
        var item = incoming.item
        if item != nil {
            let name = record.recordID.recordName
            if bindings[index].itemIDs[name] == nil {
                // Remote IDs never overwrite an item in another local/private list.
                bindings[index].itemIDs[name] = UUID()
                try checkpoint()
            }
            item?.id = bindings[index].itemIDs[name] ?? UUID()
            item?.listID = binding.id
        }
        // Save application data before recording a CloudKit change token.
        try store.applyCloud(list: list, item: item, listID: binding.id)
        try remember(record)
        try checkpoint()
        // Requeue only if a newer local revision won over this fetched version.
        if let local = try payload(for: record.recordID),
           fingerprint(try encoded(local)) != disk.acknowledged[key(record.recordID)],
           binding.canWrite {
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        }
    }

    private func refreshPermissions() async throws {
        for binding in bindings where binding.isActive && binding.accountName == accountName && !busyListIDs.contains(binding.id) {
            let expectedAccount = accountName
            let database = container.database(with: scope(binding))
            do {
                let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(binding))
                let record = try await database.record(for: shareID)
                guard expectedAccount == accountName else { throw CloudListError.accountChanged }
                if let share = record as? CKShare, let index = bindingIndex(zoneID(binding)) {
                    bindings[index].canWrite = binding.isOwner || share.currentUserParticipant?.permission == .readWrite
                }
            } catch let error as CKError where [.zoneNotFound, .userDeletedZone, .unknownItem, .permissionFailure].contains(error.code) {
                try deactivate(binding)
            }
        }
        try checkpoint()
        updateAccess()
    }

    private func deactivate(_ binding: CloudListBinding) throws {
        guard let index = bindings.firstIndex(where: { $0.id == binding.id && $0.zoneName == binding.zoneName && $0.ownerName == binding.ownerName && $0.accountName == binding.accountName && $0.isActive }) else { return }
        let zone = zoneID(binding)
        if let engine = engines[scope(binding)] {
            let pending = engine.state.pendingRecordZoneChanges.filter { pendingID($0).zoneID == zone }
            engine.state.remove(pendingRecordZoneChanges: pending)
        }
        // Retain the retired zone so delayed CloudKit events cannot rediscover it.
        // An owner keeps the local list; re-sharing creates an entirely new zone.
        bindings[index].isActive = false
        try checkpoint()
        updateAccess()
        if !binding.isOwner { try store.removeCloudList(binding.id) }
    }

    func prepareShare(for listID: UUID) async throws -> CKShare {
        guard !busyListIDs.contains(listID), !persistenceFailed else { throw CloudListError.unavailable }
        busyListIDs.insert(listID)
        defer { busyListIDs.remove(listID) }
        try await connectAccount()
        guard let accountName,
              let list = store.activeLists.first(where: { $0.id == listID }) else { throw CloudListError.unavailable }
        if let binding = binding(for: listID) {
            guard binding.accountName == accountName else { throw CloudListError.accountChanged }
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(binding))
            do {
                guard let share = try await container.database(with: scope(binding)).record(for: shareID) as? CKShare else {
                    throw CloudListError.invalidRecord
                }
                return share
            } catch let error as CKError where binding.isOwner &&
                [.unknownItem, .zoneNotFound, .userDeletedZone].contains(error.code) {
                // Recover an interrupted initial share or a share removed on another device.
                try deactivate(binding)
                busyListIDs.remove(listID)
                return try await prepareShare(for: listID)
            }
        }
        let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "cleverlist-v1-" + UUID().uuidString,
                                                       ownerName: CKCurrentUserDefaultName))
        _ = try await container.privateCloudDatabase.save(zone)
        guard accountName == self.accountName else { throw CloudListError.accountChanged }
        let binding = CloudListBinding(id: listID, zoneName: zone.zoneID.zoneName,
                                       ownerName: zone.zoneID.ownerName, accountName: accountName, isOwner: true, canWrite: false)
        bindings.append(binding)
        try checkpoint()
        updateAccess()
        let share = CKShare(recordZoneID: zone.zoneID)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = list.name as CKRecordValue
        let headerID = CKRecord.ID(recordName: "list", zoneID: zone.zoneID)
        guard let header = try record(for: headerID) else { throw CloudListError.invalidRecord }
        // Create the header and private share atomically. Items can follow in batches.
        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [header, share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        // A rejected record causes its peers to report batchRequestFailed.
        // Surface the original failure instead of an arbitrary dictionary entry.
        let saveErrors = result.saveResults.sorted {
            $0.key.recordName < $1.key.recordName
        }.compactMap { entry -> Error? in
            if case .failure(let error) = entry.value { return error }
            return nil
        }
        if let error = saveErrors.first(where: { ($0 as? CKError)?.code != .batchRequestFailed })
            ?? saveErrors.first {
            throw error
        }
        guard accountName == self.accountName,
              let savedShare = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw CloudListError.accountChanged
        }
        if let savedHeader = try result.saveResults[headerID]?.get() { try remember(savedHeader) }
        if let index = bindingIndex(zone.zoneID) { bindings[index].canWrite = true }
        busyListIDs.remove(listID)
        try enqueueChanges()
        try await engines[.private]?.sendChanges()
        try checkpoint()
        return savedShare
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            guard metadata.containerIdentifier == Self.containerIdentifier,
                  metadata.share.recordID.zoneID.zoneName.hasPrefix("cleverlist-v1-") else {
                throw CloudListError.invalidRecord
            }
            try await connectAccount()
            let expectedAccount = accountName
            let share = try await container.accept(metadata)
            guard accountName == expectedAccount else { throw CloudListError.accountChanged }
            let zone = share.recordID.zoneID
            // Explicit acceptance may rejoin a previously left invitation.
            bindings.removeAll { !$0.isActive && $0.accountName == accountName &&
                $0.zoneName == zone.zoneName && $0.ownerName == zone.ownerName }
            try discover(zone, scope: .shared)
            try await engines[.shared]?.fetchChanges()
            try await refreshPermissions()
        } catch { report(error) }
    }

    func stopSharing(_ listID: UUID) async throws {
        guard let binding = binding(for: listID), !busyListIDs.contains(listID) else { return }
        busyListIDs.insert(listID)
        defer { busyListIDs.remove(listID) }
        try await connectAccount()
        guard binding.accountName == accountName else { throw CloudListError.accountChanged }
        let database = container.database(with: scope(binding))
        // Cancel in-flight writes before destroying access to this zone.
        await engines[scope(binding)]?.cancelOperations()
        if binding.isOwner {
            _ = try await database.deleteRecordZone(withID: zoneID(binding))
        } else {
            _ = try await database.deleteRecord(withID: CKRecord.ID(
                recordName: CKRecordNameZoneWideShare, zoneID: zoneID(binding)))
        }
        try deactivate(binding)
    }

    func removeParticipant(_ participant: CKShare.Participant, from share: CKShare,
                           listID: UUID) async throws -> CKShare {
        try await connectAccount()
        guard let binding = binding(for: listID), binding.isOwner,
              binding.accountName == accountName, share.recordID.zoneID == zoneID(binding),
              participant.role != .owner else { throw CloudListError.notOwner }
        share.removeParticipant(participant)
        guard let saved = try await container.privateCloudDatabase.save(share) as? CKShare else {
            throw CloudListError.invalidRecord
        }
        return saved
    }

    func sharingSettingsChanged() {
        resumeIfNeeded()
    }

    private func report(_ error: Error) {
        if let cloudError = error as? CKError, [.networkFailure, .networkUnavailable, .serviceUnavailable].contains(cloudError.code) {
            errorMessage = store.text("Waiting for iCloud. Your edits are saved on this device; retry when connected.",
                                      "Väntar på iCloud. Dina ändringar är sparade på enheten; försök igen när du är ansluten.",
                                      "Warten auf iCloud. Deine Änderungen sind auf diesem Gerät gespeichert; versuche es mit Verbindung erneut.")
        } else {
            errorMessage = error.localizedDescription
        }
    }

    func requestNotifications() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { report(error) }
    }

    private func notify(_ items: [ShoppingItem]) {
        for item in items where !store.matchingRules(for: item).isEmpty {
            let content = UNMutableNotificationContent()
            content.title = "Cleverlist"
            content.body = store.product(for: item).map { store.name($0.name) } ??
                store.text("Shared list updated", "Delad lista uppdaterad", "Geteilte Liste aktualisiert")
            content.sound = .default
            Task { try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)) }
        }
    }
}

extension CloudSyncService: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engines[syncEngine.database.databaseScope] === syncEngine, !persistenceFailed else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                disk.engineStates[stateKey(syncEngine.database.databaseScope)] = update.stateSerialization
                try checkpoint()
            case .accountChange(let change):
                if case .signIn(let user) = change.changeType, user.recordName == accountName {
                    break
                }
                await resetAccount()
                resumeIfNeeded()
            case .fetchedDatabaseChanges(let changes):
                for modification in changes.modifications {
                    try discover(modification.zoneID, scope: syncEngine.database.databaseScope)
                }
                for deletion in changes.deletions {
                    if let index = bindingIndex(deletion.zoneID) { try deactivate(bindings[index]) }
                }
            case .fetchedRecordZoneChanges(let changes):
                for modification in changes.modifications {
                    try receive(modification.record, engine: syncEngine)
                }
                for deletion in changes.deletions {
                    if deletion.recordID.recordName == "list" ||
                        deletion.recordID.recordName == CKRecordNameZoneWideShare {
                        if let index = bindingIndex(deletion.recordID.zoneID) { try deactivate(bindings[index]) }
                    } else if let index = bindingIndex(deletion.recordID.zoneID),
                              let id = bindings[index].itemIDs[deletion.recordID.recordName],
                              var item = store.items.first(where: { $0.id == id && $0.listID == bindings[index].id }) {
                        item.isDeleted = true
                        item.revision += 1
                        bindings[index].retiredRecordNames = (bindings[index].retiredRecordNames ?? [])
                            .union([deletion.recordID.recordName])
                        try checkpoint()
                        try store.applyCloud(list: nil, item: item, listID: bindings[index].id)
                        disk.systemFields.removeValue(forKey: key(deletion.recordID))
                        disk.acknowledged.removeValue(forKey: key(deletion.recordID))
                        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(deletion.recordID)])
                    }
                }
            case .sentRecordZoneChanges(let changes):
                for record in changes.savedRecords { try remember(record) }
                for failure in changes.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged,
                       let serverRecord = failure.error.serverRecord {
                        try receive(serverRecord, engine: syncEngine)
                    } else if failure.error.code == .permissionFailure,
                              let index = bindingIndex(failure.record.recordID.zoneID) {
                        bindings[index].canWrite = false
                        let zone = failure.record.recordID.zoneID
                        syncEngine.state.remove(pendingRecordZoneChanges:
                            syncEngine.state.pendingRecordZoneChanges.filter { pendingID($0).zoneID == zone })
                        updateAccess()
                        report(failure.error)
                    } else if [.zoneNotFound, .userDeletedZone].contains(failure.error.code),
                              let index = bindingIndex(failure.record.recordID.zoneID) {
                        try deactivate(bindings[index])
                        report(failure.error)
                    } else {
                        // The engine retries transient failures; re-enqueue durable
                        // edits on the next foreground/retry for other failures.
                        report(failure.error)
                    }
                }
                try checkpoint()
                // Only requeue successful writes whose local content changed in flight.
                // Requeuing permanent failures here would spin inside a send operation.
                for record in changes.savedRecords {
                    if let local = try payload(for: record.recordID),
                       fingerprint(try encoded(local)) != disk.acknowledged[key(record.recordID)] {
                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
                    }
                }
            case .didFetchRecordZoneChanges(let result):
                if let error = result.error { report(error) }
            default:
                break
            }
            updatePendingCount()
        } catch {
            report(error)
            // Never acknowledge a cursor after failing to persist fetched records.
            if error is DecodingError || (error as? CloudListError) != nil {
                persistenceFailed = true
            }
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                  syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engines[syncEngine.database.databaseScope] === syncEngine, !persistenceFailed else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { change in
            guard context.options.scope.contains(change),
                  let index = bindingIndex(pendingID(change).zoneID) else { return false }
            return bindings[index].canWrite && !busyListIDs.contains(bindings[index].id)
        }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            guard let self else { return nil }
            return await self.outgoingRecord(id)
        }
    }

    private func outgoingRecord(_ id: CKRecord.ID) -> CKRecord? {
        do { return try record(for: id) }
        catch { report(error); return nil }
    }
}

extension CloudSyncService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
