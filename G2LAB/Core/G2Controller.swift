import Foundation
import MentraBluetoothSDK

@MainActor
final class G2Controller: NSObject, ObservableObject, MentraBluetoothSDKDelegate {
    @Published var status = "IDLE"
    @Published var devices: [Device] = []
    @Published var logs: [String] = []
    @Published var micLevel: Double = 0
    @Published var micPacketCount: Int = 0
    @Published var micEnabled = false
    @Published var micActive = false
    @Published var pcmActive = false
    @Published var asrLive = false
    private var lc3: G2LC3Decoder?
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
            guard let self, self.captionsEnabled else { return }
            self.asrLive = true

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
    private var pendingHUDTask: Task<Void, Never>?
    private var hasConnectedOnce = false
    private var lastHudPush = Date.distantPast
    private var committedCaptionText = ""
    private var currentPartialText = ""
    private var lastRenderedCaption = ""

    var linkReady: Bool {
        direct?.isProtocolReady == true
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
        log("G2 LAB v0.4.0 build 7 — cold launch safe")
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
                    self.status = left && right ? "DIRECT GATT L+R" : "DIRECT GATT PARTIAL"
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
            // CoreBluetooth uses the main queue; process the 50-ms packet immediately.
            MainActor.assumeIsolated { self?.acceptMicPacket(data) }
        }
        transport.onMicUnavailable = { [weak self] in
            MainActor.assumeIsolated { self?.stopAudioSession() }
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
        startLink()
    }

    func startLink() {
        if direct == nil {
            status = "DIRECT STARTING"
            log("DIRECT: auto-start requested")
            startDirectTransportIfNeeded()
        } else {
            direct?.start()
        }
    }

    func appDidEnterBackground() {
        stopAudioSession()
        log("APP: BACKGROUND — foreground caption session stopped")
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
        stopAudioSession()
        reconnectTask?.cancel()
        reconnectTask = nil
        hasConnectedOnce = false
        direct?.stop()
        direct = nil
        status = "DISCONNECTED"
        log("DIRECT: disconnect requested")
    }

    func showProof() {
        guard let direct, direct.isProtocolReady else {
            log("DIRECT HUD TEST BLOCKED: no verified G2 link")
            return
        }
        direct.showText("G2 LAB\nDIRECT LINK ACTIVE")
        log("DIRECT HUD proof queued")
    }

    func clearHUD() {
        guard let direct, direct.isProtocolReady else {
            log("DIRECT CLEAR BLOCKED: no verified G2 link")
            return
        }
        direct.clearText()
        log("DIRECT HUD clear queued")
    }

    func toggleMic() {
        setMic(!micEnabled)
    }

    func toggleCaptions() {
        if captionsEnabled { stopAudioSession(); return }
        guard linkReady, direct?.micAvailable == true else {
            captionStatus = "DIRECT G2 + LEFT AUDIO NOTIFY REQUIRED"
            return
        }
        guard prepareAudioSession() else { return }
        captionsEnabled = true
        currentPartialText = ""
        italian.resetSession()
        italian.start()
        captionStatus = "WAITING FOR G2 AUDIO"
        direct?.setMicEnabled(true)
    }

    private func prepareAudioSession() -> Bool {
        guard let decoder = G2LC3Decoder() else {
            captionStatus = "LC3 INITIALIZATION FAILED"
            return false
        }
        lc3 = decoder
        micEnabled = true
        micActive = false
        pcmActive = false
        asrLive = false
        micPacketCount = 0
        micLevel = 0
        return true
    }

    private func stopAudioSession() {
        direct?.setMicEnabled(false)
        pendingHUDTask?.cancel()
        pendingHUDTask = nil
        direct?.cancelCaptionUpdates()
        let wasCaptioning = captionsEnabled
        captionsEnabled = false
        micEnabled = false
        micActive = false
        pcmActive = false
        asrLive = false
        lc3 = nil
        micLevel = 0
        if wasCaptioning { italian.stop() }
        captionHoldTask?.cancel()
        captionHoldTask = nil
        captionStatus = "ITALIAN OFFLINE • IDLE"
    }

    private func acceptMicPacket(_ data: Data) {
        guard micEnabled, let decoder = lc3 else { return }
        if data.count == 205 { micActive = true }
        let pcm = decoder.decode(data)
        micPacketCount = decoder.packets
        pcmActive = decoder.decodedFrames > 0
        if let pcm {
            micLevel = min(1, decoder.rms * 4)
            if captionsEnabled {
                italian.appendPCM16(pcm)
                if !asrLive { captionStatus = "PCM ACTIVE • " + italian.status }
            }
        }
        if decoder.packets == 1 || decoder.packets % 20 == 0 {
            log("MIC packets=\(decoder.packets) size=\(data.count) seq=\(decoder.sequence.map(String.init) ?? "-") missing=\(decoder.missing) duplicates=\(decoder.duplicates) malformed=\(decoder.malformed) frames=\(decoder.decodedFrames) samples=\(decoder.sampleCount) rms=\(decoder.rms)")
        }
    }

    func openMenu() {
        guard linkReady else {
            menuVisible = false
            log("DIRECT MENU BLOCKED: no verified RIGHT-lens 5402 response")
            return
        }
        menuVisible = true
        menuSelection = 0
        renderMenu()
        log("DIRECT G2 menu queued")
    }

    func closeMenu() {
        menuVisible = false
        clearHUD()
        log("G2 LAB menu CLOSED")
    }

    private func setMic(_ enabled: Bool) {
        if !enabled { stopAudioSession(); return }
        guard linkReady, direct?.micAvailable == true, prepareAudioSession() else { return }
        direct?.setMicEnabled(true)
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

        guard let direct, direct.isProtocolReady else {
            log("DIRECT MENU RENDER BLOCKED: protocol not ready")
            return
        }
        direct.showText("G2 LAB\n\n\(rows)\(footer)")
    }

    private func showConnectionStatus() {
        let text = "G2 LAB STATUS\n\n\(status)\nMIC: \(micEnabled ? "ON" : "OFF")\nCAPTIONS: \(captionsEnabled ? "ON" : "OFF")"
        guard let direct, direct.isProtocolReady else {
            log("DIRECT STATUS HUD BLOCKED: protocol not ready")
            return
        }
        direct.showText(text)
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
            pendingHUDTask?.cancel()
            let delay = 0.12 - now.timeIntervalSince(lastHudPush)
            pendingHUDTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.pushCaptionToHUD(text, force: true)
            }
            return
        }
        pendingHUDTask?.cancel()
        pendingHUDTask = nil
        lastHudPush = now

        var visible = String(text.suffix(220))
        // Leave room for protobuf/page wrapping inside the existing 253-byte payload.
        while visible.utf8.count > 190 { visible.removeFirst() }
        lastRenderedCaption = visible
        sendCaptionHUD(visible)
        restartCaptionHoldTimer()
    }

    private func sendCaptionHUD(_ visible: String) {
        guard captionsEnabled, !menuVisible, !visible.isEmpty else { return }

        guard let direct, direct.isProtocolReady else {
            log("DIRECT CAPTION HUD BLOCKED: protocol not ready")
            return
        }
        direct.showCaption(visible)
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
            break
        }
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didReceiveMicPcm event: MicPcmEvent) {
        // Captions accept only decoded LEFT audio from the direct transport.
    }

    func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didLog message: String) {
        // SDK log payloads are not part of the metadata-only diagnostics contract.
    }
}
