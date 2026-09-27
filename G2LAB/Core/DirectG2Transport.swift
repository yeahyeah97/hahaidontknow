import Foundation
import CoreBluetooth

/// Clean-room G2 transport built from public protocol documentation and
/// observable BLE behavior. Nothing here depends on Mentra's connection stack.
final class DirectG2Transport: NSObject {
    enum Side: String { case left = "L", right = "R" }

    final class Lens {
        let side: Side
        let peripheral: CBPeripheral
        var commandWrite: CBCharacteristic?
        var commandNotify: CBCharacteristic?
        var micNotify: CBCharacteristic?
        var commandReady = false

        init(side: Side, peripheral: CBPeripheral) {
            self.side = side
            self.peripheral = peripheral
        }
    }

    var onLog: ((String) -> Void)?
    var onReadyChanged: ((Bool, Bool) -> Void)?
    var onPacket: ((Side, Data) -> Void)?
    var onMicPacket: ((Data) -> Void)?
    var onProtocolReady: (() -> Void)?

    private var central: CBCentralManager?
    private var lenses: [UUID: Lens] = [:]
    private var heartbeat: Timer?
    private var protocolStarted = false
    private(set) var isProtocolReady = false
    private var wantsMic = false
    private var conversateStarted = false

    private static let commandWriteSuffix = "5401"
    private static let commandNotifySuffix = "5402"
    private static let displayWriteSuffix = "6402"

    private var transportSeq: UInt8 = 0x08
    private var msgID: UInt8 = 0x14

    override init() {
        // Zero CoreBluetooth work during application launch.
        super.init()
    }

    func start() {
        if central == nil {
            onLog?("DIRECT: creating CBCentralManager on demand")
            central = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
            return
        }

        if central?.state == .poweredOn {
            scan()
        } else {
            onLog?("DIRECT: Bluetooth not powered on yet")
        }
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        central?.stopScan()
        for lens in lenses.values {
            central?.cancelPeripheralConnection(lens.peripheral)
        }
        lenses.removeAll()
        protocolStarted = false
        isProtocolReady = false
        conversateStarted = false
        publishReady()
        onLog?("DIRECT: stopped")
    }

    func setMicEnabled(_ enabled: Bool) {
        wantsMic = enabled
        guard isProtocolReady else {
            onLog?("DIRECT MIC: \(enabled ? "armed — waiting for protocol ready" : "off")")
            return
        }
        enabled ? enableMicPath() : disableMicPath()
    }

    func showText(_ text: String, final: Bool = true) {
        guard isProtocolReady else {
            onLog?("DIRECT HUD: blocked — no verified G2 protocol link")
            return
        }
        sendTeleprompter(text)
    }

    func clearText() {
        guard isProtocolReady else { return }
        sendTeleprompter(" ")
    }

    private func sendTeleprompter(_ text: String) {
        // Known-working clean-room teleprompter path:
        // 0E-20 display config -> 06-20 init -> 06-20 content pages -> 80-00 sync.
        let displayConfig = Self.hex(
            "08011213080210904E1D00E094442500000000280030001213" +
            "0803100D0F1D00408D442500000000280030001212080410" +
            "001D000088422500000000280030001212080510001D0000" +
            "9242250000A242280030001212080610001D0000C6422500" +
            "00C442280030001800"
        )

        let cfgID = nextMsgID()
        var cfgPayload: [UInt8] = [0x08, 0x02, 0x10, cfgID, 0x22]
        cfgPayload += Self.varint(UInt64(displayConfig.count))
        cfgPayload += displayConfig

        let lines = Self.wrap(text: text, width: 25, maxLines: 10)
        let contentHeight = max(1, (max(lines.count, 1) * 2665) / 140)
        var display: [UInt8] = [0x08,0x01,0x10,0x00,0x18,0x00,0x20,0x8B,0x02,0x28]
        display += Self.varint(UInt64(contentHeight))
        display += [0x30,0xE6,0x01,0x38,0x8E,0x0A,0x40,0x05,0x48,0x00]
        var settings: [UInt8] = [0x08,0x01,0x12]
        settings += Self.varint(UInt64(display.count))
        settings += display
        var initPayload: [UInt8] = [0x08,0x01,0x10,nextMsgID(),0x1A]
        initPayload += Self.varint(UInt64(settings.count))
        initPayload += settings

        let page0 = Self.pageText(lines)
        var pages = [page0]
        while pages.count < 14 { pages.append(Self.blankPage()) }

        send(serviceHi: 0x0E, serviceLo: 0x20, payload: cfgPayload)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            self?.send(serviceHi: 0x06, serviceLo: 0x20, payload: initPayload)
        }

