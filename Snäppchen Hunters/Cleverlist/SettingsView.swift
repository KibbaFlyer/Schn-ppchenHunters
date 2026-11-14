import SwiftUI

struct SettingsView: View {
    @Bindable var store: CleverlistStore
    let sync: CloudSyncService
    @AppStorage("hunter.searchAllLanguages") private var searchAllLanguages = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(store.text("Make it yours", "Gör den till din", "Ganz nach deinem Geschmack")) {
                    Picker(store.text("Language", "Språk", "Sprache"), selection: $store.language) {
                        Text("Svenska").tag(Language.sv)
                        Text("Deutsch").tag(Language.de)
                        Text("English").tag(Language.en)
                    }
                    NavigationLink {
                        ThemePickerView(store: store)
                    } label: {
                        Label(store.theme.name(store.language), systemImage: "paintpalette.fill")
                    }
                }
                Section {
                    Toggle(store.text("Search all languages", "Sök på alla språk", "In allen Sprachen suchen"), isOn: $searchAllLanguages)
                } header: {
                    Text(store.text("Search", "Sökning", "Suche"))
                } footer: {
                    Text(store.text(
                        "When enabled, search Swedish, German and English product names. Results stay in your selected language: searching Brot shows Bröd in Swedish. When disabled, only names in your selected language are searched.",
                        "När detta är aktiverat söker du bland svenska, tyska och engelska produktnamn. Resultaten visas på ditt valda språk: Brot visar Bröd på svenska. När det är avstängt söker du endast på ditt valda språk.",
                        "Wenn aktiviert, werden schwedische, deutsche und englische Produktnamen durchsucht. Ergebnisse bleiben in deiner gewählten Sprache: Brot zeigt bei schwedischer App-Sprache Bröd. Wenn deaktiviert, wird nur in deiner gewählten Sprache gesucht."
                    ))
                }
                Section(store.text("Shop together", "Handla tillsammans", "Gemeinsam einkaufen")) {
                    NavigationLink {
                        CloudSharingSettingsView(store: store, sync: sync)
                    } label: {
                        Label(store.text("iCloud sharing", "iCloud-delning", "iCloud-Freigaben"), systemImage: "icloud")
                    }
                    NavigationLink {
                        NotificationSettingsView(store: store, sync: sync)
                    } label: {
                        Label(store.text("Change notifications", "Ändringsnotiser", "Änderungsmitteilungen"), systemImage: "bell.badge")
                    }
                }
                Section(store.text("Your catalog", "Din katalog", "Dein Katalog")) {
                    NavigationLink {
                        CustomProductsSettingsView(store: store)
                    } label: {
                        Label(store.text("Custom items", "Egna varor", "Eigene Artikel"), systemImage: "square.and.pencil")
                    }
                    ForEach(CatalogKind.allCases, id: \.self) { kind in
                        NavigationLink {
                            CatalogSettingsView(store: store, kind: kind)
                        } label: {
                            Label(kind.title(store), systemImage: kind.symbol)
                        }
                    }
                    NavigationLink {
                        LocationsSettingsView(store: store)
                    } label: {
                        Label(store.text("Stores & aisle order", "Butiker och avdelningsordning", "Filialen & Abteilungsreihenfolge"), systemImage: "map.fill")
                    }
                }
                Section(store.text("On this device", "På den här enheten", "Auf diesem Gerät")) {
                    LabeledContent(store.text("Lists", "Listor", "Listen"), value: "\(store.lists.filter { !$0.isDeleted }.count)")
                    LabeledContent(store.text("Products", "Produkter", "Produkte"), value: "\(store.activeProducts.count)")
                    Text(store.text("Shopping data and the translated catalog are saved separately on your device.", "Inköpsdata och den översatta katalogen sparas separat på din enhet.", "Einkaufsdaten und der übersetzte Katalog werden getrennt auf deinem Gerät gespeichert."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = store.lastError { Text(error).foregroundStyle(.red) }
                }
                Section {
                    NavigationLink {
                        AboutView(store: store)
                    } label: {
                        Label(store.text("About", "Om", "Über"), systemImage: "info.circle")
                    }
                }

                Section(store.text("Illustrations & colors", "Illustrationer och färger", "Illustrationen & Farben")) {
                    Text("OpenMoji · CC BY-SA 4.0")
                    Text(store.text("Original illustrations and palette by OpenMoji contributors. Artwork used without modification.", "Originalillustrationer och palett av OpenMoji. Bilderna används oförändrade.", "Originalillustrationen und Palette von OpenMoji. Grafiken unverändert verwendet."))
                        .font(.caption)
                    if let url = URL(string: "https://openmoji.org") {
                        Link("OpenMoji", destination: url)
                    }
                    if let url = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/") {
                        Link("Creative Commons BY-SA 4.0", destination: url)
                    }
                }
            }
            .formStyle(.grouped)
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle(store.text("Settings", "Inställningar", "Einstellungen"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("Done", "Klart", "Fertig")) { store.save(); dismiss() }
                }
            }
        }
        .tint(store.theme.accent)
        .frame(minWidth: 320, minHeight: 400)
    }
}

