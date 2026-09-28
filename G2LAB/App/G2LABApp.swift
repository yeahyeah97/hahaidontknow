import SwiftUI

@main
struct G2LABApp: App {
    @StateObject private var models: WhisperModelManager
    @StateObject private var g2: G2Controller

    init() {
        let modelManager = WhisperModelManager()
        _models = StateObject(wrappedValue: modelManager)
        _g2 = StateObject(wrappedValue: G2Controller(models: modelManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(g2)
                .environmentObject(models)
        }
    }
}
