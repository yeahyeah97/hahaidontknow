import Foundation

/// Session-owned decoder. All calls occur on the main queue with CoreBluetooth.
/// No encoded audio, PCM, or speech is logged or persisted.
final class G2LC3Decoder {
    private var handle: UnsafeMutableRawPointer
    private(set) var packets = 0
    private(set) var duplicates = 0
    private(set) var missing = 0
    private(set) var malformed = 0
    private(set) var decodedFrames = 0
    private(set) var sampleCount = 0
    private(set) var decodeErrors = 0
    private(set) var sequence: UInt8?
    private(set) var rms = 0.0

    init?() {
        guard let handle = g2_lc3_create() else { return nil }
        self.handle = handle
    }
    deinit { g2_lc3_destroy(handle) }

    func decode(_ packet: Data) -> Data? {
        guard packet.count == 205 else { malformed += 1; return nil }
        packets += 1
        let bytes = [UInt8](packet)
        let current = bytes[204]
        if let previous = sequence {
            let delta = Int(current &- previous)
            if delta == 0 { duplicates += 1; return nil }
            missing += delta - 1
        }
        sequence = current
        var pcm = [Int16](repeating: 0, count: 800)
        var succeeded = true
        bytes.withUnsafeBufferPointer { input in
            pcm.withUnsafeMutableBufferPointer { output in
                for frame in 0..<5 {
                    let result = g2_lc3_decode(handle, input.baseAddress! + frame * 40,
                                               40, output.baseAddress! + frame * 160, 160)
                    if result == 0 { decodedFrames += 1 }
                    else { decodeErrors += 1; succeeded = false }
                }
            }
        }
        // Concealed or invalid frames do not count as successful PCM evidence.
        guard succeeded else { return nil }
        sampleCount += pcm.count
        rms = sqrt(pcm.reduce(0.0) { total, sample in
            let normalized = Double(sample) / 32768.0
            return total + normalized * normalized
        } / Double(pcm.count))
        var data = Data(capacity: 1600)
        for sample in pcm {
            let bits = UInt16(bitPattern: sample)
            data.append(UInt8(truncatingIfNeeded: bits))
            data.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return data
    }
}
