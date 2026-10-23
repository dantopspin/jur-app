// Push notifications: ask once (after onboarding), then hand the APNs token to the server.
import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        QNavBar.apply()
        Hints.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await Backend.registerPush(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    // Show banners while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    // A tap on a notification: go where its "url" points.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let path = response.notification.request.content.userInfo["url"] as? String ?? "/discover"
        await MainActor.run { Router.shared.open(path: path) }
    }
}

enum Push {
    /// Asks for permission (once; later calls just re-register) and registers with APNs.
    static func enable() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// "Not now" pressed: don't invite again for a week.
    static func remindLater() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: laterKey)
    }

    /// True for someone iOS has never asked (skipped it in onboarding a week ago, or signed in
    /// to an existing profile, which skips onboarding). Once asked, iOS never shows its prompt
    /// again, so after that the only way back is the Settings row.
    static func shouldInvite() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return false }
        let last = UserDefaults.standard.double(forKey: laterKey)
        return last == 0 || Date.now.timeIntervalSince1970 - last > 7 * 24 * 3600
    }

    private static let laterKey = "jur.pushLaterAt"

    /// Re-registers on launch if permission was already given.
    static func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }
}
