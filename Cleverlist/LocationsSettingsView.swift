import SwiftUI

struct LocationsSettingsView: View {
    let store: CleverlistStore
    @State private var editing: StoreLocation?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(store.activeLocations) { location in
                Button { editing = location } label: {
                    Label(location.name, systemImage: "storefront").foregroundStyle(.primary)
                }
            }
            .onDelete { indices in
                let locations = store.activeLocations
                for index in indices { store.delete(locations[index]) }
            }
        }
        .modifier(SeasonalScreen(theme: store.theme))
        .navigationTitle(store.text("Specific stores", "Specifika butiker", "Filialen"))
        .toolbar {
            Button { adding = true } label: { Image(systemName: "plus") }
                .accessibilityLabel(store.text("Add store", "Lägg till butik", "Filiale hinzufügen"))
        }
        .sheet(isPresented: $adding) {
            LocationEditor(store: store, location: StoreLocation(name: "", sectionOrder: store.catalog(.section).map(\.id)))
        }
        .sheet(item: $editing) { LocationEditor(store: store, location: $0) }
    }
}

struct LocationEditor: View {
    let store: CleverlistStore
    @State private var location: StoreLocation
    
    init(store: CleverlistStore, location: StoreLocation) {
        self.store = store
        _location = State(initialValue: location)
    }
    @Environment(\.dismiss) private var dismiss
    private var sections: [CatalogTerm] {
        location.sectionOrder.compactMap { id in store.term(id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(store.text("Store details", "Butiksinformation", "Filialdetails")) {
                    TextField(store.text("Store name", "Butiksnamn", "Filialname"), text: $location.name)
                    CatalogTermPicker(store: store, kind: .store, selection: $location.storeID)
                }
                Section {
                    ForEach(sections) { section in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            Text(section.name.value(store.language)).font(.headline)
                            Spacer()
                            Button { move(section.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(location.sectionOrder.first == section.id)
                                .accessibilityLabel(store.text("Move earlier", "Flytta tidigare", "Nach vorne"))
                            Button { move(section.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(location.sectionOrder.last == section.id)
                                .accessibilityLabel(store.text("Move later", "Flytta senare", "Nach hinten"))
                        }
                        .buttonStyle(.borderless)
                        .padding(10)
                        .background(Color(hex: section.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .onMove { source, destination in location.sectionOrder.move(fromOffsets: source, toOffset: destination) }
                } header: {
                    Text(store.text("Walking route", "Gångväg", "Einkaufsroute"))
                } footer: {
                    Text(store.text("Arrange sections in the order you walk through the store. Drag rows or use the arrows.", "Ordna avdelningarna i den ordning du går genom butiken. Dra raderna eller använd pilarna.", "Ordne die Abteilungen nach deinem Weg durch die Filiale. Ziehe die Zeilen oder nutze die Pfeile."))
                }
            }
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle(store.text("Store layout", "Butikslayout", "Filialaufbau"))
            .onAppear {
                let known = Set(store.catalog(.section).map(\.id))
                location.sectionOrder.removeAll { !known.contains($0) }
                for term in store.catalog(.section) where !location.sectionOrder.contains(term.id) {
                    location.sectionOrder.append(term.id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("Cancel", "Avbryt", "Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("Save", "Spara", "Speichern")) { store.save(location); dismiss() }
                        .disabled(location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) { EditButton() }
                #endif
            }
        }.frame(minWidth: 320, minHeight: 440)
    }
    private func move(_ id: UUID, by offset: Int) {
        guard let index = location.sectionOrder.firstIndex(of: id),
              location.sectionOrder.indices.contains(index + offset) else { return }
        location.sectionOrder.swapAt(index, index + offset)
    }
}

struct CatalogTermPicker: View {
    let store: CleverlistStore
    let kind: CatalogKind
    @Binding var selection: UUID?
    var body: some View {
        Picker(kind.title(store), selection: $selection) {
            Text(store.text("Any", "Alla", "Alle")).tag(nil as UUID?)
            ForEach(store.catalog(kind)) { term in
                Text(term.name.value(store.language)).tag(Optional(term.id))
            }
        }
    }
}

struct NotificationSettingsView: View {
    let store: CleverlistStore
    let sync: CloudSyncService
    @State private var editing: NotificationRule?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Button(store.text("Allow notifications", "Tillåt notiser", "Mitteilungen erlauben")) {
                    Task { await sync.requestNotifications() }
                }
                Text(store.text("Rules apply to changes received from connected people. Filters within a rule must all match; any matching rule can notify you. * matches any text and ? matches one character.", "Regler gäller ändringar från anslutna personer. Alla filter i en regel måste matcha. En matchande regel kan skicka en notis. * matchar valfri text och ? ett tecken.", "Regeln gelten für Änderungen verbundener Personen. Alle Filter einer Regel müssen passen. Jede passende Regel kann eine Mitteilung auslösen. * steht für beliebigen Text, ? für ein Zeichen."))
                    .font(.caption).foregroundStyle(.secondary)
                if let error = sync.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section(store.text("My rules", "Mina regler", "Meine Regeln")) {
                ForEach(store.activeRules) { rule in
                    HStack {
                        Button { editing = rule } label: {
                            VStack(alignment: .leading) {
                                Text(rule.name)
                                Text(rule.namePattern).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Toggle(store.text("Enabled", "Aktiverad", "Aktiv"), isOn: Binding(get: {
                            store.rules.first { $0.id == rule.id }?.isEnabled ?? false
                        }, set: { value in
                            var updated = rule; updated.isEnabled = value; store.save(updated)
                        })).labelsHidden()
                    }
                }
                .onDelete { indices in
                    let rules = store.activeRules
                    for index in indices { store.delete(rules[index]) }
                }
            }
        }
        .modifier(SeasonalScreen(theme: store.theme))
        .navigationTitle(store.text("Notifications", "Notiser", "Mitteilungen"))
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel(store.text("Add rule", "Lägg till regel", "Regel hinzufügen")) }
        .sheet(isPresented: $adding) { RuleEditor(store: store, rule: NotificationRule(name: "")) }
        .sheet(item: $editing) { RuleEditor(store: store, rule: $0) }
    }
}

struct RuleEditor: View {
    let store: CleverlistStore
    @State private var rule: NotificationRule
    
    init(store: CleverlistStore, rule: NotificationRule) {
        self.store = store
        _rule = State(initialValue: rule)
    }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(store.text("Rule name", "Regelnamn", "Regelname"), text: $rule.name)
                Picker(store.text("List", "Lista", "Liste"), selection: $rule.listID) {
                    Text(store.text("All lists", "Alla listor", "Alle Listen")).tag(nil as UUID?)
                    ForEach(store.activeLists) { list in Text(list.name).tag(Optional(list.id)) }
                }
                CatalogTermPicker(store: store, kind: .store, selection: $rule.storeID)
                CatalogTermPicker(store: store, kind: .type, selection: $rule.typeID)
                CatalogTermPicker(store: store, kind: .section, selection: $rule.sectionID)
                TextField(store.text("Name pattern (e.g. *milk*)", "Namnmönster (t.ex. *mjölk*)", "Namensmuster (z. B. *milch*)"), text: $rule.namePattern)
                Text(store.text("Names match in your selected language, ignoring case.", "Namn matchas på ditt valda språk, oavsett stora eller små bokstäver.", "Namen werden in deiner gewählten Sprache ohne Beachtung der Großschreibung verglichen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle(store.text("Notification rule", "Notisregel", "Mitteilungsregel"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("Cancel", "Avbryt", "Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("Save", "Spara", "Speichern")) { store.save(rule); dismiss() }
                        .disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.frame(minWidth: 320, minHeight: 400)
    }
}
