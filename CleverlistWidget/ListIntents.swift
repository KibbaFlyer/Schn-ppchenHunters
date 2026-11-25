import AppIntents
import WidgetKit

struct ShoppingListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shopping List"
    static let defaultQuery = ShoppingListQuery()

    // The list's UUID, which is stable across launches and shared with the app.
    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ShoppingListQuery: EntityQuery {
    private var lists: [ShoppingListEntity] {
        (WidgetSharedStore.readSnapshot()?.lists ?? []).map { ShoppingListEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [UUID]) async throws -> [ShoppingListEntity] {
        lists.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ShoppingListEntity] { lists }

    func defaultResult() async -> ShoppingListEntity? { lists.first }
}

struct SelectListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose List"
    static let description = IntentDescription("Choose which shopping list the widget shows.")

    @Parameter(title: "List")
    var list: ShoppingListEntity?

    init() {}

    init(list: ShoppingListEntity?) {
        self.list = list
    }
}

// Runs in the widget extension, so checking off an item never opens the app.
struct ToggleItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Off Item"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Item")
    var itemID: String

    @Parameter(title: "List")
    var listID: String

    // The state to apply. Passed in explicitly: widget toggles don't fill in a
    // SetValueIntent's `value`, which left the intent unable to run.
    @Parameter(title: "Checked")
    var isChecked: Bool

    init() {}

    init(itemID: UUID, listID: UUID, isChecked: Bool) {
        self.itemID = itemID.uuidString
        self.listID = listID.uuidString
        self.isChecked = isChecked
    }

    func perform() async throws -> some IntentResult {
        guard let itemID = UUID(uuidString: itemID), let listID = UUID(uuidString: listID) else { return .result() }
        WidgetSharedStore.record(WidgetToggle(itemID: itemID, listID: listID, isChecked: isChecked))
        // WidgetKit only reloads widgets sharing the tapped widget's configuration, so
        // other Cleverlist widgets (another size or list choice) are reloaded explicitly.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedStore.widgetKind)
        return .result()
    }
}
