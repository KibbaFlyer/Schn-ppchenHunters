import SwiftUI

struct ContentView: View {
    @State private var store: CleverlistStore
    @State private var sync: CloudSyncService
    @State private var showingSettings = false
    @State private var showingNewList = false
    @State private var listName = ""
    @State private var renamingList: ShoppingList?
    @State private var showingRename = false
    @AppStorage("hunter.lastUsedListID") private var lastUsedListID = ""

    @Environment(\.scenePhase) private var scenePhase
    private let startsSync: Bool

    init(store: CleverlistStore, sync: CloudSyncService, startsSync: Bool = true) {
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        self.startsSync = startsSync
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    hero
                    HStack {
                        Text(store.text("Your lists", "Dina listor", "Deine Listen"))
                            .font(.title2.bold())
                        Spacer()
                        Text("\(store.activeLists.count)")
                            .font(.headline).padding(.horizontal, 12).padding(.vertical, 5)
                            .background(store.theme.accent.opacity(0.14), in: Capsule())
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(store.activeLists) { list in
                            NavigationLink {
                                ShoppingListView(store: store, listID: list.id, sync: sync)
                            } label: {
                                listCard(list)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                NavigationLink { ListSharingView(store: store, sync: sync, listID: list.id) } label: {
                                    Label(store.text("Share list", "Dela lista", "Liste teilen"), systemImage: "person.2")
                                }
                                Button(store.text("Rename", "Byt namn", "Umbenennen"), systemImage: "pencil") {
                                    renamingList = list
                                    listName = list.name
                                    showingRename = true
                                }
                                Button(store.text("Delete list", "Radera lista", "Liste löschen"), systemImage: "trash", role: .destructive) {
                                    store.delete(list)
                                }.disabled(store.linkedCloudListIDs.contains(list.id))
                            }
                        }
                    }
                    Button {
                        listName = ""
                        showingNewList = true
                    } label: {
                        Label(store.text("Start a new adventure", "Starta ett nytt äventyr", "Starte ein neues Abenteuer"), systemImage: "plus.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(20)
                            .foregroundStyle(store.theme.accent)
                            .background(store.theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(store.theme.accent.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.2.wave.2.fill").foregroundStyle(store.theme.accent)
                        Text(store.text("Share individual lists with iCloud. Your other lists stay private.", "Dela enskilda listor via iCloud. Dina andra listor förblir privata.", "Teile einzelne Listen über iCloud. Andere Listen bleiben privat."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.horizontal, 6)
                }
                .padding(22)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle("Cleverlist")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(store.text("Settings", "Inställningar", "Einstellungen"), systemImage: "slider.horizontal.3") {
                        showingSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(store: store, sync: sync) }
            .alert(store.text("New list", "Ny lista", "Neue Liste"), isPresented: $showingNewList) {
                TextField(store.text("List name", "Listans namn", "Listenname"), text: $listName)
                Button(store.text("Create", "Skapa", "Erstellen")) { store.save(ShoppingList(name: listName.trimmingCharacters(in: .whitespacesAndNewlines))) }
                    .disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(store.text("Cancel", "Avbryt", "Abbrechen"), role: .cancel) {}
            }
            .alert(store.text("Rename list", "Byt namn på lista", "Liste umbenennen"), isPresented: $showingRename) {
                TextField(store.text("List name", "Listans namn", "Listenname"), text: $listName)
                Button(store.text("Save", "Spara", "Speichern")) {
                    if var list = renamingList {
                        list.name = listName.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.save(list)
                    }
                }.disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(store.text("Cancel", "Avbryt", "Abbrechen"), role: .cancel) {}
            }
        }
        .tint(store.theme.accent)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .preferredColorScheme(.light)
        .task { if startsSync { sync.resumeIfNeeded() } }
        .onChange(of: scenePhase) { _, phase in
            guard startsSync else { return }
            if phase == .active { sync.resumeIfNeeded() }

        }
    }

    private var recentList: ShoppingList? {
        store.activeLists.first { $0.id.uuidString == lastUsedListID } ?? store.activeLists.first
    }

    @ViewBuilder
    private var hero: some View {
        if let list = recentList {
            NavigationLink {
                ShoppingListView(store: store, listID: list.id, sync: sync)
            } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "arrow.up.right").font(.title2.bold())
                        Text(list.name)
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(store.theme.artwork)
                        .resizable().scaledToFit().frame(maxWidth: 120, maxHeight: 150)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [store.theme.accent, store.theme.secondary], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
            }
            .buttonStyle(.plain)
            .accessibilityHint(store.text("Open your last-used list", "Öppna din senast använda lista", "Zuletzt verwendete Liste öffnen"))
        }
    }

    private func listCard(_ list: ShoppingList) -> some View {
        let items = store.items(in: list.id)
        let completed = items.filter(\.isChecked).count
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "basket.fill")
                    .font(.title2).foregroundStyle(store.theme.accent)
                    .frame(width: 52, height: 52)
                    .background(store.theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                Spacer()
                Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(.secondary)
            }
            Label(sync.status(for: list.id), systemImage: sync.binding(for: list.id) == nil ? "lock" : "person.2")
                .font(.caption).foregroundStyle(.secondary)
            Text(list.name).font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            HStack {
                Text(store.text("\(items.count - completed) left to find", "\(items.count - completed) kvar att hitta", "\(items.count - completed) offen"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(completed)/\(items.count)").font(.caption.monospacedDigit().bold()).foregroundStyle(store.theme.accent)
            }
            ProgressView(value: Double(completed), total: Double(max(items.count, 1)))
                .tint(store.theme.accent)
        }
        .padding(22)
        .background(store.theme.surface, in: RoundedRectangle(cornerRadius: 25))
        .shadow(color: store.theme.accent.opacity(0.12), radius: 10, y: 5)
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(store.theme.accent.opacity(0.10)))
    }
}
