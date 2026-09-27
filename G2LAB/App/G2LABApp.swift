import SwiftUI
import UIKit

final class G2LABAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // This opts G2 LAB into the legacy Background App Refresh path so iOS
        // exposes the per-app Background App Refresh switch in Settings.
        // BLE continuity itself is handled separately by bluetooth-central +
        // the Mentra G2 keepalive/reconnect layer.
        application.setMinimumBackgroundFetchInterval(
            UIApplication.backgroundFetchIntervalMinimum
        )
        return true
    }

    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(name: .g2LabBackgroundRefresh, object: nil)
        completionHandler(.newData)
    }
}

extension Notification.Name {
    static let g2LabBackgroundRefresh = Notification.Name("G2LABBackgroundRefresh")
}

@main
struct G2LABApp: App {
    @UIApplicationDelegateAdaptor(G2LABAppDelegate.self) private var appDelegate
    @StateObject private var g2 = G2Controller()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(g2)
                .onReceive(NotificationCenter.default.publisher(for: .g2LabBackgroundRefresh)) { _ in
                    g2.backgroundRefreshPulse()
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        g2.appDidBecomeActive()
                    case .inactive:
                        g2.appWillResignActive()
                    case .background:
                        g2.appDidEnterBackground()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