        var t = 0.80
        for i in 0..<10 {
            let page = pages[i]
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                self?.sendContentPage(index: i, text: page)
            }
            t += 0.10
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            guard let self else { return }
            self.send(serviceHi: 0x06, serviceLo: 0x20,
                      payload: [0x08,0xFF,0x01,0x10,self.nextMsgID(),0x6A,0x04,0x08,0x00,0x10,0x06])
        }
        t += 0.10

        for i in 10..<12 {
            let page = pages[i]
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                self?.sendContentPage(index: i, text: page)
            }
            t += 0.10
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            guard let self else { return }
            self.send(serviceHi: 0x80, serviceLo: 0x00,
                      payload: [0x08,0x0E,0x10,self.nextMsgID(),0x6A,0x00])
        }
        t += 0.10

        for i in 12..<14 {
            let page = pages[i]
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                self?.sendContentPage(index: i, text: page)
            }
            t += 0.10
        }

        onLog?("DIRECT HUD: teleprompter frame queued on RIGHT lens")
    }

    private func sendContentPage(index: Int, text: String) {
        let bytes = Array(("\n" + text).utf8)
        var inner: [UInt8] = [0x08]
        inner += Self.varint(UInt64(index))
        inner += [0x10,0x0A,0x1A]
        inner += Self.varint(UInt64(bytes.count))
        inner += bytes

        var payload: [UInt8] = [0x08,0x03,0x10,nextMsgID(),0x2A]
        payload += Self.varint(UInt64(inner.count))
        payload += inner
        send(serviceHi: 0x06, serviceLo: 0x20, payload: payload)
    }

    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        onLog?("DIRECT: scanning for Even G2 L/R")
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func side(for name: String) -> Side? {
        let u = name.uppercased()
        guard u.contains("G2") else { return nil }
        if u.contains("_L_") || u.hasSuffix("_L") { return .left }
        if u.contains("_R_") || u.hasSuffix("_R") { return .right }
        return nil
    }

    private func attach(_ peripheral: CBPeripheral, side: Side) {
        guard lenses[peripheral.identifier] == nil else { return }
        let lens = Lens(side: side, peripheral: peripheral)
        lenses[peripheral.identifier] = lens
        peripheral.delegate = self
        onLog?("DIRECT: found \(side.rawValue) \(peripheral.name ?? peripheral.identifier.uuidString)")
        central?.connect(
            peripheral,
            options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true]
        )
    }

    private func publishReady() {
        let left = lenses.values.contains { $0.side == .left && $0.commandReady }
        let right = lenses.values.contains { $0.side == .right && $0.commandReady }
        onReadyChanged?(left, right)
    }

    private func primaryLens() -> Lens? {
        // Official-app captures drive the RIGHT lens for app/display traffic.
        lenses.values.first(where: { $0.side == .right && $0.commandReady })
    }

    private func lens(_ side: Side) -> Lens? {
        lenses.values.first(where: { $0.side == side && $0.commandReady })
    }

    private func tryStartProtocol() {
        guard !protocolStarted, let primary = primaryLens() else { return }
        protocolStarted = true
        onLog?("DIRECT: L command channel ready; starting capture-derived auth")

        let auth = authPackets()
        for (index, packet) in auth.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.10)) { [weak self, weak primary] in
                guard let self, let primary, let write = primary.commandWrite else { return }
                primary.peripheral.writeValue(packet, for: write, type: .withoutResponse)
                self.onLog?("DIRECT: auth \(index + 1)/7")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { [weak self] in
            self?.sendCoreInit()
        }
    }

    private func sendCoreInit() {
        guard primaryLens() != nil else { return }
        transportSeq = 0x08
        msgID = 0x14

        // Safe core subset from current G2 official-app captures / clean-room
        // implementations. No developer/debug configuration writes.
        var messages: [(UInt8, UInt8, [UInt8])] = []

        messages.append((0x80, 0x00, [
            0x08, 0x04, 0x10, nextMsgID(), 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
        ]))
        messages.append((0x80, 0x20, [
            0x08, 0x05, 0x10, nextMsgID(), 0x22, 0x02, 0x08, 0x02
        ]))
        messages.append((0x80, 0x20, timeSyncPayload(msgID: nextMsgID())))

        messages.append((0x09, 0x20, [
            0x08, 0x01, 0x10, nextMsgID(),
            0x1A, 0x0C, 0x4A, 0x0A, 0x08, 0x00, 0x10, 0x00,
            0x18, 0x00, 0x20, 0x02, 0x28, 0x01
        ]))
        messages.append((0x0D, 0x20, [0x08, 0x00, 0x10, nextMsgID()]))
        messages.append((0x0C, 0x20, [
            0x08, 0x02, 0x10, nextMsgID(), 0x22, 0x04, 0x08, 0x01, 0x10, 0x00
        ]))
        messages.append((0x07, 0x20, [
            0x08, 0x0A, 0x10, nextMsgID(), 0x6A, 0x04, 0x08, 0x00, 0x10, 0x50
        ]))
        messages.append((0x10, 0x20, [
            0x08, 0x01, 0x10, nextMsgID(), 0x1A, 0x02, 0x08, 0x04
        ]))
        messages.append((0x09, 0x20, [
            0x08, 0x02, 0x10, nextMsgID(), 0x22, 0x02, 0x08, 0x01
        ]))
        messages.append((0x01, 0x20, [
            0x08, 0x02, 0x10, nextMsgID(),
            0x22, 0x17, 0x12, 0x15, 0x08, 0x04, 0x10, 0x03,
            0x1A, 0x03, 0x01, 0x02, 0x03, 0x20, 0x04,
            0x2A, 0x04, 0x01, 0x03, 0x02, 0x02, 0x30, 0x00, 0x38, 0x01
        ]))
        messages.append((0x81, 0x20, [
            0x08, 0x01, 0x10, nextMsgID(), 0x1A, 0x00
        ]))
        messages.append((0x20, 0x20, [
            0x08, 0x00, 0x10, nextMsgID(), 0x1A, 0x02, 0x08, 0x00
        ]))
        messages.append((0x20, 0x20, [
            0x08, 0x01, 0x10, nextMsgID(), 0x22, 0x00
        ]))
        messages.append((0x04, 0x20, [
            0x08, 0x01, 0x10, nextMsgID(),
            0x1A, 0x08, 0x08, 0x01, 0x10, 0x01, 0x18, 0x05, 0x28, 0x01
        ]))

        for (index, item) in messages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.07)) { [weak self] in
                self?.send(serviceHi: item.0, serviceLo: item.1, payload: item.2)
            }
        }

        onLog?("DIRECT: init sent — waiting for real 5402 response before declaring READY")
    }

    private func ensureConversate() {
        guard isProtocolReady, !conversateStarted else { return }

        let config: [UInt8] = [0x08, 0x01, 0x10, 0x01, 0x18, 0x00, 0x20, 0x01, 0x28, 0x00]
        var field3: [UInt8] = [0x08, 0x01, 0x12]
        field3 += Self.varint(UInt64(config.count))
        field3 += config
        field3 += [0x20, 0x00]

        var payload: [UInt8] = [0x08, 0x01, 0x10, nextMsgID(), 0x1A]
        payload += Self.varint(UInt64(field3.count))
        payload += field3
        send(serviceHi: 0x0B, serviceLo: 0x20, payload: payload)
        conversateStarted = true
        onLog?("DIRECT: Conversate session START")
    }

    private func enableMicPath() {
        // 6402 is a display/rendering WRITE characteristic, not a microphone stream.
        // Keep this explicit until the real G2 audio transport is captured.
        onLog?("DIRECT MIC: not implemented yet — 6402 is DISPLAY, not microphone")
    }

    private func disableMicPath() {
        onLog?("DIRECT MIC: OFF")
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeats()
        }
        sendHeartbeats()
    }

    private func sendHeartbeats() {
        guard isProtocolReady else { return }

        let hubID = nextMsgID()
        send(to: .right,
             serviceHi: 0xE0,
             serviceLo: 0x20,
             payload: [0x08,0x0C,0x10,hubID,0x72,0x00])

        let syncID = nextMsgID()
        send(to: .left,
             serviceHi: 0x80,
             serviceLo: 0x00,
             payload: [0x08,0x0E,0x10,syncID,0x6A,0x00])
        onLog?("DIRECT: heartbeat R=e0-20 L=80-00")
    }

    private func send(serviceHi: UInt8, serviceLo: UInt8, payload: [UInt8]) {
        send(to: .right, serviceHi: serviceHi, serviceLo: serviceLo, payload: payload)
    }

    private func send(to side: Side, serviceHi: UInt8, serviceLo: UInt8, payload: [UInt8]) {
        guard let target = lens(side), let write = target.commandWrite else {
            onLog?("DIRECT TX: \(side.rawValue) command channel unavailable")
            return
        }
        let packet = Self.packet(
            seq: nextTransportSeq(),
            serviceHi: serviceHi,
            serviceLo: serviceLo,
            payload: Data(payload)
        )
        target.peripheral.writeValue(packet, for: write, type: .withoutResponse)
    }

    private func nextTransportSeq() -> UInt8 {
        let value = transportSeq
        transportSeq &+= 1
        return value
    }

    private func nextMsgID() -> UInt8 {
        let value = msgID
        msgID &+= 1
        return value
    }

    private func authPackets() -> [Data] {
        let ts = UInt64(Date().timeIntervalSince1970)
        let tzQuarterHours = Int64(TimeZone.current.secondsFromGMT() / 900)

        func p(_ seq: UInt8, _ hi: UInt8, _ lo: UInt8, _ payload: [UInt8]) -> Data {
            Self.packet(seq: seq, serviceHi: hi, serviceLo: lo, payload: Data(payload))
        }

        let time15 = timeSyncPayload(msgID: 0x0F, timestamp: ts, timezoneQuarterHours: tzQuarterHours)
        let time19 = timeSyncPayload(msgID: 0x13, timestamp: ts, timezoneQuarterHours: tzQuarterHours)

        return [
            p(0x01, 0x80, 0x00, [0x08,0x04,0x10,0x0C,0x1A,0x04,0x08,0x01,0x10,0x04]),
            p(0x02, 0x80, 0x20, [0x08,0x05,0x10,0x0E,0x22,0x02,0x08,0x02]),
            p(0x03, 0x80, 0x20, time15),
            p(0x04, 0x80, 0x00, [0x08,0x04,0x10,0x10,0x1A,0x04,0x08,0x01,0x10,0x04]),
            p(0x05, 0x80, 0x00, [0x08,0x04,0x10,0x11,0x1A,0x04,0x08,0x01,0x10,0x04]),
            p(0x06, 0x80, 0x20, [0x08,0x05,0x10,0x12,0x22,0x02,0x08,0x01]),
            p(0x07, 0x80, 0x20, time19)
        ]
    }

    private func timeSyncPayload(
        msgID: UInt8,
        timestamp: UInt64 = UInt64(Date().timeIntervalSince1970),
        timezoneQuarterHours: Int64 = Int64(TimeZone.current.secondsFromGMT() / 900)
    ) -> [UInt8] {
        let ts = Self.varint(timestamp)
        let tz = Self.varint(UInt64(bitPattern: timezoneQuarterHours))
        var nested: [UInt8] = [0x08]
        nested += ts
        nested += [0x10]
        nested += tz

        var payload: [UInt8] = [0x08, 0x80, 0x01, 0x10, msgID, 0x82, 0x08]
        payload += Self.varint(UInt64(nested.count))
        payload += nested
        return payload
    }

    private static func packet(
        seq: UInt8,
        serviceHi: UInt8,
        serviceLo: UInt8,
        payload: Data
    ) -> Data {
        guard payload.count <= 253 else { return Data() }
        var out = Data([
            0xAA, 0x21, seq, UInt8(payload.count + 2),
            0x01, 0x01, serviceHi, serviceLo
        ])
        out.append(payload)
        let crc = crc16(payload)
        out.append(UInt8(crc & 0xFF))
        out.append(UInt8((crc >> 8) & 0xFF))
        return out
    }

    private static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : (crc << 1)
            }
        }
        return crc
    }

    private static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private static func hex(_ string: String) -> [UInt8] {
        let clean = string.filter { !$0.isWhitespace }
        var out: [UInt8] = []
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            out.append(UInt8(clean[i..<j], radix: 16) ?? 0)
            i = j
        }
        return out
    }

    private static func wrap(text: String, width: Int, maxLines: Int) -> [String] {
        var result: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for word in rawLine.split(separator: " ") {
                let w = String(word)
                if !current.isEmpty && current.count + 1 + w.count > width {
                    result.append(current)
                    current = w
                } else {
                    current += current.isEmpty ? w : " " + w
                }
                if result.count >= maxLines { break }
            }
            if result.count >= maxLines { break }
            if !current.isEmpty { result.append(current) }
            else if rawLine.isEmpty { result.append("") }
        }
        return Array(result.prefix(maxLines))
    }

    private static func pageText(_ lines: [String]) -> String {
        var out = lines
        while out.count < 10 { out.append(" ") }
        return out.prefix(10).joined(separator: "\n") + " \n"
    }

    private static func blankPage() -> String {
        Array(repeating: " ", count: 10).joined(separator: "\n") + " \n"
    }
}

