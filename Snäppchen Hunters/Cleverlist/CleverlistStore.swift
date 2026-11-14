import Foundation
import Observation

@MainActor @Observable
final class CleverlistStore {
    var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "hunter.language") }
    }
    var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "hunter.theme") }
    }
    var lists: [ShoppingList] = []
    var items: [ShoppingItem] = []
    var terms: [CatalogTerm] = []
    var products: [Product] = []
    var locations: [StoreLocation] = []
    var rules: [NotificationRule] = []
    var hiddenCloudListIDs: Set<UUID> = []
    var readOnlyCloudListIDs: Set<UUID> = []
    var linkedCloudListIDs: Set<UUID> = []
    var lastError: String?
    let deviceID: String
    @ObservationIgnored var onRemoteItemsChanged: (([ShoppingItem]) -> Void)?
    @ObservationIgnored var onLocalChange: (() -> Void)?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var loadingFailed = false

    init(directory: URL? = nil) {
        let defaults = UserDefaults.standard
        deviceID = defaults.string(forKey: "hunter.device") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "hunter.device")
        language = Language(rawValue: defaults.string(forKey: "hunter.language") ?? String(Locale.current.language.languageCode?.identifier ?? "en")) ?? .en
        theme = Theme(rawValue: defaults.string(forKey: "hunter.theme") ?? "summer") ?? .summer
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("SnappchenHunters", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let shoppingURL = self.directory.appendingPathComponent("shopping.json")
            let catalogURL = self.directory.appendingPathComponent("catalog.json")
            if FileManager.default.fileExists(atPath: shoppingURL.path) {
                let db = try JSONDecoder().decode(ShoppingDatabase.self, from: Data(contentsOf: shoppingURL))
                lists = db.lists
                items = db.items
            }
            if FileManager.default.fileExists(atPath: catalogURL.path) {
                let db = try JSONDecoder().decode(CatalogDatabase.self, from: Data(contentsOf: catalogURL))
                terms = db.terms
                products = db.products
                locations = db.locations
            } else {
                seedCatalog()
            }
            migrateCatalogExpansion()
            let rulesURL = self.directory.appendingPathComponent("notification-rules.json")
            if FileManager.default.fileExists(atPath: rulesURL.path) {
                rules = try JSONDecoder().decode([NotificationRule].self, from: Data(contentsOf: rulesURL))
            }
            if !FileManager.default.fileExists(atPath: shoppingURL.path) {
                lists = [ShoppingList(name: text("Weekly groceries", "Veckohandling", "Wocheneinkauf"))]
            }
            persist()
        } catch {
            loadingFailed = true
            lastError = text("Could not load saved data: ", "Kunde inte läsa sparade data: ", "Gespeicherte Daten konnten nicht geladen werden: ") + error.localizedDescription
        }
    }

    var activeLists: [ShoppingList] { lists.filter { !$0.isDeleted && !hiddenCloudListIDs.contains($0.id) } }
    var activeProducts: [Product] {
        products.filter { !$0.isDeleted && !GroceryDrugstoreCatalog.isRetiredVariant($0) }
            .map { GroceryDrugstoreCatalog.consolidated($0) }
    }
    var customProducts: [Product] {
        // Bundled products use the reserved numeric UUID namespace; user-created
        // products have random UUIDs, including those saved by older app versions.
        activeProducts.filter { !$0.id.uuidString.hasPrefix("00000000-0000-0000-0000-") }
            .sorted { name($0.name).localizedStandardCompare(name($1.name)) == .orderedAscending }
    }

    var activeLocations: [StoreLocation] { locations.filter { !$0.isDeleted } }
    var activeRules: [NotificationRule] { rules.filter { !$0.isDeleted } }
    func catalog(_ kind: CatalogKind) -> [CatalogTerm] {
        terms.filter { !$0.isDeleted && $0.kind == kind }.sorted { name($0.name).localizedStandardCompare(name($1.name)) == .orderedAscending }
    }
    func items(in listID: UUID) -> [ShoppingItem] {
        guard !hiddenCloudListIDs.contains(listID) else { return [] }
        return items.filter { !$0.isDeleted && $0.listID == listID }
    }

    var cloudStateURL: URL { directory.appendingPathComponent("cloud-sync.json") }

    func canEdit(_ listID: UUID) -> Bool {
        !hiddenCloudListIDs.contains(listID) && !readOnlyCloudListIDs.contains(listID)
    }

    func product(for item: ShoppingItem) -> Product? {
        if let details = item.sharedDetails { return details.product }
        return product(item.productID)
    }

    func term(_ id: UUID?, for item: ShoppingItem) -> CatalogTerm? {
        if let details = item.sharedDetails { return details.terms.first { $0.id == id } }
        return term(id)
    }

    func sharingDetails(for item: ShoppingItem) -> SharedItemDetails {
        if let details = item.sharedDetails { return details }
        var product = product(item.productID)
        // Store affiliations and unrelated catalog entries are device-private.
        product?.storeIDs = []
        // A local copy keeps a private catalog identifier, but shared lists use the
        // originating identifier so participants can recognize the same product later.
        if let sharedProductID = product?.sharedProductID {
            product?.id = sharedProductID
        }
        let ids = Set([item.unitID, product?.typeID, product?.sectionID].compactMap { $0 })
        return SharedItemDetails(product: product, terms: terms.filter { ids.contains($0.id) && !$0.isDeleted })
    }

    func applyCloud(list: ShoppingList?, item: ShoppingItem?, listID: UUID) throws {
        let previousLists = lists
        let previousItems = items
        let previousProducts = products
        if let list {
            guard list.id == listID else { throw CloudListError.invalidRecord }
            _ = mergeRecords([list], into: &lists)
        }

        var localizedItem = item
        if var item {
            guard item.listID == listID,
                  !items.contains(where: { $0.id == item.id && $0.listID != listID }) else {
                throw CloudListError.invalidRecord
            }

            if let existing = items.first(where: { $0.id == item.id && $0.listID == listID }),
               products.contains(where: { $0.id == existing.productID && !$0.isDeleted }) {
                // Preserve the recipient's existing local catalog assignment on updates.
                item.productID = existing.productID
                item.sharedDetails = nil
            } else if let sharedProduct = item.sharedDetails?.product {
                let sourceProductID = sharedProduct.sharedProductID ?? sharedProduct.id
                if let localProduct = products.first(where: {
                    !$0.isDeleted && ($0.id == sourceProductID || $0.sharedProductID == sourceProductID)
                }) {
                    // This product was already added from this shared group. Reuse the
                    // recipient's manual item instead of creating a duplicate.
                    item.productID = localProduct.id
                } else {
                    // A shared item is represented locally by a private custom product.
                    // Type, section, and stores intentionally start unset so each
                    // recipient can choose their own organization independently.
                    let localProduct = Product(
                        name: sharedProduct.name,
                        sharedProductID: sourceProductID
                    )
                    upsert(localProduct, in: &products)
                    item.productID = localProduct.id
                }
                item.sharedDetails = nil
            }

            localizedItem = item
            _ = mergeRecords([item], into: &items)
        }

        guard persist() else {
            lists = previousLists
            items = previousItems
            products = previousProducts
            throw CloudListError.persistence
        }
        if let localizedItem, !previousItems.contains(localizedItem) {
            onRemoteItemsChanged?([localizedItem])
        }
    }

    func removeCloudList(_ listID: UUID) throws {
        let previousLists = lists
        let previousItems = items
        lists.removeAll { $0.id == listID }
        items.removeAll { $0.listID == listID }
        guard persist() else {
            lists = previousLists
            items = previousItems
            throw CloudListError.persistence
        }
    }
    func product(_ id: UUID) -> Product? {
        products.first { $0.id == id && !$0.isDeleted }.map { GroceryDrugstoreCatalog.consolidated($0) }
    }
    func term(_ id: UUID?) -> CatalogTerm? { terms.first { $0.id == id && !$0.isDeleted } }
    func name(_ value: LocalizedName) -> String { value.value(language) }
    func text(_ en: String, _ sv: String, _ de: String) -> String {
        switch language { case .en: en; case .sv: sv; case .de: de }
    }

    func save(_ record: ShoppingList) { guard canEdit(record.id) else { return }; upsert(record, in: &lists); save() }
    func save(_ record: ShoppingItem) {
        guard canEdit(record.listID) else { return }
        var value = record
        if var details = value.sharedDetails,
           let previous = items.first(where: { $0.id == value.id }), previous.unitID != value.unitID {
            let referenced = Set([details.product?.typeID, details.product?.sectionID].compactMap { $0 })
            details.terms.removeAll { !referenced.contains($0.id) }
            if let unit = term(value.unitID), !details.terms.contains(where: { $0.id == unit.id }) {
                details.terms.append(unit)
            }
            value.sharedDetails = details
        }
        upsert(value, in: &items)
        save()
    }
    func save(_ record: CatalogTerm) { upsert(record, in: &terms); save() }
    func save(_ record: Product) { upsert(record, in: &products); save() }
    func save(_ record: StoreLocation) { upsert(record, in: &locations); save() }
    func save(_ record: NotificationRule) { upsert(record, in: &rules); save() }
    func delete(_ record: ShoppingList) {
        guard canEdit(record.id), !linkedCloudListIDs.contains(record.id) else { return }
        var value = record
        value.isDeleted = true
        upsert(value, in: &lists)
        for item in items(in: record.id) {
            var deleted = item
            deleted.isDeleted = true
            upsert(deleted, in: &items)
        }
        save()
    }
    func delete(_ record: ShoppingItem) { var v = record; v.isDeleted = true; save(v) }
    func delete(_ record: CatalogTerm) { var v = record; v.isDeleted = true; save(v) }
    func delete(_ record: Product) {
        // Keep existing shopping entries readable after removing a catalog product.
        // These snapshots are local metadata; deleting a catalog entry does not
        // change the contents of a shared shopping list.
        for index in items.indices where items[index].productID == record.id && items[index].sharedDetails == nil {
            items[index].sharedDetails = sharingDetails(for: items[index])
        }
        var value = record
        value.isDeleted = true
        save(value)
    }
    func delete(_ record: StoreLocation) { var v = record; v.isDeleted = true; save(v) }
    func delete(_ record: NotificationRule) { var v = record; v.isDeleted = true; save(v) }

    private func upsert<T: SyncRecord>(_ record: T, in records: inout [T]) {
        var value = record
        value.revision = max(record.revision, records.first(where: { $0.id == record.id })?.revision ?? 0) + 1
        value.modifiedAt = Date()
        value.deviceID = deviceID
        if let index = records.firstIndex(where: { $0.id == value.id }) { records[index] = value }
        else { records.append(value) }
    }

    func save() {
        if persist() { onLocalChange?() }
    }

    @discardableResult private func persist() -> Bool {
        guard !loadingFailed else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(ShoppingDatabase(lists: lists, items: items)).write(to: directory.appendingPathComponent("shopping.json"), options: .atomic)
            try encoder.encode(CatalogDatabase(terms: terms, products: products, locations: locations)).write(to: directory.appendingPathComponent("catalog.json"), options: .atomic)
            try encoder.encode(rules).write(to: directory.appendingPathComponent("notification-rules.json"), options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = text("Could not save data: ", "Kunde inte spara data: ", "Daten konnten nicht gespeichert werden: ") + error.localizedDescription
            return false
        }
    }

    func snapshotData() throws -> Data {
        try JSONEncoder().encode(SyncSnapshot(shopping: ShoppingDatabase(lists: lists, items: items), catalog: CatalogDatabase(terms: terms, products: products, locations: locations)))
    }

    @discardableResult func merge(data: Data) throws -> Int {
        let incoming = try JSONDecoder().decode(SyncSnapshot.self, from: data)
        guard incoming.schemaVersion == 1 else { throw CocoaError(.fileReadUnknown) }
        let previousShopping = ShoppingDatabase(lists: lists, items: items)
        let previousCatalog = CatalogDatabase(terms: terms, products: products, locations: locations)
        let oldItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var count = mergeRecords(incoming.shopping.lists, into: &lists)
        count += mergeRecords(incoming.shopping.items, into: &items)
        count += mergeRecords(incoming.catalog.terms, into: &terms)
        count += mergeRecords(incoming.catalog.products, into: &products)
        count += mergeRecords(incoming.catalog.locations, into: &locations)
        if count > 0 {
            guard persist() else {
                // Keep the snapshot retryable after a disk error.
                lists = previousShopping.lists
                items = previousShopping.items
                terms = previousCatalog.terms
                products = previousCatalog.products
                locations = previousCatalog.locations
                throw CocoaError(.fileWriteUnknown)
            }
            onRemoteItemsChanged?(items.filter { oldItems[$0.id] != $0 })
        }
        return count
    }

    // Revision is a per-record logical clock. Device ID resolves concurrent edits
    // deterministically, and tombstones keep deleted records from resurfacing.
    private func mergeRecords<T: SyncRecord>(_ incoming: [T], into local: inout [T]) -> Int {
        var count = 0
        for value in incoming {
            if let index = local.firstIndex(where: { $0.id == value.id }) {
                let current = local[index]
                let wins = CloudListConflict.incomingWins(value, over: current)
                if wins { local[index] = value; count += 1 }
            } else {
                local.append(value)
                count += 1
            }
        }
        return count
    }

    func matchingRules(for item: ShoppingItem) -> [NotificationRule] {
        guard let product = product(for: item) else { return [] }
        return activeRules.filter { rule in
            guard rule.isEnabled,
                  rule.listID == nil || rule.listID == item.listID,
                  rule.storeID.map({ product.storeIDs.isEmpty || product.storeIDs.contains($0) }) ?? true,
                  rule.typeID == nil || rule.typeID == product.typeID,
                  rule.sectionID == nil || rule.sectionID == product.sectionID else { return false }
            let pattern = rule.namePattern.isEmpty ? "*" : rule.namePattern
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            return name(product.name).range(of: "^" + escaped + "$", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private func migrateCatalogExpansion() {
        // Include tombstones in the ID sets: an upgrade must never restore a
        // deleted seed or overwrite names and routes customized by the user.
        let termIDs = Set(terms.map(\.id))
        let productIDs = Set(products.map(\.id))
        let locationIDs = Set(locations.map(\.id))
        terms.append(contentsOf: CatalogExpansion.terms.filter { !termIDs.contains($0.id) })
        products.append(contentsOf: CatalogExpansion.products.filter { !productIDs.contains($0.id) })
        locations.append(contentsOf: CatalogExpansion.locations.filter { !locationIDs.contains($0.id) })
    }

    private func seedCatalog() {
        // Stable IDs allow independently installed catalogs to merge without duplicates.
        func stable(_ number: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
        }
        func term(_ number: Int, _ kind: CatalogKind, _ sv: String, _ de: String, _ en: String, _ color: String) {
            terms.append(CatalogTerm(id: stable(number), name: LocalizedName(sv: sv, de: de, en: en), kind: kind, colorHex: color, modifiedAt: Date(timeIntervalSince1970: 0)))
        }
        term(1, .store, "ICA", "ICA", "ICA", "#ED5A65")
        term(2, .store, "Coop", "Coop", "Coop", "#55B97D")
        term(3, .store, "Lidl", "Lidl", "Lidl", "#5089E8")
        term(4, .store, "Hemköp", "Hemköp", "Hemköp", "#D34B67")
        term(10, .type, "Mat", "Lebensmittel", "Food", "#FFB655")
        term(11, .type, "Hygien", "Hygiene", "Hygiene", "#BA91ED")
        term(12, .type, "Hushåll", "Haushalt", "Household", "#63C7C1")
        term(13, .type, "Kläder", "Kleidung", "Clothing", "#EE8BBC")
        term(14, .type, "Fritid", "Freizeit", "Entertainment", "#7F9EED")
        term(20, .section, "Frukt & grönt", "Obst & Gemüse", "Produce", "#75C783")
        term(21, .section, "Bageri", "Backwaren", "Bakery", "#E7AF63")
        term(22, .section, "Mejeri", "Milchprodukte", "Dairy", "#74BFE4")
        term(23, .section, "Skafferi", "Vorräte", "Pantry", "#E7A175")
        term(24, .section, "Frys", "Tiefkühl", "Frozen", "#8CAFE8")
        term(25, .section, "Hygien", "Körperpflege", "Personal care", "#C59DE6")
        term(26, .section, "Kök", "Küche", "Kitchen", "#65C4BC")
        term(27, .section, "Kläder", "Kleidung", "Clothing", "#EC91B5")
        term(28, .section, "Underhållning", "Unterhaltung", "Entertainment", "#929CE0")
        term(30, .unit, "stycken", "Stück", "pieces", "#A0A0A0")
        term(31, .unit, "paket", "Packungen", "packages", "#A0A0A0")
        term(32, .unit, "gram", "Gramm", "grams", "#A0A0A0")
        term(33, .unit, "kilogram", "Kilogramm", "kilograms", "#A0A0A0")
        term(34, .unit, "liter", "Liter", "liters", "#A0A0A0")
        term(35, .unit, "milliliter", "Milliliter", "milliliters", "#A0A0A0")
        let seeds: [(String, String, String, Int, Int)] = [
            ("Mjölk", "Milch", "Milk", 10, 22), ("Ägg", "Eier", "Eggs", 10, 22),
            ("Bröd", "Brot", "Bread", 10, 21), ("Bananer", "Bananen", "Bananas", 10, 20),
            ("Äpplen", "Äpfel", "Apples", 10, 20), ("Tomater", "Tomaten", "Tomatoes", 10, 20),
            ("Pasta", "Nudeln", "Pasta", 10, 23), ("Ris", "Reis", "Rice", 10, 23),
            ("Kaffe", "Kaffee", "Coffee", 10, 23), ("Ost", "Käse", "Cheese", 10, 22),
            ("Yoghurt", "Joghurt", "Yogurt", 10, 22), ("Glass", "Eis", "Ice cream", 10, 24),
            ("Tandkräm", "Zahnpasta", "Toothpaste", 11, 25), ("Schampo", "Shampoo", "Shampoo", 11, 25),
            ("Diskmedel", "Spülmittel", "Dish soap", 12, 26), ("Potatis", "Kartoffeln", "Potatoes", 10, 20),
            ("Smör", "Butter", "Butter", 10, 22), ("Havremjölk", "Hafermilch", "Oat milk", 10, 22),
            ("Toalettpapper", "Toilettenpapier", "Toilet paper", 12, 25), ("Strumpor", "Socken", "Socks", 13, 27)
        ]
        for (index, seed) in seeds.enumerated() {
            products.append(Product(id: stable(100 + index), name: LocalizedName(sv: seed.0, de: seed.1, en: seed.2), typeID: stable(seed.3), sectionID: stable(seed.4), modifiedAt: Date(timeIntervalSince1970: 0)))
        }
        locations = [
            StoreLocation(id: stable(200), name: "ICA Maxi Solna", storeID: stable(1), sectionOrder: [20,21,22,23,24,25,26,27,28].map(stable), modifiedAt: Date(timeIntervalSince1970: 0)),
            StoreLocation(id: stable(201), name: "ICA Rapidköp", storeID: stable(1), sectionOrder: [20,21,23,22,24,25,26].map(stable), modifiedAt: Date(timeIntervalSince1970: 0))
        ]
    }
}
