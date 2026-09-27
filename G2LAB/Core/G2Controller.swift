import Foundation
import MentraBluetoothSDK

@MainActor
final class G2Controller: NSObject, ObservableObject, MentraBluetoothSDKDelegate {
    @Published var status = "READY"
    @Published var devices: [Device] = []
    @Published var logs: [String] = []
    @Published var micLevel: Double = 0
    @Published var micEnabled = false

    private let sdk = MentraBluetoothSDK(configuration: .default)

    override init() {
        super.init()
        sdk.delegate = self
        log("G2 LAB v0.1 boot")
    }

    func scan() {
        devices.removeAll()
        status = "SCANNING"
        log("Scanning for Even Realities G2…")
        do {
            try sdk.startScan(model: .g2)
        } catch {
            status = "SCAN ERROR"
            log("SCAN ERROR: \(error.localizedDescription)")
        }
    }

    func connect(_ device: Device) {
        status = "CONNECTING"
        log("Connecting: \(device.name)")
        do {
            try sdk.connect(to: device)
        } catch {
            status = "CONNECT ERROR"
            log("CONNECT ERROR: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        sdk.disconnect()
        status = "DISCONNECTED"
        log("Disconnect requested")
    }

    func showProof() {
        Task {
            do {
                try await sdk.displayText("G2 LAB // LINK ACTIVE", x: 0, y: 0, size: 24)
                log("HUD proof sent")
            } catch {
                log("HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    func clearHUD() {
        Task {
            do {
                try await sdk.clearDisplay()
                log("Display cleared")
            } catch {
                log("CLEAR ERROR: \(error.localizedDescription)")
            }
        }
    }

    func toggleMic() {
        micEnabled.toggle()
        sdk.setPreferredMic(.auto)
        sdk.setMicState(enabled: micEnabled, useGlassesMic: true, bypassVad: false)
        log("G2 microphone \(micEnabled ? "ON" : "OFF")")
    }

    private func log(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        logs.insert("\(f.string(from: Date()))  \(s)", at: 0)
        if logs.count > 150 {
            logs.removeLast(logs.count - 150)
        }
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didDiscover device: Device) {
        if !devices.contains(where: { $0.id == device.id }) {
            devices.append(device)
        }
        log("FOUND: \(device.name)")
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didUpdateGlasses glasses: GlassesRuntimeState) {
        status = glasses.connected ? "CONNECTED" : "DISCONNECTED"
        log("GLASSES: \(status)")
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didReceive event: BluetoothEvent) {
        log("EVENT: \(String(describing: event))")
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didReceiveMicPcm event: MicPcmEvent) {
        let data = event.pcm
        guard data.count >= 2 else { return }

        var sum = 0.0
        var n = 0
        data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            var i = 0
            while i + 1 < b.count {
                let u = UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
                let s = Double(Int16(bitPattern: u)) / 32768.0
                sum += s * s
                n += 1
                i += 2
            }
        }
        if n > 0 {
            micLevel = min(1, sqrt(sum / Double(n)) * 4)
        }
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didLog message: String) {
        log("SDK: \(message)")
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didFail error: BluetoothError) {
        log("SDK ERROR: \(error)")
    }
}
