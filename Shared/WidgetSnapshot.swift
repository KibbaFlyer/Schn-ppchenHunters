import Foundation

// Compiled into both the app and the widget extension. Types are explicitly
// nonisolated because the app target defaults to MainActor isolation while
// widget timelines and intents run off the main actor.

nonisolated struct WidgetItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var detail: String
    // The item's own note, already shortened by the app (see `shortenedComment`).
    var comment: String
    var colorHex: String?
    var isChecked: Bool
}

nonisolated extension WidgetItem {
    static let maxCommentLength = 60

    // Keeps notes to one tidy line: line breaks become spaces and anything past
    // the limit is cut at a word boundary and trails off with an ellipsis.
    static func shortenedComment(_ comment: String) -> String {
        let flattened = comment.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > maxCommentLength else { return flattened }
        let prefix = flattened.prefix(maxCommentLength)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return cut.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }
}

nonisolated struct WidgetList: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var canEdit: Bool
    // In the same order as the list in the app.
    var items: [WidgetItem]

    var remainingCount: Int { openItems.count }

    // The widget hides items once they're checked off.
    var openItems: [WidgetItem] { items.filter { !$0.isChecked } }
}

nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    var version = 1
    var updatedAt: Date
    var language: String
    var accentHex: String
    var secondaryHex: String
    var backgroundHex: String
    var lists: [WidgetList]

    func text(_ en: String, _ sv: String, _ de: String) -> String {
        switch language { case "sv": sv; case "de": de; default: en }
    }

    func list(_ id: UUID?) -> WidgetList? {
        guard let id else { return lists.first }
        return lists.first { $0.id == id }
    }
}

// A check-off made in the widget. The app applies these to its own store the
// next time it runs, so revisions, persistence, and CloudKit sync stay in one place.
nonisolated struct WidgetToggle: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let itemID: UUID
    let listID: UUID
    let isChecked: Bool
    var date = Date()
}

nonisolated enum WidgetSharedStore {
    static let appGroup = "group.com.Flygare.SnappchenHunters"
    static let widgetKind = "CleverlistWidget"

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
    private static var snapshotURL: URL? { directory?.appendingPathComponent("widget-snapshot-v1.json") }
    private static var togglesURL: URL? { directory?.appendingPathComponent("widget-toggles-v1.json") }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL else { return nil }
        var snapshot: WidgetSnapshot?
        coordinate(reading: url) { url in
            guard let data = try? Data(contentsOf: url),
                  let value = try? JSONDecoder().decode(WidgetSnapshot.self, from: data), value.version == 1 else { return }
            snapshot = value
        }
        return snapshot
    }

    @discardableResult static func writeSnapshot(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(snapshot) else { return false }
        var written = false
        coordinate(writing: url) { url in written = write(data, to: url) }
        return written
    }

    static func pendingToggles() -> [WidgetToggle] {
        guard let url = togglesURL else { return [] }
        var toggles: [WidgetToggle] = []
        coordinate(reading: url) { url in toggles = decodeToggles(at: url) }
        return toggles
    }

    // Records a widget check-off and reflects it in the snapshot immediately so the
    // widget re-renders with the new state before the app has processed it.
    static func record(_ toggle: WidgetToggle) {
        guard let togglesURL else { return }
        coordinate(writing: togglesURL) { url in
            // Only the latest state per item matters.
            var toggles = decodeToggles(at: url).filter { $0.itemID != toggle.itemID }
            toggles.append(toggle)
            if let data = try? JSONEncoder().encode(toggles) { write(data, to: url) }
        }
        guard var snapshot = readSnapshot(),
              let listIndex = snapshot.lists.firstIndex(where: { $0.id == toggle.listID }),
              let itemIndex = snapshot.lists[listIndex].items.firstIndex(where: { $0.id == toggle.itemID }) else { return }
        snapshot.lists[listIndex].items[itemIndex].isChecked = toggle.isChecked
        writeSnapshot(snapshot)
    }

    static func removeToggles(_ ids: Set<UUID>) {
        guard let togglesURL, !ids.isEmpty else { return }
        coordinate(writing: togglesURL) { url in
            // Re-read inside the coordinated write so toggles recorded meanwhile survive.
            let remaining = decodeToggles(at: url).filter { !ids.contains($0.id) }
            if let data = try? JSONEncoder().encode(remaining) { write(data, to: url) }
        }
    }

    private static func decodeToggles(at url: URL) -> [WidgetToggle] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetToggle].self, from: data)) ?? []
    }

    @discardableResult private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            // Lock Screen widgets render while the device is locked, so the files
            // must stay readable after the first unlock.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var protectedURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedURL.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    private static func coordinate(reading url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
    }

    private static func coordinate(writing url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error, byAccessor: body)
    }
}
