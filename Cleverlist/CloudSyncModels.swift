import Foundation

// Shared names travel with an item, never as a global catalog snapshot.
struct SharedItemDetails: Codable, Hashable {
    var product: Product?
    var terms: [CatalogTerm]
}

struct CloudListBinding: Codable, Identifiable, Equatable {
    var id: UUID
    var zoneName: String
    var ownerName: String
    var accountName: String
    var isOwner: Bool
    var isActive = true
    var canWrite = true
    var itemIDs: [String: UUID] = [:]
    var retiredRecordNames: Set<String>?
}

struct CloudListPayload: Codable {
    var version = 1
    var list: ShoppingList?
    var item: ShoppingItem?

    func validated(listID: UUID, recordName: String) throws -> CloudListPayload {
        guard version == 1 else { throw CloudListError.invalidRecord }
        if recordName == "list" {
            guard let list, list.id == listID, item == nil else { throw CloudListError.invalidRecord }
        } else {
            guard let item, item.listID == listID, list == nil,
                  item.id.uuidString == recordName, let details = item.sharedDetails,
                  details.product.map({ $0.id == item.productID && $0.storeIDs.isEmpty }) ?? true else {
                throw CloudListError.invalidRecord
            }
            let allowed = Set([item.unitID, details.product?.typeID, details.product?.sectionID].compactMap { $0 })
            guard details.terms.allSatisfy({ allowed.contains($0.id) }) else { throw CloudListError.invalidRecord }
        }
        return self
    }
}

enum CloudListError: LocalizedError {
    case invalidRecord, unavailable, persistence, accountChanged, notOwner
    case noCloudAccount, cloudAccountRestricted, cloudAccountUndetermined, cloudAccountTemporarilyUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "This invitation or shared record is not a valid Cleverlist list."
        case .unavailable: "Sharing is not available for this list right now. Try again shortly."
        case .noCloudAccount: "CloudKit reports no iCloud account on this device. Check the Apple Account in Settings on the device running Cleverlist. If using Simulator, sign in inside Simulator."
        case .cloudAccountRestricted: "Access to iCloud is restricted on this device. Check Screen Time or device management restrictions."
        case .cloudAccountUndetermined: "CloudKit could not determine your iCloud account status. Check your connection and try again."
        case .cloudAccountTemporarilyUnavailable: "Your iCloud account is temporarily unavailable to CloudKit. Try again shortly."
        case .persistence: "Changes could not be saved on this device. Sync is paused to protect your lists."
        case .accountChanged: "The iCloud account changed. Reopen sharing with the original account."
        case .notOwner: "Only the list owner can manage invitations."
        }
    }
}

// The same ordering is used for normal fetches and CloudKit save conflicts.
enum CloudListConflict {
    static func incomingWins<T: SyncRecord>(_ incoming: T, over current: T) -> Bool {
        incoming.revision > current.revision ||
            (incoming.revision == current.revision && incoming.deviceID > current.deviceID)
    }
}
