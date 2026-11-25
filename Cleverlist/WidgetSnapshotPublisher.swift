import Foundation
import WidgetKit

extension CleverlistStore {
    // Shares a display-only copy of the lists with the widget through the App
    // Group. The full databases stay in the app's private container.
    func publishWidgetSnapshot() {
        guard sharesWithWidget else { return }
        let pending = pendingWidgetToggles()
        let palette = theme.palette
        let snapshotLists = activeLists.map { list in
            WidgetList(
                id: list.id,
                name: list.name,
                canEdit: canEdit(list.id),
                // Matches the list screen's default view: no store selected, grouped by section.
                items: groupedItems(in: list.id, sectionOrder: nil, groupKey: sectionGroupName)
                    .flatMap(\.items)
                    .map { widgetItem($0, pending: pending) }
            )
        }
        var snapshot = WidgetSnapshot(
            updatedAt: Date(), language: language.rawValue,
            accentHex: palette.0, secondaryHex: palette.1, backgroundHex: palette.2,
            lists: snapshotLists
        )
        if var previous = WidgetSharedStore.readSnapshot() {
            // Skip identical snapshots so background syncs don't spend the widget's reload budget.
            previous.updatedAt = snapshot.updatedAt
            if previous == snapshot { return }
        }
        snapshot.updatedAt = Date()
        if WidgetSharedStore.writeSnapshot(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedStore.widgetKind)
        }
    }

    // Applies items checked off in the widget while the app wasn't running.
    func applyWidgetToggles() {
        guard sharesWithWidget else { return }
        let toggles = WidgetSharedStore.pendingToggles()
        guard !toggles.isEmpty else { return }
        for toggle in toggles {
            guard let item = items.first(where: { $0.id == toggle.itemID && $0.listID == toggle.listID && !$0.isDeleted }),
                  canEdit(item.listID),
                  // A newer edit (for example one synced from another device) wins.
                  item.modifiedAt <= toggle.date,
                  item.isChecked != toggle.isChecked else { continue }
            var changed = item
            changed.isChecked = toggle.isChecked
            save(changed)
        }
        // Keep the toggles for a later retry if saving failed.
        guard lastError == nil else { return }
        WidgetSharedStore.removeToggles(Set(toggles.map(\.id)))
        publishWidgetSnapshot()
    }

    private func pendingWidgetToggles() -> [UUID: WidgetToggle] {
        Dictionary(WidgetSharedStore.pendingToggles().map { ($0.itemID, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    // Same group names as the list screen's "Group: Section" setting.
    private func sectionGroupName(_ item: ShoppingItem) -> String {
        guard let product = product(for: item) else { return "" }
        return term(product.sectionID, for: item).map { name($0.name) } ?? text("Other", "Övrigt", "Sonstiges")
    }

    private func widgetItem(_ item: ShoppingItem, pending: [UUID: WidgetToggle]) -> WidgetItem {
        let product = product(for: item)
        var detail: [String] = []
        if !item.amount.isEmpty { detail.append(item.amount) }
        if let unit = term(item.unitID, for: item) { detail.append(name(unit.name)) }
        if let section = term(product?.sectionID, for: item) { detail.append("· " + name(section.name)) }
        // Show not-yet-applied widget check-offs so republishing doesn't undo them visually.
        var isChecked = item.isChecked
        if let toggle = pending[item.id], item.modifiedAt <= toggle.date { isChecked = toggle.isChecked }
        return WidgetItem(
            id: item.id,
            name: itemName(item),
            detail: detail.joined(separator: " "),
            comment: WidgetItem.shortenedComment(item.comment),
            colorHex: item.colorHex ?? term(product?.sectionID, for: item)?.colorHex,
            isChecked: isChecked
        )
    }
}
