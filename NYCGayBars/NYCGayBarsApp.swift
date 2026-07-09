import SwiftUI
import UIKit
import CloudKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // CloudKit subscription pushes require remote-notification registration.
        // This does not prompt the user; the alert permission prompt happens in
        // Friends onboarding via UNUserNotificationCenter.
        application.registerForRemoteNotifications()
        return true
    }

    /// Silent CloudKit pushes (friendship acceptance) and background alerts.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await SocialStore.shared.handleRemoteNotification(userInfo)
        return .newData
    }

    /// Show friend pushes as banners while the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Tap on "<name> is at <bar>" → open that bar's detail sheet.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await SocialStore.shared.handleRemoteNotification(userInfo)
        if let note = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
           let barId = note.recordFields?["barId"] as? String,
           AppData.barsById[barId] != nil {
            SocialStore.shared.deepLinkBarId = barId
        }
    }
}

@main
struct NYCGayBarsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var visits = VisitsStore()
    @StateObject private var badges = BadgesStore()
    @StateObject private var social = SocialStore.shared
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppBackground()
                RootTabView()
                    .environmentObject(visits)
                    .environmentObject(badges)
                    .environmentObject(social)
                if showSplash {
                    Splash().transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
            }
        }
    }
}
