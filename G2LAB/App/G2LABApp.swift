import SwiftUI

@main
struct G2LABApp: App {
    @StateObject private var g2 = G2Controller()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(g2)
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
