import Foundation

enum Language: String, Codable, CaseIterable, Identifiable {
    case sv, de, en
    var id: String { rawValue }
    var title: String {
        switch self { case .sv: "Svenska"; case .de: "Deutsch"; case .en: "English" }
    }
}

struct LocalizedName: Codable, Hashable {
    var sv: String
    var de: String
    var en: String
    func value(_ language: Language) -> String {
        switch language { case .sv: sv; case .de: de; case .en: en }
    }
}

protocol SyncRecord: Codable, Identifiable where ID == UUID {
    var modifiedAt: Date { get set }
    var revision: Int { get set }
    var deviceID: String { get set }
    var isDeleted: Bool { get set }
}

enum CatalogKind: String, Codable, CaseIterable, Identifiable {
    case store, type, section, unit
    var id: String { rawValue }
}

struct CatalogTerm: SyncRecord, Hashable {
    var id = UUID()
    var name: LocalizedName
    var kind: CatalogKind
    var colorHex = "#FF926B"
    var modifiedAt = Date()
    var revision = 0
    var deviceID = ""
    var isDeleted = false
}

struct Product: SyncRecord, Hashable {
    var id = UUID()
    var name: LocalizedName
    var storeIDs: [UUID] = []
    // Identifies the originating product when this is a local copy from a shared list.
    // The local identifier remains private so each person can edit their own catalog copy.
    var sharedProductID: UUID?
    var typeID: UUID?
    var sectionID: UUID?
    var modifiedAt = Date()
    var revision = 0
    var deviceID = ""
    var isDeleted = false
}

struct StoreLocation: SyncRecord, Hashable {
    var id = UUID()
    var name: String
    var storeID: UUID?
    var sectionOrder: [UUID] = []
    var modifiedAt = Date()
    var revision = 0
    var deviceID = ""
    var isDeleted = false
}

struct ShoppingList: SyncRecord, Hashable {
    var id = UUID()
    var name: String
    var modifiedAt = Date()
    var revision = 0
    var deviceID = ""
    var isDeleted = false
}

struct ShoppingItem: SyncRecord, Hashable {
    var id = UUID()
    var listID: UUID
    var productID: UUID
    var amount = ""
    var unitID: UUID?
    var comment = ""
    var isChecked = false
    var colorHex: String?
    var sharedDetails: SharedItemDetails?
    var modifiedAt = Date()
    var revision = 0
    var deviceID = ""
    var isDeleted = false
}

struct NotificationRule: SyncRecord, Hashable {
    var id = UUID()
    var name: String
    var listID: UUID?
    var storeID: UUID?
    var typeID: UUID?
    var sectionID: UUID?
    var namePattern = "*"
    var isEnabled = true
    var modifiedAt = Date()
    var revision = 0
    var deviceID = ""
    var isDeleted = false
}

struct ShoppingDatabase: Codable {
    var lists: [ShoppingList] = []
    var items: [ShoppingItem] = []
}

struct CatalogDatabase: Codable {
    var terms: [CatalogTerm] = []
    var products: [Product] = []
    var locations: [StoreLocation] = []
}

struct SyncSnapshot: Codable {
    var schemaVersion = 1
    var shopping: ShoppingDatabase
    var catalog: CatalogDatabase
}
