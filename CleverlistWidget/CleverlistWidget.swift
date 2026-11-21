import AppIntents
import SwiftUI
import WidgetKit

struct ListEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let list: WidgetList?
}

struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListEntry {
        ListEntry(date: Date(), snapshot: .sample, list: WidgetSnapshot.sample.lists.first)
    }

    func snapshot(for configuration: SelectListIntent, in context: Context) async -> ListEntry {
        if context.isPreview, WidgetSharedStore.readSnapshot() == nil { return placeholder(in: context) }
        return entry(for: configuration)
    }

    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<ListEntry> {
        // The app reloads this widget whenever its lists change, so no scheduled refresh is needed.
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: SelectListIntent) -> ListEntry {
        let snapshot = WidgetSharedStore.readSnapshot()
        return ListEntry(date: Date(), snapshot: snapshot, list: snapshot?.list(configuration.list?.id))
    }
}

struct CleverlistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSharedStore.widgetKind, intent: SelectListIntent.self, provider: ListProvider()) { entry in
            ListWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetText.localized("Shopping list", "Inköpslista", "Einkaufsliste"))
        .description(WidgetText.localized(
            "Check off items from one of your lists.",
            "Bocka av varor från en av dina listor.",
            "Hake Artikel auf einer deiner Listen ab."
        ))
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Views

struct ListWidgetView: View {
    let entry: ListEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { entry.snapshot.map { Color.widget(hex: $0.accentHex) } ?? .accentColor }

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, let list = entry.list {
            switch family {
            case .accessoryCircular: CircularView(list: list)
            case .accessoryInline: Text(snapshot.text("\(list.name): \(list.remainingCount) left", "\(list.name): \(list.remainingCount) kvar", "\(list.name): \(list.remainingCount) offen"))
            case .accessoryRectangular: RectangularView(snapshot: snapshot, list: list)
            default: SystemListView(snapshot: snapshot, list: list, accent: accent, layout: .init(family))
            }
        } else {
            let message = entry.snapshot == nil
                ? WidgetText.localized("Open Cleverlist to show your lists here.", "Öppna Cleverlist för att visa dina listor här.", "Öffne Cleverlist, um deine Listen hier zu sehen.")
                : WidgetText.localized("No lists yet.", "Inga listor än.", "Noch keine Listen.")
            if family == .accessoryInline {
                Text(message)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "basket.fill").font(.title2).foregroundStyle(accent).widgetAccentable()
                    Text(message).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if let snapshot = entry.snapshot, family.isSystem {
            // Mirrors the app's seasonal card surface.
            LinearGradient(colors: [.white.opacity(0.97), Color.widget(hex: snapshot.backgroundHex)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.clear
        }
    }
}

private struct SystemLayout {
    let columns: Int
    let rows: Int
    let showsDetail: Bool

    init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium: columns = 2
        case .systemExtraLarge: columns = 3
        default: columns = 1
        }
        switch family {
        case .systemSmall: rows = 4
        case .systemMedium: rows = 3
        case .systemLarge: rows = 8
        // Extra large is wide but short; 5 rows fit even on iPad mini.
        case .systemExtraLarge: rows = 5
        default: rows = 2
        }
        showsDetail = family == .systemLarge || family == .systemExtraLarge
    }

    var capacity: Int { columns * rows }
}

private struct SystemListView: View {
    let snapshot: WidgetSnapshot
    let list: WidgetList
    let accent: Color
    let layout: SystemLayout

    var body: some View {
        let items = list.openItems
        // Reserve the last slot for the "more" note when the list doesn't fit.
        let shown = items.count > layout.capacity ? Array(items.prefix(layout.capacity - 1)) : items
        VStack(alignment: .leading, spacing: layout.columns == 1 && layout.rows <= 4 ? 6 : 8) {
            header
            if items.isEmpty {
                Spacer(minLength: 0)
                Text(list.items.isEmpty
                     ? snapshot.text("Nothing on this list yet.", "Inget på listan än.", "Noch nichts auf der Liste.")
                     : snapshot.text("All found!", "Allt fixat!", "Alles gefunden!"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .leading), count: layout.columns), alignment: .leading, spacing: layout.showsDetail ? 8 : 6) {
                    ForEach(shown) { item in
                        ItemRow(item: item, listID: list.id, canEdit: list.canEdit, accent: accent, showsDetail: layout.showsDetail)
                    }
                    if items.count > shown.count {
                        Text(snapshot.text("+\(items.count - shown.count) more", "+\(items.count - shown.count) till", "+\(items.count - shown.count) weitere"))
                            .font(.caption.bold()).foregroundStyle(.secondary)
                            .padding(.leading, 28)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(list.name)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 4)
            if list.remainingCount == 0 && !list.items.isEmpty {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(accent).widgetAccentable()
                    .accessibilityLabel(snapshot.text("All found", "Allt fixat", "Alles gefunden"))
            } else {
                Text("\(list.remainingCount)")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(accent.opacity(0.14), in: Capsule())
                    .accessibilityLabel(snapshot.text("\(list.remainingCount) left", "\(list.remainingCount) kvar", "\(list.remainingCount) offen"))
            }
        }
    }
}

private struct ItemRow: View {
    let item: WidgetItem
    let listID: UUID
    let canEdit: Bool
    let accent: Color
    let showsDetail: Bool

    private var color: Color { item.colorHex.map { Color.widget(hex: $0) } ?? accent }

