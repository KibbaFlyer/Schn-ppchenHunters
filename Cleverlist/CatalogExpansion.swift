import Foundation

// Append-only seed IDs: changing names or ordering must not change an existing ID.
enum CatalogExpansion {
    private static let seedDate = Date(timeIntervalSince1970: 0)

    private static func stable(_ number: Int) -> UUID {
        // Numeric IDs fit in the last 32 bits and preserve the original seed format.
        let suffix = String(format: "%012d", number)
        return UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID()
    }

    static var terms: [CatalogTerm] {
        [
            CatalogTerm(id: stable(40), name: LocalizedName(sv: "Kött & chark", de: "Fleisch & Wurst", en: "Meat & deli"), kind: .section, colorHex: "#E98991", modifiedAt: seedDate),
            CatalogTerm(id: stable(41), name: LocalizedName(sv: "Fisk & skaldjur", de: "Fisch & Meeresfrüchte", en: "Fish & seafood"), kind: .section, colorHex: "#64B9CB", modifiedAt: seedDate),
            CatalogTerm(id: stable(42), name: LocalizedName(sv: "Drycker", de: "Getränke", en: "Drinks"), kind: .section, colorHex: "#E4A54C", modifiedAt: seedDate),
            CatalogTerm(id: stable(43), name: LocalizedName(sv: "Snacks & godis", de: "Snacks & Süßigkeiten", en: "Snacks & sweets"), kind: .section, colorHex: "#D78AC1", modifiedAt: seedDate)
        ]
    }

    static var locations: [StoreLocation] {
        // Routes are intentionally empty until the shopper arranges the sections.
        [
            StoreLocation(id: stable(202), name: "Coop Västra Skogen", storeID: stable(2), modifiedAt: seedDate),
            StoreLocation(id: stable(203), name: "Hemköp Huvudsta", storeID: stable(4), modifiedAt: seedDate),
            StoreLocation(id: stable(204), name: "Hemköp Solna Centrum", storeID: stable(4), modifiedAt: seedDate),
            StoreLocation(id: stable(205), name: "ICA Aptiten", storeID: stable(1), modifiedAt: seedDate),
            StoreLocation(id: stable(206), name: "ICA Kvantum Liljeholmen", storeID: stable(1), modifiedAt: seedDate),
            StoreLocation(id: stable(207), name: "ICA Kvantum Solna Centrum", storeID: stable(1), modifiedAt: seedDate),
            StoreLocation(id: stable(208), name: "Lidl Solna Centrum", storeID: stable(3), modifiedAt: seedDate)
        ]
    }

    static var products: [Product] { GroceryDrugstoreCatalog.products }
}
