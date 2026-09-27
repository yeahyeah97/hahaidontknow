import Foundation
import MentraBluetoothSDK

@MainActor
final class G2Controller: NSObject, ObservableObject, MentraBluetoothSDKDelegate {
    @Published var status = "READY"
    @Published var devices: [Device] = []
    @Published var logs: [String] = []
    @Published var micLevel: Double = 0
    @Published var micEnabled = false

    @Published var menuVisible = false
    @Published var menuSelection = 0

    @Published var captionsEnabled = false
    @Published var captionText = ""
    @Published var captionStatus = "ITALIAN OFFLINE • IDLE"

    private let sdk = MentraBluetoothSDK(configuration: .default)
    private let italian = OfflineItalianRecognizer()

    private var reconnectTask: Task<Void, Never>?
    private var hasConnectedOnce = false
    private var lastHudPush = Date.distantPast

    private let menuItems = [
        "ITALIAN LIVE CAPTIONS",
        "MIC TOGGLE",
        "CLEAR HUD",
        "CONNECTION STATUS"
    ]

    override init() {
        super.init()
        sdk.delegate = self

        italian.onText = { [weak self] text, isFinal in
            guard let self else { return }
            self.captionText = text
            self.captionStatus = isFinal ? "ITALIAN OFFLINE • FINAL" : "ITALIAN OFFLINE • LIVE"
            self.pushCaptionToHUD(text, force: isFinal)
        }

        log("G2 LAB v0.2 boot")
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
            sdk.setDefaultDevice(device)
            log("Saved G2 as default device")
        } catch {
            status = "CONNECT ERROR"
            log("CONNECT ERROR: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        hasConnectedOnce = false
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
        setMic(!micEnabled)
    }

    func toggleCaptions() {
        captionsEnabled.toggle()

        if captionsEnabled {
            if !micEnabled {
                setMic(true)
            }
            italian.start()
            captionStatus = "ITALIAN OFFLINE • STARTING"
            log("Italian offline captions ON")
        } else {
            italian.stop()
            captionStatus = "ITALIAN OFFLINE • IDLE"
            log("Italian offline captions OFF")
        }
    }

    func openMenu() {
        menuVisible = true
        menuSelection = 0
        renderMenu()
        log("G2 LAB menu OPEN")
    }

    func closeMenu() {
        menuVisible = false
        clearHUD()
        log("G2 LAB menu CLOSED")
    }

    private func setMic(_ enabled: Bool) {
        micEnabled = enabled
        sdk.setPreferredMic(.auto)
        sdk.setMicState(enabled: enabled, useGlassesMic: true)
        log("G2 microphone \(enabled ? "ON" : "OFF")")
    }

    private func handleGesture(_ name: String, source: Any?) {
        log("GESTURE: \(name) source=\(String(describing: source))")

        switch name {
        case "double_tap":
            if menuVisible {
                activateMenuItem()
            } else {
                openMenu()
            }

        case "single_tap":
            if menuVisible {
                closeMenu()
            }

        case "swipe_up":
            guard menuVisible else { return }
            menuSelection = (menuSelection - 1 + menuItems.count) % menuItems.count
            renderMenu()

        case "swipe_down":
            guard menuVisible else { return }
            menuSelection = (menuSelection + 1) % menuItems.count
            renderMenu()

        default:
            break
        }
    }

    private func activateMenuItem() {
        switch menuSelection {
        case 0:
            toggleCaptions()
        case 1:
            toggleMic()
        case 2:
            clearHUD()
        case 3:
            showConnectionStatus()
        default:
            break
        }

        if menuVisible {
            renderMenu()
        }
    }

    private func renderMenu() {
        let rows = menuItems.enumerated().map { index, item in
            "\(index == menuSelection ? ">" : " ") \(item)"
        }.joined(separator: "\n")

        let footer = captionsEnabled ? "\n\nCAPTIONS: ON" : "\n\nCAPTIONS: OFF"

        Task {
            do {
                try await sdk.displayText("G2 LAB\n\n\(rows)\(footer)", x: 0, y: 0, size: 18)
            } catch {
                log("MENU HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    private func showConnectionStatus() {
        Task {
            do {
                try await sdk.displayText(
                    "G2 LAB STATUS\n\n\(status)\nMIC: \(micEnabled ? "ON" : "OFF")\nCAPTIONS: \(captionsEnabled ? "ON" : "OFF")",
                    x: 0,
                    y: 0,
                    size: 18
                )
            } catch {
                log("STATUS HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    private func pushCaptionToHUD(_ text: String, force: Bool) {
        guard captionsEnabled, !menuVisible, !text.isEmpty else { return }

        let now = Date()
        if !force && now.timeIntervalSince(lastHudPush) < 0.12 {
            return
        }
        lastHudPush = now

        let visible = String(text.suffix(220))

        Task {
            do {
                try await sdk.displayText(visible, x: 0, y: 0, size: 22)
            } catch {
                log("CAPTION HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleReconnect() {
        guard hasConnectedOnce, reconnectTask == nil else { return }

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }

            do {
                self.log("Background reconnect attempt…")
                try self.sdk.connectDefault()
                self.reconnectTask = nil
            } catch {
                self.log("Reconnect failed: \(error.localizedDescription)")
                self.reconnectTask = nil

                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                self.scheduleReconnect()
            }
        }
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

        if glasses.connected {
            hasConnectedOnce = true
            reconnectTask?.cancel()
            reconnectTask = nil
        } else {
            scheduleReconnect()
        }
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didReceive event: BluetoothEvent) {
        switch event {
        case let .touch(touch):
            handleGesture(touch.gestureName ?? "unknown", source: touch.values["source"])

        default:
            log("EVENT: \(String(describing: event))")
        }
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

        if captionsEnabled {
            italian.appendPCM16(data)
        }
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didLog message: String) {
        log("SDK: \(message)")
    }
}
