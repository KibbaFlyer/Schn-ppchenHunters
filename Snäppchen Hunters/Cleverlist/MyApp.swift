import SwiftUI

@main
struct MyApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(CloudAppDelegate.self) private var appDelegate
    #else
    @UIApplicationDelegateAdaptor(CloudAppDelegate.self) private var appDelegate
    #endif
    @State private var store: CleverlistStore
    @State private var sync: CloudSyncService

    init() {
        let store = CleverlistStore()
        _store = State(initialValue: store)
        let sync = CloudSyncService(store: store)
        _sync = State(initialValue: sync)
        CloudInvitationRouter.shared.service = sync
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, sync: sync)
        }
    }
}
