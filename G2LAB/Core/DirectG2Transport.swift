import Foundation
import CoreBluetooth

/// Clean-room Even G2 transport based only on observable BLE behavior documented
/// by the community. It intentionally does not depend on MentraBluetoothSDK.
final class DirectG2Transport: NSObject {
    enum Side: String { case left = "L", right = "R" }

    struct Lens {
        let side: Side
        let peripheral: CBPeripheral
        var write: CBCharacteristic?
        var notify: CBCharacteristic?
        var ready = false
    }

    var onLog: ((String) -> Void)?
    var onReadyChanged: ((Bool, Bool) -> Void)?
    var onPacket: ((Side, Data) -> Void)?

    private static let restoreID = "com.g2lab.direct.central.v1"
    private static let serviceUUID = CBUUID(string: "00002760-08C2-11E1-9073-0E8AC72E0000")
    private static let writeUUID = CBUUID(string: "00002760-08C2-11E1-9073-0E8AC72E5401")
    private static let notifyUUID = CBUUID(string: "00002760-08C2-11E1-9073-0E8AC72E5402")

    private var central: CBCentralManager!
    private var lenses: [UUID: Lens] = [:]
    private var keepAlive: Timer?
    private var seq: UInt8 = 8
    private var msgID: UInt8 = 20

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(label: "g2lab.direct.ble"),
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    func start() {
        guard central.state == .poweredOn else {
            onLog?("DIRECT: waiting for Bluetooth")
            return
        }
        scan()
    }

    func stop() {
        keepAlive?.invalidate()
        keepAlive = nil
        central.stopScan()
        for lens in lenses.values { central.cancelPeripheralConnection(lens.peripheral) }
        lenses.removeAll()
        publishReady()
    }

    private func scan() {
        onLog?("DIRECT: scanning Even G2 L/R")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func side(for name: String) -> Side? {
        let u = name.uppercased()
        if u.contains("EVEN G2") || u.contains("G2") {
            if u.contains("_L_") || u.hasSuffix("_L") { return .left }
            if u.contains("_R_") || u.hasSuffix("_R") { return .right }
        }
        return nil
    }

    private func connect(_ p: CBPeripheral, side: Side) {
        guard lenses[p.identifier] == nil else { return }
        lenses[p.identifier] = Lens(side: side, peripheral: p)
        p.delegate = self
        onLog?("DIRECT: found \(side.rawValue) \(p.name ?? p.identifier.uuidString)")
        central.connect(p, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    private func authenticate(_ id: UUID) {
        guard let lens = lenses[id], let w = lens.write else { return }
        let packets = Self.authPackets(timestamp: UInt64(Date().timeIntervalSince1970))
        onLog?("DIRECT: auth \(lens.side.rawValue) 7-packet sequence")
        for (i, packet) in packets.enumerated() {
            let delay = Double(i) * 0.018
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak p = lens.peripheral] in
                guard let self, let p else { return }
                p.writeValue(packet, for: w, type: .withoutResponse)
                self.onLog?("DIRECT: auth \(lens.side.rawValue) \(i + 1)/7")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            guard let self, var l = self.lenses[id] else { return }
            l.ready = true
            self.lenses[id] = l
            self.onLog?("DIRECT: \(l.side.rawValue) transport READY")
            self.publishReady()
            self.ensureKeepAlive()
        }
    }

    private func ensureKeepAlive() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.keepAlive == nil else { return }
            self.keepAlive = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { [weak self] _ in
                self?.sendKeepAlive()
            }
        }
    }

    private func sendKeepAlive() {
        msgID &+= 1
        // Official-app capture: e0-20 type 12 keepalive, payload 08 0c 10 <msgId> 72 00.
        let payload = Data([0x08, 0x0c, 0x10, msgID, 0x72, 0x00])
        let packet = Self.packet(seq: seq, serviceHi: 0xe0, serviceLo: 0x20, payload: payload)
        seq &+= 1
        for lens in lenses.values where lens.ready {
            guard let w = lens.write else { continue }
            lens.peripheral.writeValue(packet, for: w, type: .withoutResponse)
        }
        onLog?("DIRECT: keepalive id=\(msgID)")
    }

    private func publishReady() {
        let left = lenses.values.contains { $0.side == .left && $0.ready }
        let right = lenses.values.contains { $0.side == .right && $0.ready }
        onReadyChanged?(left, right)
    }

