import SwiftUI
import Translation

private enum ItemOrganization: String, CaseIterable, Identifiable {
    case none, type, section, store
    var id: String { rawValue }
    func name(_ store: CleverlistStore) -> String {
        switch self {
        case .none: store.text("None", "Ingen", "Keine")
        case .type: store.text("Product type", "Produkttyp", "Produkttyp")
        case .section: store.text("Section", "Avdelning", "Abteilung")
        case .store: store.text("Store", "Butik", "Geschäft")
        }
    }
}

private struct ItemGroup: Identifiable {
    let id: String
    let title: String
    let items: [ShoppingItem]
}

private struct ItemGroupView<ItemContent: View>: View {
    let group: ItemGroup
    @Binding var isCheckedGroupExpanded: Bool
    let canEdit: Bool
    let deleteTitle: String
    let deleteItem: (ShoppingItem) -> Void
    @ViewBuilder let itemContent: (ShoppingItem) -> ItemContent

    private var isCheckedGroup: Bool {
        group.id == "__checked"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !group.title.isEmpty {
                if isCheckedGroup {
                    Button {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isCheckedGroupExpanded.toggle()
                        }
                    } label: {
                        groupHeader(showsDisclosureIndicator: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(group.title)
                    .accessibilityValue(isCheckedGroupExpanded ? "Expanded" : "Collapsed")
                } else {
                    groupHeader(showsDisclosureIndicator: false)
                }
            }

            if !isCheckedGroup || isCheckedGroupExpanded {
                ForEach(group.items) { item in
                    itemContent(item)
                        .disabled(!canEdit)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label(deleteTitle, systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func groupHeader(showsDisclosureIndicator: Bool) -> some View {
        HStack {
            Text(group.title).font(.subheadline.weight(.bold))
            Text("\(group.items.count)").font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            if showsDisclosureIndicator {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isCheckedGroupExpanded ? 0 : -90))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 5)
        .contentShape(Rectangle())
    }
}

struct ShoppingListView: View {
    let store: CleverlistStore
    let listID: UUID
    let sync: CloudSyncService
    @State private var query = ""
    @State private var grouping: ItemOrganization = .section
    @State private var coloring: ItemOrganization = .type
    @State private var locationID: UUID?
    @State private var showingProduct = false
    @State private var editingItem: ShoppingItem?
    @State private var addingProduct: Product?
    @State private var areCheckedItemsExpanded = true
    @AppStorage("hunter.lastUsedListID") private var lastUsedListID = ""
    @AppStorage("hunter.searchAllLanguages") private var searchAllLanguages = true

    private var items: [ShoppingItem] { store.items(in: listID) }
    private var location: StoreLocation? { store.activeLocations.first { $0.id == locationID } }
    private var suggestions: [Product] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return Array(store.activeProducts.filter { product in
            let names = searchAllLanguages
                ? [product.name.sv, product.name.de, product.name.en].joined(separator: " ")
                : store.name(product.name)
            return words.allSatisfy { names.localizedCaseInsensitiveContains($0) }
        }.sorted { store.name($0.name) < store.name($1.name) }.prefix(5))
    }
    private var groups: [ItemGroup] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
            if let order = location?.sectionOrder {
                let a = store.product(lhs.productID)?.sectionID.flatMap { order.firstIndex(of: $0) } ?? Int.max
                let b = store.product(rhs.productID)?.sectionID.flatMap { order.firstIndex(of: $0) } ?? Int.max
                if a != b { return a < b }
            }
            return productName(lhs) < productName(rhs)
        }
        var keys: [String] = []
        var buckets: [String: [ShoppingItem]] = [:]
        for item in sorted {
            let key = item.isChecked ? "__checked" : groupName(item)
            if buckets[key] == nil { keys.append(key) }
            buckets[key, default: []].append(item)
        }
        return keys.map { key in
            ItemGroup(id: key, title: key == "__checked" ? store.text("Sorted", "Fixat", "Eingepackt") : key, items: buckets[key] ?? [])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary
                controls
                if items.isEmpty {
                    ContentUnavailableView(store.text("Your next great find", "Ditt nästa fina fynd", "Dein nächster toller Fund"), systemImage: "basket", description: Text(store.text("Search below to add your first item.", "Sök nedan för att lägga till din första vara.", "Suche unten, um deinen ersten Artikel hinzuzufügen.")))
                        .padding(.vertical, 35)
                }
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        ItemGroupView(
                            group: group,
                            isCheckedGroupExpanded: $areCheckedItemsExpanded,
                            canEdit: store.canEdit(listID),
                            deleteTitle: store.text("Delete", "Radera", "Löschen"),
                            deleteItem: { store.delete($0) },
                            itemContent: { item in itemRow(item) }
                        )
                    }
                }
            }
            .padding(20).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
        .modifier(ShoppingSwipeContainer())
        .onAppear { lastUsedListID = listID.uuidString }
        .modifier(SeasonalScreen(theme: store.theme))
        .navigationTitle(store.activeLists.first { $0.id == listID }?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ListSharingView(store: store, sync: sync, listID: listID)
                } label: {
                    Label(store.text("Share list", "Dela lista", "Liste teilen"), systemImage: "person.2")
                }
            }
            ToolbarItem(placement: .principal) {
                Menu {
                    Button(store.text("All stores", "Alla butiker", "Alle Geschäfte")) { locationID = nil }
                    ForEach(store.activeLocations) { location in
                        Button(location.name) { locationID = location.id; grouping = .section }
                    }
                } label: {
                    Label(location?.name ?? store.text("Choose store", "Välj butik", "Geschäft wählen"), systemImage: "mappin.and.ellipse")
                        .font(.subheadline.bold()).lineLimit(1)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(store.text("Create product", "Skapa produkt", "Produkt erstellen"), systemImage: "plus") { showingProduct = true }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { searchDock.disabled(!store.canEdit(listID)) }
        .sheet(isPresented: $showingProduct) {
            ProductEditor(store: store, listID: listID, initialText: query) { query = "" }
        }
        .sheet(item: $editingItem) { item in
            ShoppingItemEditor(store: store, item: item)
        }
        .sheet(item: $addingProduct) { product in
            AddQuantityView(store: store, product: product, listID: listID) {
                query = ""
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(items.filter { !$0.isChecked }.count == 1
                     ? store.text("1 thing to find", "1 sak att hitta", "1 Sache auf der Liste")
                     : store.text("\(items.filter { !$0.isChecked }.count) things to find", "\(items.filter { !$0.isChecked }.count) saker att hitta", "\(items.filter { !$0.isChecked }.count) Auf der Liste"))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                if let location {
                    Label(store.text("Sorted for \(location.name)", "Sorterat för \(location.name)", "Sortiert für \(location.name)"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(store.theme.artwork).resizable().scaledToFit().frame(width: 70, height: 70).accessibilityHidden(true)
        }
        .padding(16)
        .background(store.theme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(store.theme.accent.opacity(0.24)))
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { groupMenu; colorMenu }
            VStack(alignment: .leading) { groupMenu; colorMenu }
        }
    }

    private var groupMenu: some View {
        Menu {
            Picker(store.text("Group by", "Gruppera efter", "Gruppieren nach"), selection: $grouping) {
                ForEach(ItemOrganization.allCases) { mode in Text(mode.name(store)).tag(mode) }
            }
        } label: {
            Label(store.text("Group: ", "Gruppera: ", "Gruppieren: ") + grouping.name(store), systemImage: "square.grid.2x2")
                .font(.caption.bold()).padding(.horizontal, 13).padding(.vertical, 10)
                .background(store.theme.secondary.opacity(0.24), in: Capsule())
                .overlay(Capsule().strokeBorder(store.theme.accent.opacity(0.25)))
        }
    }

    private var colorMenu: some View {
        Menu {
            Picker(store.text("Color by", "Färglägg efter", "Farbe nach"), selection: $coloring) {
                ForEach(ItemOrganization.allCases) { mode in Text(mode.name(store)).tag(mode) }
            }
        } label: {
            Label(store.text("Color: ", "Färg: ", "Farbe: ") + coloring.name(store), systemImage: "paintpalette")
                .font(.caption.bold()).padding(.horizontal, 13).padding(.vertical, 10)
                .background(store.theme.secondary.opacity(0.24), in: Capsule())
                .overlay(Capsule().strokeBorder(store.theme.accent.opacity(0.25)))
        }
    }

    private func productName(_ item: ShoppingItem) -> String {
        store.product(for: item).map { store.name($0.name) } ?? store.text("Unavailable product", "Otillgänglig produkt", "Nicht verfügbares Produkt")
    }

    private func termID(_ product: Product, by mode: ItemOrganization) -> UUID? {
        switch mode {
        case .none: nil
        case .type: product.typeID
        case .section: product.sectionID
        case .store: product.storeIDs.first
        }
    }

    private func groupName(_ item: ShoppingItem) -> String {
        guard grouping != .none, let product = store.product(for: item) else { return "" }
        if grouping == .store {
            if product.storeIDs.isEmpty { return store.text("Any store", "Alla butiker", "Jedes Geschäft") }
            return product.storeIDs.compactMap { store.term($0).map { store.name($0.name) } }.joined(separator: " · ")
        }
        return store.term(termID(product, by: grouping), for: item).map { store.name($0.name) } ?? store.text("Other", "Övrigt", "Sonstiges")
    }

    private func itemColor(_ item: ShoppingItem) -> Color {
        if let hex = item.colorHex { return hunterColor(hex) }
        if let product = store.product(for: item), let term = store.term(termID(product, by: coloring), for: item) {
            return hunterColor(term.colorHex)
        }
        return store.theme.accent
    }

    private func itemRow(_ item: ShoppingItem) -> some View {
        let color = itemColor(item)
        return HStack(spacing: 13) {
            Button {
                var changed = item
                changed.isChecked.toggle()
                withAnimation(.easeInOut(duration: 0.5)) {
                    store.save(changed)
                }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(color).frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.text("Toggle purchased", "Växla köpt", "Gekauft umschalten"))
            Button { editingItem = item } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(productName(item)).font(.headline).strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    HStack(spacing: 5) {
                        if !item.amount.isEmpty { Text(item.amount) }
                        if let unit = store.term(item.unitID, for: item) { Text(store.name(unit.name)) }
                        if let product = store.product(for: item), let section = store.term(product.sectionID, for: item) {
                            Text("· " + store.name(section.name))
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    if !item.comment.isEmpty {
                        Text(item.comment).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button(store.text("Edit", "Redigera", "Bearbeiten"), systemImage: "pencil") { editingItem = item }
                Button(store.text("Remove", "Ta bort", "Entfernen"), systemImage: "trash", role: .destructive) { store.delete(item) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 44)
            }.accessibilityLabel(store.text("Item options", "Alternativ för vara", "Artikeloptionen"))
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(store.theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18).fill(color.opacity(item.isChecked ? 0.03 : 0.09)))
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(store.theme.accent.opacity(0.16)))
        .shadow(color: store.theme.accent.opacity(0.08), radius: 6, y: 3)
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 4).padding(.vertical, 15) }
    }

    private var searchDock: some View {
        VStack(spacing: 0) {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { product in
                        HStack {
                            Image(systemName: "plus.circle.fill").foregroundStyle(store.theme.accent)
                            Text(store.name(product.name)).foregroundStyle(.primary)
                            Spacer()
                            if let type = store.term(product.typeID) {
                                Text(store.name(type.name)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(13).contentShape(Rectangle())
                        // Exclusive recognition prevents a long press from also adding on release.
                        .gesture(LongPressGesture(minimumDuration: 0.5)
                            .exclusively(before: TapGesture())
                            .onEnded { gesture in
                                switch gesture {
                                case .first: addingProduct = product
                                case .second:
                                    store.save(ShoppingItem(listID: listID, productID: product.id))
                                    query = ""
                                }
                            })
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(store.text("Tap to add, or hold to choose amount and unit", "Tryck för att lägga till, eller håll för att välja mängd och enhet", "Tippen zum Hinzufügen oder halten für Menge und Einheit"))
                        .accessibilityAction {
                            store.save(ShoppingItem(listID: listID, productID: product.id))
                            query = ""
                        }
                        .accessibilityAction(named: Text(store.text("Add with quantity", "Lägg till med mängd", "Mit Menge hinzufügen"))) {
                            addingProduct = product
                        }
                    }
                    if suggestions.isEmpty {
                        Button(store.text("No match — create a product", "Ingen träff — skapa en produkt", "Kein Treffer — Produkt erstellen")) { showingProduct = true }
                            .font(.subheadline).padding(16)
                    }
                }
                .background(store.theme.surface, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16).padding(.top, 10)
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(store.theme.accent)
                TextField(store.text("What do we need?", "Vad behöver vi?", "Was brauchen wir?"), text: $query)
                    .textFieldStyle(.plain).submitLabel(.done)
                    .onSubmit { if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { showingProduct = true } }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { showingProduct = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(store.theme.accent)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(store.text("Create item from text", "Skapa vara från text", "Artikel aus Text erstellen"))
                }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel(store.text("Clear search", "Rensa sökning", "Suche löschen"))
                }
            }
            .padding(17).background(store.theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(store.theme.accent.opacity(0.35)))
            .padding(16)
        }
        .background {
            ZStack {
                store.theme.background
                LinearGradient(colors: [store.theme.background, store.theme.secondary.opacity(0.38)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(store.theme.accent.opacity(0.24)).frame(height: 1)
        }
    }
}

struct ProductEditor: View {
    let store: CleverlistStore
    let listID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var swedish = ""
    @State private var german = ""
    @State private var english = ""
    @State private var storeIDs: Set<UUID> = []
    @State private var typeID: UUID?
    @State private var sectionID: UUID?
    let existingProduct: Product?
    let initialText: String
    let onSaved: () -> Void
    @State private var isTranslating = false
    @State private var translationFailed = false
    @State private var prepared = false

    init(store: CleverlistStore, listID: UUID? = nil, product: Product? = nil, initialText: String = "", onSaved: @escaping () -> Void = {}) {
        self.store = store
        self.listID = listID
        self.existingProduct = product
        _swedish = State(initialValue: product?.name.sv ?? "")
        _german = State(initialValue: product?.name.de ?? "")
        _english = State(initialValue: product?.name.en ?? "")
        _storeIDs = State(initialValue: Set(product?.storeIDs ?? []))
        _typeID = State(initialValue: product?.typeID)
        _sectionID = State(initialValue: product?.sectionID)
        self.initialText = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.onSaved = onSaved
    }

    private var valid: Bool {
        [swedish, german, english].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Svenska", text: $swedish)
                    TextField("Deutsch", text: $german)
                    TextField("English", text: $english)
                    if isTranslating {
                        ProgressView(store.text("Translating…", "Översätter…", "Wird übersetzt…"))
                    }
                    if translationFailed {
                        Text(store.text("Some names could not be translated. Review and edit each language before saving.", "Vissa namn kunde inte översättas. Granska och redigera varje språk innan du sparar.", "Einige Namen konnten nicht übersetzt werden. Prüfe und bearbeite jede Sprache vor dem Speichern."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(store.text("One product, three languages", "En produkt, tre språk", "Ein Produkt, drei Sprachen"))
                } footer: {
                    Text(store.text("Everyone sees the name in their own language. Review and edit any name before saving.", "Alla ser namnet på sitt eget språk. Granska och redigera namnen innan du sparar.", "Alle sehen den Namen in ihrer eigenen Sprache. Prüfe und bearbeite die Namen vor dem Speichern."))
                    if !initialText.isEmpty {
                        Text(store.text("New text is translated from \(store.language.title).", "Ny text översätts från \(store.language.title).", "Neuer Text wird aus \(store.language.title) übersetzt."))
                    }
                }
                Section(store.text("Organize", "Organisera", "Organisieren")) {
                    termPicker(store.text("Type", "Typ", "Typ"), kind: .type, selection: $typeID)
                    termPicker(store.text("Section", "Avdelning", "Abteilung"), kind: .section, selection: $sectionID)
                }
                Section {
                    ForEach(store.catalog(.store)) { term in
                        Toggle(store.name(term.name), isOn: Binding(get: { storeIDs.contains(term.id) }, set: { selected in
                            if selected { storeIDs.insert(term.id) } else { storeIDs.remove(term.id) }
                        }))
                    }
                } header: {
                    Text(store.text("Available in", "Finns i", "Erhältlich bei"))
                } footer: {
                    Text(store.text("Select no stores to make this available everywhere.", "Välj inga butiker för att göra varan tillgänglig överallt.", "Ohne Auswahl ist der Artikel in allen Geschäften verfügbar."))
                }
            }
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle(existingProduct == nil ? store.text("New product", "Ny produkt", "Neues Produkt") : store.text("Edit product", "Redigera produkt", "Produkt bearbeiten"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("Cancel", "Avbryt", "Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("Save", "Spara", "Speichern")) {
                        if let listID {
                            guard store.canEdit(listID), store.activeLists.contains(where: { $0.id == listID }) else { return }
                        }
                        var product = existingProduct ?? Product(name: LocalizedName(sv: "", de: "", en: ""))
                        product.name = LocalizedName(sv: swedish.trimmingCharacters(in: .whitespacesAndNewlines), de: german.trimmingCharacters(in: .whitespacesAndNewlines), en: english.trimmingCharacters(in: .whitespacesAndNewlines))
                        product.storeIDs = Array(storeIDs)
                        product.typeID = typeID
                        product.sectionID = sectionID
                        store.save(product)
                        if let listID { store.save(ShoppingItem(listID: listID, productID: product.id)) }
                        onSaved()
                        dismiss()
                    }.disabled(!valid || isTranslating)
                }
            }
        }
        .tint(store.theme.accent)
        .task { await prepareNames() }
    }

    @MainActor
    private func prepareNames() async {
        guard !prepared, !Task.isCancelled else { return }
        prepared = true
        guard !initialText.isEmpty else { return }
        if let match = store.activeProducts.first(where: { product in
            Language.allCases.contains { product.name.value($0).localizedCaseInsensitiveCompare(initialText) == .orderedSame }
        }) {
            swedish = match.name.sv
            german = match.name.de
            english = match.name.en
            return
        }
        swedish = initialText
        german = initialText
        english = initialText

        let sourceLanguage = store.language
        isTranslating = true
        defer { isTranslating = false }

        for target in Language.allCases where target != sourceLanguage {
            guard !Task.isCancelled else { return }
            // Installed-only sessions cannot present download UI over the editor sheet.
            // Missing models throw an error and leave the names editable.
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: sourceLanguage.rawValue),
                target: Locale.Language(identifier: target.rawValue)
            )
            do {
                let response = try await session.translate(initialText)
                try Task.checkCancellation()
                // Preserve edits made while the automatic translation was running.
                switch target {
                case .sv: if swedish == initialText { swedish = response.targetText }
                case .de: if german == initialText { german = response.targetText }
                case .en: if english == initialText { english = response.targetText }
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                translationFailed = true
            }
        }
    }

    private func termPicker(_ title: String, kind: CatalogKind, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text(store.text("Not specified", "Inte angivet", "Nicht angegeben")).tag(nil as UUID?)
            ForEach(store.catalog(kind)) { term in Text(store.name(term.name)).tag(Optional(term.id)) }
        }
    }
}

struct ShoppingItemEditor: View {
    let store: CleverlistStore
    @State private var item: ShoppingItem
    @Environment(\.dismiss) private var dismiss
    private let colors = ["#ED6A45", "#E54E87", "#8C5CD6", "#3A84D5", "#279D83", "#CA981F"]

    init(store: CleverlistStore, item: ShoppingItem) {
        self.store = store
        _item = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(store.text("Quantity (optional)", "Mängd (valfritt)", "Menge (optional)")) {
                    TextField(store.text("Amount", "Mängd", "Menge"), text: $item.amount)
                    Picker(store.text("Unit", "Enhet", "Einheit"), selection: $item.unitID) {
                        Text(store.text("No unit", "Ingen enhet", "Keine Einheit")).tag(nil as UUID?)
                        ForEach(store.catalog(.unit)) { unit in Text(store.name(unit.name)).tag(Optional(unit.id)) }
                    }
                }
                Section(store.text("Comment", "Kommentar", "Kommentar")) {
                    TextField(store.text("A little reminder…", "En liten påminnelse…", "Eine kleine Erinnerung…"), text: $item.comment, axis: .vertical).lineLimit(3...6)
                }
                Section(store.text("Personal color", "Egen färg", "Eigene Farbe")) {
                    Button(store.text("Use automatic color", "Använd automatisk färg", "Automatische Farbe verwenden")) { item.colorHex = nil }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))]) {
                        ForEach(colors, id: \.self) { hex in
                            Button { item.colorHex = hex } label: {
                                Circle().fill(hunterColor(hex)).frame(width: 34, height: 34)
                                    .overlay { if item.colorHex == hex { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) } }
                            }
                            .buttonStyle(.plain).accessibilityLabel(hex)
                        }
                    }.padding(.vertical, 4)
                }
                Section {
                    Button(store.text("Remove from list", "Ta bort från listan", "Aus Liste entfernen"), role: .destructive) { store.delete(item); dismiss() }
                }
            }
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle(store.product(for: item).map { store.name($0.name) } ?? "")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("Cancel", "Avbryt", "Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(store.text("Save", "Spara", "Speichern")) { store.save(item); dismiss() } }
            }
        }.tint(store.theme.accent)
    }
}

private func hunterColor(_ hex: String) -> Color {
    let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0xED6A45
    return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
}
