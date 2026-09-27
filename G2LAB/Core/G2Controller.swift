import Foundation
import MentraBluetoothSDK

@MainActor
final class G2Controller: NSObject, ObservableObject, MentraBluetoothSDKDelegate {
    @Published var status = "READY"
    @Published var devices: [Device] = []
    @Published var logs: [String] = []
    @Published var micLevel: Double = 0
    @Published var micPacketCount: Int = 0
    @Published var micEnabled = false
    @Published var batteryLevel: Int? = nil
    @Published var batteryCharging = false
    @Published var signalDbm: Int? = nil

    @Published var menuVisible = false
    @Published var menuSelection = 0

    @Published var captionsEnabled = false
    @Published var captionText = ""
    @Published var captionStatus = "ITALIAN OFFLINE • IDLE"

    private lazy var sdk: MentraBluetoothSDK = {
        let value = MentraBluetoothSDK(configuration: .default)
        value.delegate = self
        return value
    }()

    private lazy var italian: StreamingItalianRecognizer = {
        let recognizer = StreamingItalianRecognizer()
        recognizer.onText = { [weak self] text, isFinal in
            guard let self else { return }

            if isFinal {
                self.commitFinalCaption(text)
                self.currentPartialText = ""
            } else {
                self.currentPartialText = text
            }

            let combined = self.combinedCaptionText()
            self.captionText = combined
            self.captionStatus = isFinal ? "ITALIAN OFFLINE • FINAL" : "ITALIAN OFFLINE • LIVE"
            self.pushCaptionToHUD(combined, force: isFinal)
        }
        return recognizer
    }()

    private var direct: DirectG2Transport?
    private var directLeftReady = false
    private var directRightReady = false

    private var reconnectTask: Task<Void, Never>?
    private var captionHoldTask: Task<Void, Never>?
    private var hasConnectedOnce = false
    private var lastHudPush = Date.distantPast
    private var committedCaptionText = ""
    private var currentPartialText = ""
    private var lastRenderedCaption = ""

    var linkReady: Bool {
        status == "CONNECTED" || status.contains("READY")
    }

    private let menuItems = [
        "ITALIAN LIVE CAPTIONS",
        "MIC TOGGLE",
        "CLEAR HUD",
        "CONNECTION STATUS",
        "CLOSE MENU"
    ]

    override init() {
        super.init()
        // Important: launch does not construct Mentra, Sherpa/ONNX, or CoreBluetooth.
        log("G2 LAB v0.3.1 build 5 — cold launch safe")
    }


    private func startDirectTransportIfNeeded() {
        guard direct == nil else {
            direct?.start()
            return
        }

        log("DIRECT: creating clean-room CoreBluetooth transport")
        let transport = DirectG2Transport()

        transport.onLog = { [weak self] message in
            Task { @MainActor in self?.log(message) }
        }

        transport.onReadyChanged = { [weak self] left, right in
            Task { @MainActor in
                guard let self else { return }
                self.directLeftReady = left
                self.directRightReady = right
                self.log("DIRECT: L=\(left ? "READY" : "—") R=\(right ? "READY" : "—")")
                if left || right {
                    self.status = left && right ? "DIRECT L+R READY" : "DIRECT PARTIAL"
                }
            }
        }

        transport.onPacket = { [weak self] side, data in
            guard data.count >= 8 else { return }
            let svc = String(format: "%02X%02X", data[6], data[7])
            Task { @MainActor in
                guard let self else { return }
                if self.logs.first?.contains("DIRECT RX") != true {
                    self.log("DIRECT RX \(side.rawValue) svc=\(svc) \(data.count)B")
                }
            }
        }

        transport.onMicPacket = { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.micPacketCount += 1
                if data.count > 200 {
                    self.micLevel = min(1.0, Double(data[200]) / 80.0)
                }
                if self.micPacketCount == 1 || self.micPacketCount % 20 == 0 {
                    self.log("DIRECT MIC: 6402 LC3 packet #\(self.micPacketCount) size=\(data.count)")
                }
                if self.captionsEnabled {
                    self.captionStatus = "DIRECT G2 MIC • LC3 \(self.micPacketCount)"
                }
            }
        }