    private static func crc16(_ bytes: Data) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : (crc << 1)
            }
        }
        return crc
    }

    private static func withCRC(_ raw: Data) -> Data {
        var out = raw
        let crc = crc16(Data(raw.dropFirst(8)))
        out.append(UInt8(crc & 0xff))
        out.append(UInt8((crc >> 8) & 0xff))
        return out
    }

    private static func packet(seq: UInt8, serviceHi: UInt8, serviceLo: UInt8, payload: Data) -> Data {
        var raw = Data([0xaa, 0x21, seq, UInt8(payload.count + 2), 0x01, 0x01, serviceHi, serviceLo])
        raw.append(payload)
        return withCRC(raw)
    }

    private static func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        repeat {
            var b = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    private static func authPackets(timestamp: UInt64) -> [Data] {
        let ts = varint(timestamp)
        let txid = Data([0xe8,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0x01])
        var result: [Data] = []

        func fixed(_ bytes: [UInt8]) { result.append(withCRC(Data(bytes))) }
        fixed([0xaa,0x21,0x01,0x0c,0x01,0x01,0x80,0x00, 0x08,0x04,0x10,0x0c,0x1a,0x04,0x08,0x01,0x10,0x04])
        fixed([0xaa,0x21,0x02,0x0a,0x01,0x01,0x80,0x20, 0x08,0x05,0x10,0x0e,0x22,0x02,0x08,0x02])

        var p3 = Data([0x08,0x80,0x01,0x10,0x0f,0x82,0x08,0x11,0x08])
        p3.append(ts); p3.append(0x10); p3.append(txid)
        result.append(packet(seq: 0x03, serviceHi: 0x80, serviceLo: 0x20, payload: p3))

        fixed([0xaa,0x21,0x04,0x0c,0x01,0x01,0x80,0x00, 0x08,0x04,0x10,0x10,0x1a,0x04,0x08,0x01,0x10,0x04])
        fixed([0xaa,0x21,0x05,0x0c,0x01,0x01,0x80,0x00, 0x08,0x04,0x10,0x11,0x1a,0x04,0x08,0x01,0x10,0x04])
        fixed([0xaa,0x21,0x06,0x0a,0x01,0x01,0x80,0x20, 0x08,0x05,0x10,0x12,0x22,0x02,0x08,0x01])

        var p7 = Data([0x08,0x80,0x01,0x10,0x13,0x82,0x08,0x11,0x08])
        p7.append(ts); p7.append(0x10); p7.append(txid)
        result.append(packet(seq: 0x07, serviceHi: 0x80, serviceLo: 0x20, payload: p7))
        return result
    }
}

extension DirectG2Transport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onLog?("DIRECT: central state=\(central.state.rawValue)")
        if central.state == .poweredOn { scan() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        onLog?("DIRECT: iOS restored \(restored.count) peripheral(s)")
        for p in restored {
            guard let name = p.name, let s = side(for: name) else { continue }
            lenses[p.identifier] = Lens(side: s, peripheral: p)
            p.delegate = self
            if p.state == .connected {
                p.discoverServices([Self.serviceUUID])
            } else {
                central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              let s = side(for: name) else { return }
        connect(peripheral, side: s)
        if lenses.values.contains(where: { $0.side == .left }) &&
           lenses.values.contains(where: { $0.side == .right }) { central.stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onLog?("DIRECT: connected \(lenses[peripheral.identifier]?.side.rawValue ?? "?")")
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard var l = lenses[peripheral.identifier] else { return }
        l.ready = false; l.write = nil; l.notify = nil
        lenses[peripheral.identifier] = l
        publishReady()
        onLog?("DIRECT: \(l.side.rawValue) disconnected; reconnecting")
        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onLog?("DIRECT: connect failed \(error?.localizedDescription ?? "unknown")")
        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }
}

extension DirectG2Transport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { onLog?("DIRECT: service error \(error!.localizedDescription)"); return }
        for s in peripheral.services ?? [] where s.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, var lens = lenses[peripheral.identifier] else { return }
        for c in service.characteristics ?? [] {
            if c.uuid == Self.writeUUID { lens.write = c }
            if c.uuid == Self.notifyUUID {
                lens.notify = c
                peripheral.setNotifyValue(true, for: c)
            }
        }
        lenses[peripheral.identifier] = lens
        if lens.write != nil && lens.notify != nil { authenticate(peripheral.identifier) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value,
              let side = lenses[peripheral.identifier]?.side else { return }
        onPacket?(side, data)
    }
}
