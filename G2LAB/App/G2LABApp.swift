import SwiftUI

@main
struct G2LABApp: App {
    @StateObject private var g2 = G2Controller()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(g2) }
    }
}
