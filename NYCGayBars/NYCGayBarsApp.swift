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

    /// Show friend pushes as banners while the app is foregrounded — and
    /// refresh state so an incoming request's Accept button appears instantly,
    /// not on the next manual refresh. The refresh is detached: its retry loop
    /// can run for seconds and must not delay the banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        Task { await SocialStore.shared.handleRemoteNotification(userInfo) }
        return [.banner, .sound]
    }

    /// Tap on a friend push: "<name> is at <bar>" opens that bar's detail sheet;
    /// a friend request switches to the Friends tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let note = CKNotification(fromRemoteNotificationDictionary: userInfo)
        if note?.subscriptionID == CloudKitSocial.requestSubID {
            SocialStore.shared.focusFriendsTab = true
        }
        // Navigate from the payload immediately; the refresh below can spend
        // seconds retrying against CloudKit consistency.
        if let q = note as? CKQueryNotification,
           let barId = q.recordFields?["barId"] as? String,
           AppData.barsById[barId] != nil {
            SocialStore.shared.deepLinkBarId = barId
        }
        await SocialStore.shared.handleRemoteNotification(userInfo)
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
            // nycgaybars://addfriend?code=X from the add-friend web page / QR.
            .onOpenURL { url in
                social.handleAddFriendLink(url)
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
            }
        }
    }
}