    var body: some View {
        if canEdit {
            // The toggle flips immediately; the item then disappears when the widget reloads.
            Toggle(isOn: item.isChecked, intent: ToggleItemIntent(itemID: item.id, listID: listID, isChecked: !item.isChecked)) { label }
                .toggleStyle(ItemToggleStyle(color: color))
        } else {
            // Read-only shared lists show their state without a control.
            HStack(spacing: 6) {
                ItemToggleStyle.checkmark(isOn: item.isChecked, color: color)
                label
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .strikethrough(item.isChecked)
                .foregroundStyle(item.isChecked ? .secondary : .primary)
                .lineLimit(1)
            if showsDetail, !item.detail.isEmpty || !item.comment.isEmpty {
                // One line, so a note that doesn't fit the row also trails off with "…".
                Text(detailLine).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailLine: AttributedString {
        var line = AttributedString(item.detail)
        if !item.comment.isEmpty {
            var comment = AttributedString(item.comment)
            comment.inlinePresentationIntent = .emphasized
            if !line.characters.isEmpty { line += AttributedString(" · ") }
            line += comment
        }
        return line
    }
}

private struct ItemToggleStyle: ToggleStyle {
    let color: Color

    static func checkmark(isOn: Bool, color: Color) -> some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 22)
            .widgetAccentable()
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Self.checkmark(isOn: configuration.isOn, color: color)
            configuration.label
        }
        .contentShape(Rectangle())
    }
}

private struct CircularView: View {
    let list: WidgetList

    var body: some View {
        Gauge(value: Double(list.items.count - list.remainingCount), in: 0...Double(max(list.items.count, 1))) {
            Image(systemName: "basket.fill")
        } currentValueLabel: {
            Text("\(list.remainingCount)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

private struct RectangularView: View {
    let snapshot: WidgetSnapshot
    let list: WidgetList

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(list.name).font(.headline).lineLimit(1).widgetAccentable()
                Spacer(minLength: 2)
                Text("\(list.remainingCount)").font(.headline.monospacedDigit())
            }
            let open = list.openItems
            if open.isEmpty {
                Text(snapshot.text("All found!", "Allt fixat!", "Alles gefunden!")).font(.caption)
            } else {
                ForEach(open.prefix(2)) { item in
                    ItemRow(item: item, listID: list.id, canEdit: list.canEdit, accent: .primary, showsDetail: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Helpers

enum WidgetText {
    // Before the app has published a snapshot, follow the system language.
    static func localized(_ en: String, _ sv: String, _ de: String) -> String {
        switch Locale.current.language.languageCode?.identifier { case "sv": sv; case "de": de; default: en }
    }
}

private extension WidgetFamily {
    var isSystem: Bool { [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge].contains(self) }
}

private extension Color {
    static func widget(hex: String) -> Color {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x186648
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}

extension WidgetSnapshot {
    static let sample: WidgetSnapshot = {
        let comments = [
            0: "Lactose free, the big carton",
            2: "Sourdough if they have it, otherwise any dark rye bread from the bakery shelf",
            5: "Ripe ones for tonight"
        ]
        let names: [(String, String, String, String, Bool)] = [
            ("Milk", "Mjölk", "Milch", "#74BFE4", false), ("Bananas", "Bananer", "Bananen", "#75C783", false),
            ("Bread", "Bröd", "Brot", "#E7AF63", false), ("Coffee", "Kaffe", "Kaffee", "#E7A175", false),
            ("Eggs", "Ägg", "Eier", "#74BFE4", false), ("Tomatoes", "Tomater", "Tomaten", "#75C783", false),
            ("Pasta", "Pasta", "Nudeln", "#E7A175", false), ("Toothpaste", "Tandkräm", "Zahnpasta", "#C59DE6", false),
            ("Butter", "Smör", "Butter", "#74BFE4", false), ("Apples", "Äpplen", "Äpfel", "#75C783", false),
            ("Yogurt", "Yoghurt", "Joghurt", "#74BFE4", false), ("Potatoes", "Potatis", "Kartoffeln", "#75C783", false),
            ("Oat milk", "Havremjölk", "Hafermilch", "#74BFE4", false), ("Shampoo", "Schampo", "Shampoo", "#C59DE6", false),
            ("Dish soap", "Diskmedel", "Spülmittel", "#65C4BC", false), ("Socks", "Strumpor", "Socken", "#EC91B5", false),
            ("Cheese", "Ost", "Käse", "#74BFE4", true), ("Rice", "Ris", "Reis", "#E7A175", true)
        ]
        let items = names.enumerated().map { index, name in
            WidgetItem(id: UUID(), name: WidgetText.localized(name.0, name.1, name.2), detail: "\(index % 3 + 1)", comment: WidgetItem.shortenedComment(comments[index] ?? ""), colorHex: name.3, isChecked: name.4)
        }
        return WidgetSnapshot(
            updatedAt: Date(), language: Locale.current.language.languageCode?.identifier ?? "en",
            accentHex: "186648", secondaryHex: "F1B31C", backgroundHex: "E7F3C8",
            lists: [WidgetList(id: UUID(), name: WidgetText.localized("Weekly groceries", "Veckohandling", "Wocheneinkauf"), canEdit: true, items: items)]
        )
    }()
}

#Preview(as: .systemMedium) {
    CleverlistWidget()
} timeline: {
    ListEntry(date: .now, snapshot: .sample, list: WidgetSnapshot.sample.lists.first)
}

#Preview(as: .systemSmall) {
    CleverlistWidget()
} timeline: {
    ListEntry(date: .now, snapshot: .sample, list: WidgetSnapshot.sample.lists.first)
}

#Preview(as: .accessoryRectangular) {
    CleverlistWidget()
} timeline: {
    ListEntry(date: .now, snapshot: .sample, list: WidgetSnapshot.sample.lists.first)
}
