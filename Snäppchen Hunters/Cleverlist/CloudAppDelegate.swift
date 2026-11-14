import CloudKit
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class CloudInvitationRouter {
    static let shared = CloudInvitationRouter()
    weak var service: CloudSyncService? {
        didSet {
            guard service != nil else { return }
            let invitations = pending
            pending.removeAll()
            for invitation in invitations { receive(invitation) }
        }
    }
    private var pending: [CKShare.Metadata] = []

    func receive(_ metadata: CKShare.Metadata) {
        guard let service else { pending.append(metadata); return }
        Task { await service.accept(metadata) }
    }
}

#if os(macOS)
final class CloudAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudInvitationRouter.shared.receive(metadata)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        CloudInvitationRouter.shared.service?.resumeIfNeeded()
    }
}
#else
final class CloudAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let metadata = options.cloudKitShareMetadata { CloudInvitationRouter.shared.receive(metadata) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = CloudSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudInvitationRouter.shared.receive(metadata)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            guard let service = CloudInvitationRouter.shared.service else {
                completionHandler(.noData)
                return
            }
            await service.syncNow()
            completionHandler(service.errorMessage == nil ? .newData : .failed)
        }
    }
}

final class CloudSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudInvitationRouter.shared.receive(metadata)
    }
}
#endif
