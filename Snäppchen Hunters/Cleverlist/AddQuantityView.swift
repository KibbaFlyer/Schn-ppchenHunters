import SwiftUI

struct AddQuantityView: View {
    let store: CleverlistStore
    let product: Product
    let listID: UUID
    let onAdded: () -> Void
    @State private var amount = ""
    @State private var unitID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(store.text("Quantity", "Mängd", "Menge")) {
                    TextField(store.text("Amount", "Mängd", "Menge"), text: $amount)
                    Picker(store.text("Unit", "Enhet", "Einheit"), selection: $unitID) {
                        Text(store.text("No unit", "Ingen enhet", "Keine Einheit")).tag(nil as UUID?)
                        ForEach(store.catalog(.unit)) { unit in
                            Text(store.name(unit.name)).tag(Optional(unit.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .modifier(SeasonalScreen(theme: store.theme))
            .navigationTitle(store.name(product.name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.text("Cancel", "Avbryt", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("Add", "Lägg till", "Hinzufügen")) {
                        guard store.activeLists.contains(where: { $0.id == listID }) else { dismiss(); return }
                        store.save(ShoppingItem(listID: listID, productID: product.id,
                                                amount: amount.trimmingCharacters(in: .whitespacesAndNewlines),
                                                unitID: unitID))
                        onAdded()
                        dismiss()
                    }
                }
            }
        }
        .tint(store.theme.accent)
        .presentationDetents([.medium, .large])
    }
}

struct ShoppingSwipeContainer: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            content.swipeActionsContainer()
        } else {
            // Older macOS retains the row's existing Remove menu action.
            content
        }
    }
}
