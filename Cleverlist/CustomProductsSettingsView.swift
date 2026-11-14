import SwiftUI

struct CustomProductsSettingsView: View {
    let store: CleverlistStore
    @State private var editing: Product?
    @State private var pendingDeletion: Product?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            ForEach(store.customProducts) { product in
                HStack {
                    Button {
                        editing = product
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.name(product.name))
                                .foregroundStyle(.primary)
                            if let section = store.term(product.sectionID) {
                                Text(store.name(section.name))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        pendingDeletion = product
                        showingDeleteConfirmation = true
                    } label: {
                        Label(store.text("Delete", "Radera", "Löschen"), systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(store.text("Delete", "Radera", "Löschen") + " " + store.name(product.name))
                }
            }
        }
        .overlay {
            if store.customProducts.isEmpty {
                ContentUnavailableView {
                    Label(store.text("No custom items", "Inga egna varor", "Keine eigenen Artikel"), systemImage: "basket")
                } description: {
                    Text(store.text("Items you create while shopping appear here for editing.", "Varor som du skapar när du handlar visas här för redigering.", "Artikel, die du beim Einkaufen erstellst, erscheinen hier zum Bearbeiten."))
                }
            }
        }
        .modifier(SeasonalScreen(theme: store.theme))
        .navigationTitle(store.text("Custom items", "Egna varor", "Eigene Artikel"))
        .sheet(item: $editing) { product in
            ProductEditor(store: store, product: product)
        }
        .confirmationDialog(
            store.text("Delete custom item?", "Radera egen vara?", "Eigenen Artikel löschen?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { product in
            Button(store.text("Delete", "Radera", "Löschen"), role: .destructive) {
                store.delete(product)
                pendingDeletion = nil
            }
            Button(store.text("Cancel", "Avbryt", "Abbrechen"), role: .cancel) {
                pendingDeletion = nil
            }
        } message: { product in
            Text(store.text(
                "Remove \\(store.name(product.name)) from your catalog? Existing shopping list entries will keep their details.",
                "Ta bort \\(store.name(product.name)) från din katalog? Befintliga inköpsposter behåller sina uppgifter.",
                "\\(store.name(product.name)) aus deinem Katalog entfernen? Bestehende Einkaufslisteneinträge behalten ihre Details."
            ))
        }
    }
}
