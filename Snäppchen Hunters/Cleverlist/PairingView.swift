import SwiftUI
import CloudKit
import CoreTransferable

struct ListShareInvitation: Transferable {
    let share: CKShare
    let container: CKContainer

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invitation in
            .existing(invitation.share, container: invitation.container,
                      allowedSharingOptions: CKAllowedSharingOptions(
                        allowedParticipantPermissionOptions: .readWrite,
                        allowedParticipantAccessOptions: .specifiedRecipientsOnly))
        }
    }
}

struct CloudSharingSettingsView: View {
    let store: CleverlistStore
    let sync: CloudSyncService

    var body: some View {
        Form {
            Section {
                Text(store.text("Lists stay private until you share them. Invite people separately for each list.",
                                "Listor är privata tills du delar dem. Bjud in personer separat för varje lista.",
                                "Listen bleiben privat, bis du sie teilst. Lade Personen für jede Liste einzeln ein."))
                ForEach(store.activeLists) { list in
                    NavigationLink {
                        ListSharingView(store: store, sync: sync, listID: list.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(list.name)
                            Text(sync.status(for: list.id)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            CloudSyncStatusSection(store: store, sync: sync)
        }
        .formStyle(.grouped)
        .navigationTitle(store.text("iCloud sharing", "iCloud-delning", "iCloud-Freigaben"))
    }
}

struct CloudSyncStatusSection: View {
    let store: CleverlistStore
    let sync: CloudSyncService

    var body: some View {
        Section(store.text("Sync", "Synkronisering", "Synchronisierung")) {
            if sync.isSyncing {
                ProgressView(store.text("Syncing with iCloud…", "Synkar med iCloud…", "Mit iCloud synchronisieren…"))
            } else if sync.pendingCount > 0 {
                Text(store.text("Changes waiting to upload", "Ändringar väntar på uppladdning", "Änderungen warten auf Upload"))
            }
            if let lastSync = sync.lastSync {
                LabeledContent(store.text("Last sync", "Senaste synk", "Letzte Synchronisierung")) {
                    Text(lastSync, style: .relative)
                }
            }
            if let error = sync.errorMessage { Text(error).foregroundStyle(.red) }
            Button(store.text("Sync now", "Synka nu", "Jetzt synchronisieren")) {
                Task { await sync.syncNow() }
            }.disabled(sync.isSyncing)
            Text(store.text("Edits save on this device first and sync when iCloud is available.",
                            "Ändringar sparas först på enheten och synkas när iCloud är tillgängligt.",
                            "Änderungen werden zuerst auf diesem Gerät gespeichert und bei verfügbarer iCloud synchronisiert."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ListSharingView: View {
    let store: CleverlistStore
    let sync: CloudSyncService
    let listID: UUID
    @State private var share: CKShare?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmingStop = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var isOwner: Bool { sync.binding(for: listID)?.isOwner ?? true }

    var body: some View {
        Form {
            Section {
                Label(sync.status(for: listID), systemImage: sync.binding(for: listID) == nil ? "lock" : "person.2")
                Text(store.text("Only this list and its items are included. Your other lists and catalog remain private.",
                                "Endast denna lista och dess varor ingår. Dina andra listor och din katalog förblir privata.",
                                "Nur diese Liste und ihre Artikel werden geteilt. Andere Listen und dein Katalog bleiben privat."))
                    .font(.callout)
                if let share {
                    if isOwner {
                        ShareLink(item: ListShareInvitation(share: share, container: sync.container),
                                  preview: SharePreview(store.activeLists.first { $0.id == listID }?.name ?? "Cleverlist")) {
                            Label(store.text("Invite people", "Bjud in personer", "Personen einladen"), systemImage: "person.badge.plus")
                        }
                    }
                    ShareParticipantsSection(store: store, share: share, isOwner: isOwner, isWorking: isWorking) { participant in
                        Task {
                            isWorking = true
                            defer { isWorking = false }
                            do { self.share = try await sync.removeParticipant(participant, from: share, listID: listID) }
                            catch { errorMessage = error.localizedDescription; isWorking = false; await loadShare() }
                        }
                    }
                } else {
                    Button(store.text("Set up sharing", "Aktivera delning", "Freigabe einrichten")) {
                        Task { await loadShare() }
                    }.disabled(isWorking)
                }
                if isWorking { ProgressView() }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            if sync.binding(for: listID) != nil {
                Section {
                    Button(isOwner
                           ? store.text("Stop sharing", "Sluta dela", "Freigabe beenden")
                           : store.text("Leave list", "Lämna lista", "Liste verlassen"), role: .destructive) {
                        confirmingStop = true
                    }.disabled(isWorking)
                }
            }
            CloudSyncStatusSection(store: store, sync: sync)
        }
        .formStyle(.grouped)
        .navigationTitle(store.text("Share list", "Dela lista", "Liste teilen"))
        .confirmationDialog(store.text("Change sharing?", "Ändra delning?", "Freigabe ändern?"),
                            isPresented: $confirmingStop, titleVisibility: .visible) {
            Button(isOwner ? store.text("Stop sharing", "Sluta dela", "Freigabe beenden")
                   : store.text("Leave list", "Lämna lista", "Liste verlassen"), role: .destructive) {
                Task {
                    let wasOwner = isOwner
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        try await sync.stopSharing(listID)
                        share = nil
                        if !wasOwner { dismiss() }
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text(isOwner
                 ? store.text("Others will lose access. Your list stays on this device.",
                              "Andra förlorar åtkomsten. Din lista finns kvar på enheten.",
                              "Andere verlieren den Zugriff. Deine Liste bleibt auf diesem Gerät.")
                 : store.text("This list will be removed from this device. Others keep their access.",
                              "Listan tas bort från enheten. Andra behåller sin åtkomst.",
                              "Diese Liste wird von diesem Gerät entfernt. Andere behalten ihren Zugriff."))
        }
        .task { if sync.binding(for: listID) != nil { await loadShare() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && sync.binding(for: listID) != nil {
                Task { await loadShare() }
            }
        }
    }

    private func loadShare() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do { share = try await sync.prepareShare(for: listID); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ShareParticipantsSection: View {
    let store: CleverlistStore
    let share: CKShare
    let isOwner: Bool
    let isWorking: Bool
    let remove: (CKShare.Participant) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.text("People", "Personer", "Personen")).font(.headline)
            ForEach(share.participants, id: \.self) { participant in
                HStack {
                    VStack(alignment: .leading) {
                        Text(participant.userIdentity.nameComponents.map {
                            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                        } ?? store.text("Invited person", "Inbjuden person", "Eingeladene Person"))
                        Text(participant.role == .owner
                             ? store.text("Owner", "Ägare", "Eigentümer")
                             : participant.acceptanceStatus == .accepted
                             ? store.text("Joined", "Har anslutit", "Beigetreten")
                             : store.text("Invited", "Inbjuden", "Eingeladen"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isOwner && participant.role != .owner {
                        Button(store.text("Remove", "Ta bort", "Entfernen"), role: .destructive) {
                            remove(participant)
                        }.disabled(isWorking)
                    }
                }
            }
        }
    }
}