extension DirectG2Transport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onLog?("DIRECT: central state=\(central.state.rawValue)")
        if central.state == .poweredOn { scan() }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        guard let side = side(for: name) else { return }

        attach(peripheral, side: side)

        let hasL = lenses.values.contains { $0.side == .left }
        let hasR = lenses.values.contains { $0.side == .right }
        if hasL && hasR { central.stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let lens = lenses[peripheral.identifier] else { return }
        onLog?("DIRECT: BLE connected \(lens.side.rawValue)")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard let lens = lenses[peripheral.identifier] else { return }
        lens.commandReady = false
        lens.commandWrite = nil
        lens.commandNotify = nil
        lens.micNotify = nil
        publishReady()

        if lens.side == .left {
            protocolStarted = false
            isProtocolReady = false
            conversateStarted = false
            heartbeat?.invalidate()
            heartbeat = nil
        }

        onLog?("DIRECT: \(lens.side.rawValue) disconnected — reconnecting")
        central.connect(
            peripheral,
            options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true]
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        onLog?("DIRECT: connect failed \(error?.localizedDescription ?? "unknown")")
        central.connect(
            peripheral,
            options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true]
        )
    }
}

extension DirectG2Transport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            onLog?("DIRECT: service discovery error \(error.localizedDescription)")
            return
        }

        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            onLog?("DIRECT: characteristic error \(error.localizedDescription)")
            return
        }
        guard let lens = lenses[peripheral.identifier] else { return }

        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString.uppercased()
            if uuid.hasSuffix(Self.commandWriteSuffix) {
                lens.commandWrite = characteristic
                onLog?("DIRECT: \(lens.side.rawValue) found 5401")
            } else if uuid.hasSuffix(Self.commandNotifySuffix) {
                lens.commandNotify = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                onLog?("DIRECT: \(lens.side.rawValue) found 5402")
            } else if uuid.hasSuffix(Self.displayWriteSuffix) {
                onLog?("DIRECT: \(lens.side.rawValue) found 6402 DISPLAY")
            }
        }

        if lens.commandWrite != nil && lens.commandNotify != nil {
            lens.commandReady = true
            publishReady()
            tryStartProtocol()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let suffix = String(characteristic.uuid.uuidString.suffix(4)).uppercased()
        if let error {
            onLog?("DIRECT: notify \(suffix) failed \(error.localizedDescription)")
        } else {
            onLog?("DIRECT: notify \(suffix) = \(characteristic.isNotifying ? "ON" : "OFF")")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value,
              let lens = lenses[peripheral.identifier] else { return }

        let uuid = characteristic.uuid.uuidString.uppercased()
        if uuid.hasSuffix(Self.commandNotifySuffix) {
            onPacket?(lens.side, data)

            // Do not declare protocol readiness on a timer. A real response from
            // the RIGHT lens proves that the app-level handshake is alive.
            if lens.side == .right, protocolStarted, !isProtocolReady {
                isProtocolReady = true
                onLog?("DIRECT: VERIFIED 5402 response from RIGHT — protocol READY")
                startHeartbeat()
                onProtocolReady?()
                if wantsMic { enableMicPath() }
            }
        }
    }
}