extension CatalogKind {
    func title(_ store: CleverlistStore) -> String {
        switch self {
        case .store: store.text("Store chains", "Butikskedjor", "Handelsketten")
        case .type: store.text("Product types", "Produkttyper", "Produkttypen")
        case .section: store.text("Sections", "Avdelningar", "Abteilungen")
        case .unit: store.text("Units", "Enheter", "Einheiten")
        }
    }
    var symbol: String {
        switch self {
        case .store: "storefront.fill"
        case .type: "tag.fill"
        case .section: "square.grid.2x2.fill"
        case .unit: "scalemass.fill"
        }
    }
}

struct ThemePickerView: View {
    @Bindable var store: CleverlistStore
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 16) {
                ForEach(Theme.allCases) { theme in
                    Button {
                        store.theme = theme
                        store.save()
                    } label: {
                        VStack(spacing: 12) {
                            Image(theme.artwork).resizable().scaledToFit().frame(height: 90)
                            HStack {
                                Text(theme.name(store.language)).font(.headline)
                                if store.theme == theme { Image(systemName: "checkmark.circle.fill") }
                            }
                            HStack(spacing: 5) {
                                Capsule().fill(theme.accent)
                                Capsule().fill(theme.secondary)
                            }.frame(height: 8)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(theme.accent)
                        .background(theme.background, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent.opacity(store.theme == theme ? 1 : 0.15), lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }.padding()
        }
        .modifier(SeasonalScreen(theme: store.theme))
        .navigationTitle(store.text("Seasonal themes", "Årstidsteman", "Saisonale Designs"))
    }
}

struct CatalogSettingsView: View {
    let store: CleverlistStore
    let kind: CatalogKind
    @State private var editing: CatalogTerm?
    @State private var adding = false
    private var terms: [CatalogTerm] {
        store.terms.filter { !$0.isDeleted && $0.kind == kind }.sorted { $0.name.value(store.language) < $1.name.value(store.language) }
    }
    var body: some View {
        List {
            ForEach(terms) { term in
                Button { editing = term } label: {
                    HStack {
                        Circle().fill(Color(hex: term.colorHex)).frame(width: 14, height: 14)
                        Text(term.name.value(store.language)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .modifier(SeasonalScreen(theme: store.theme))
        .navigationTitle(kind.title(store))
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel(store.text("Add", "Lägg till", "Hinzufügen")) }
        .sheet(isPresented: $adding) { TermEditor(store: store, term: CatalogTerm(name: LocalizedName(sv: "", de: "", en: ""), kind: kind)) }
        .sheet(item: $editing) { TermEditor(store: store, term: $0) }
    }
}

struct TermEditor: View {
    let store: CleverlistStore
    @State private var term: CatalogTerm
    
    init(store: CleverlistStore, term: CatalogTerm) {
        self.store = store
        _term = State(initialValue: term)
    }
    @Environment(\.dismiss) private var dismiss
    private var valid: Bool { [term.name.sv, term.name.de, term.name.en].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var body: some View {
        NavigationStack {
            Form {
                Section(store.text("All three translations", "Alla tre översättningar", "Alle drei Übersetzungen")) {
                    TextField("Svenska", text: $term.name.sv)
                    TextField("Deutsch", text: $term.name.de)
                    TextField("English", text: $term.name.en)
                }
                Section(store.text("Color", "Färg", "Farbe")) {
                    ColorSwatches(selection: $term.colorHex)
                }
            }
            .formStyle(.grouped)
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle(term.kind.title(store))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("Cancel", "Avbryt", "Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(store.text("Save", "Spara", "Speichern")) { store.save(term); dismiss() }.disabled(!valid) }
            }
        }.frame(minWidth: 320, minHeight: 360)
    }
}

struct ColorSwatches: View {
    @Binding var selection: String
    private let colors = ["186648", "1E50A0", "781E32", "8967AA", "E27022", "F1B31C", "5C9E31", "E67A94", "3F3F3F"]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))]) {
            ForEach(colors, id: \.self) { hex in
                Button { selection = hex } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 36, height: 36)
                        .overlay { if selection == hex { Image(systemName: "checkmark").foregroundStyle(.white).bold() } }
                }
                .buttonStyle(.plain).accessibilityLabel(hex).accessibilityAddTraits(selection == hex ? .isSelected : [])
            }
        }
    }
}