        transport.onProtocolReady = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.status = "DIRECT G2 READY"
                self.log("DIRECT: protocol init complete")
                if self.micEnabled {
                    self.direct?.setMicEnabled(true)
                }
            }
        }

        direct = transport
        transport.start()
    }

    func backgroundRefreshPulse() {
        log("APP: BACKGROUND REFRESH")
        direct?.start()
    }

    func appDidBecomeActive() {
        log("APP: ACTIVE")
        if direct != nil { direct?.start() }
    }

    func appDidEnterBackground() {
        log("APP: BACKGROUND — CoreBluetooth link remains armed")
    }

    func appWillResignActive() {
        log("APP: INACTIVE")
    }

    func scan() {
        devices.removeAll()
        micPacketCount = 0
        micLevel = 0
        status = "DIRECT SCANNING"
        log("DIRECT: scan requested — Mentra transport bypassed")
        startDirectTransportIfNeeded()
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
        direct?.stop()
        direct = nil
        status = "DISCONNECTED"
        log("DIRECT: disconnect requested")
    }

    func showProof() {
        if let direct, direct.isProtocolReady {
            direct.showText("G2 LAB // DIRECT LINK ACTIVE")
            log("DIRECT HUD proof sent")
            return
        }

        Task {
            do {
                try await sdk.displayText("G2 LAB // FALLBACK LINK", x: 0, y: 0, size: 24)
                log("Fallback HUD proof sent")
            } catch {
                log("HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    func clearHUD() {
        if let direct, direct.isProtocolReady {
            direct.clearText()
            log("DIRECT HUD cleared")
            return
        }

        Task {
            do {
                try await sdk.clearDisplay()
                log("Fallback display cleared")
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
            captionHoldTask?.cancel()
            captionHoldTask = nil
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
        if let direct {
            direct.setMicEnabled(enabled)
            log("DIRECT G2 microphone \(enabled ? "ON" : "OFF")")
        } else {
            log("DIRECT MIC: tap Scan first")
        }
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
                activateMenuItem()
            } else if captionsEnabled && !lastRenderedCaption.isEmpty {
                sendCaptionHUD(lastRenderedCaption)
                restartCaptionHoldTimer()
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
            renderMenu()
        case 1:
            toggleMic()
            renderMenu()
        case 2:
            menuVisible = false
            clearHUD()
        case 3:
            menuVisible = false
            showConnectionStatus()
        case 4:
            closeMenu()
        default:
            break
        }
    }

    private func renderMenu() {
        let rows = menuItems.enumerated().map { index, item in
            "\(index == menuSelection ? ">" : " ") \(item)"
        }.joined(separator: "\n")

        let footer = captionsEnabled ? "\n\nCAPTIONS: ON" : "\n\nCAPTIONS: OFF"

        if let direct, direct.isProtocolReady {
            direct.showText("G2 LAB\n\n\(rows)\(footer)")
            return
        }

        Task {
            do {
                try await sdk.displayText("G2 LAB\n\n\(rows)\(footer)", x: 0, y: 0, size: 18)
            } catch {
                log("MENU HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    private func showConnectionStatus() {
        let text = "G2 LAB STATUS\n\n\(status)\nMIC: \(micEnabled ? "ON" : "OFF")\nCAPTIONS: \(captionsEnabled ? "ON" : "OFF")"
        if let direct, direct.isProtocolReady {
            direct.showText(text)
            return
        }

        Task {
            do {
                try await sdk.displayText(text, x: 0, y: 0, size: 18)
            } catch {
                log("STATUS HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    private func commitFinalCaption(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if committedCaptionText.isEmpty {
            committedCaptionText = cleaned
        } else {
            committedCaptionText += " " + cleaned
        }

        if committedCaptionText.count > 700 {
            committedCaptionText = String(committedCaptionText.suffix(700))
        }
    }

    private func combinedCaptionText() -> String {
        let partial = currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)

        if committedCaptionText.isEmpty {
            return partial
        }
        if partial.isEmpty {
            return committedCaptionText
        }
        return committedCaptionText + " " + partial
    }

    private func pushCaptionToHUD(_ text: String, force: Bool) {
        guard captionsEnabled, !menuVisible, !text.isEmpty else { return }

        let now = Date()
        if !force && now.timeIntervalSince(lastHudPush) < 0.12 {
            return
        }
        lastHudPush = now

        let visible = String(text.suffix(220))
        lastRenderedCaption = visible
        sendCaptionHUD(visible)
        restartCaptionHoldTimer()
    }

    private func sendCaptionHUD(_ visible: String) {
        guard captionsEnabled, !menuVisible, !visible.isEmpty else { return }

        if let direct, direct.isProtocolReady {
            direct.showText(visible, final: false)
            return
        }

        Task {
            do {
                try await sdk.displayText(visible, x: 0, y: 0, size: 22)
            } catch {
                log("CAPTION HUD ERROR: \(error.localizedDescription)")
            }
        }
    }

    private func restartCaptionHoldTimer() {
        captionHoldTask?.cancel()

        let snapshot = lastRenderedCaption
        guard !snapshot.isEmpty else { return }

        captionHoldTask = Task { [weak self] in
            guard let self else { return }

            // Keep the last phrase alive on-glass while the speaker pauses.
            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.captionsEnabled, !self.menuVisible else { return }
                self.sendCaptionHUD(snapshot)
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard self.captionsEnabled, !self.menuVisible else { return }

            if !self.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.commitFinalCaption(self.currentPartialText)
                self.currentPartialText = ""
                self.captionText = self.combinedCaptionText()
                self.italian.resetSession()
            }

            self.clearHUD()
            self.log("Caption HUD idle clear after 5s — transcript retained")
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
        batteryLevel = glasses.battery?.level
        batteryCharging = glasses.battery?.charging ?? false
        signalDbm = glasses.signal?.strengthDbm
        log("GLASSES: \(status) battery=\(batteryLevel.map(String.init) ?? "unknown")")

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
