import SwiftUI

struct AboutView: View {
    let store: CleverlistStore

    var body: some View {
        List {
            AboutAppSection(store: store)
            AboutDataSection(store: store)
            AboutSupportSection(store: store)
        }
        .modifier(SeasonalScreen(theme: store.theme))
        .navigationTitle(store.text("About", "Om", "Über"))
    }
}

private struct AboutAppSection: View {
    let store: CleverlistStore

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "cart.fill")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(store.theme.accent)
                Text("Cleverlist")
                    .font(.title2.bold())
                Text(store.text(
                    "A local-first shopping list for everyday errands. Organize your catalog, shop together through iCloud, and keep control of your data.",
                    "En lokal först-inköpslista för vardagens ärenden. Organisera din katalog, handla tillsammans via iCloud och behåll kontrollen över dina data.",
                    "Eine lokale Einkaufsliste für den Alltag. Organisiere deinen Katalog, kaufe über iCloud gemeinsam ein und behalte die Kontrolle über deine Daten."
                ))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Text(store.text("Version", "Version", "Version") + " " + version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            if let repository = CleverlistLinks.repository {
                Link(destination: repository) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
    }
}

private struct AboutDataSection: View {
    let store: CleverlistStore

    var body: some View {
        Section(store.text("Your data", "Dina data", "Deine Daten")) {
            Text(store.text(
                "Lists, catalog entries, locations, preferences, and notification rules stay on this device. iCloud is used only when you choose to share a list; the shared list and its items are then stored in Apple CloudKit for the invited participants.",
                "Listor, katalogposter, platser, inställningar och aviseringsregler stannar på den här enheten. iCloud används bara när du väljer att dela en lista; den delade listan och dess varor lagras då i Apple CloudKit för de inbjudna deltagarna.",
                "Listen, Katalogeinträge, Filialen, Einstellungen und Benachrichtigungsregeln bleiben auf diesem Gerät. iCloud wird nur verwendet, wenn du eine Liste teilst; die geteilte Liste und ihre Artikel werden dann in Apple CloudKit für die eingeladenen Personen gespeichert."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let privacy = CleverlistLinks.privacy {
                Link(store.text("Data use & privacy", "Datennutzung & integritet", "Datennutzung & Datenschutz"), destination: privacy)
            }
        }
    }
}

private struct AboutSupportSection: View {
    let store: CleverlistStore

    var body: some View {
        Section(store.text("Support", "Support", "Support")) {
            if let support = CleverlistLinks.support {
                Link(store.text("Support documentation", "Supportdokumentation", "Support-Dokumentation"), destination: support)
            }
            if let issues = CleverlistLinks.issues {
                Link(store.text("Report an issue", "Rapportera ett problem", "Problem melden"), destination: issues)
            }
            Text(store.text(
                "GitHub issues are public. Do not include shopping lists, invitation links, or other personal information in a report.",
                "GitHub-ärenden är offentliga. Lägg inte till inköpslistor, inbjudningslänkar eller annan personlig information i en rapport.",
                "GitHub-Issues sind öffentlich. Füge einem Bericht keine Einkaufslisten, Einladungslinks oder andere personenbezogene Informationen hinzu."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private enum CleverlistLinks {
    static let repository = URL(string: "https://github.com/KibbaFlyer/Schn-ppchenHunters")
    static let issues = URL(string: "https://github.com/KibbaFlyer/Schn-ppchenHunters/issues/new/choose")
    static let support = URL(string: "https://kibbaflyer.github.io/Schn-ppchenHunters/support/")
    static let privacy = URL(string: "https://kibbaflyer.github.io/Schn-ppchenHunters/privacy/")
}
