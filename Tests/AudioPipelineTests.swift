import Foundation

@main enum AudioPipelineTests {
    static func main() {
        let decoder = G2LC3Decoder()!
        for count in [0, 40, 200, 204, 206] {
            precondition(decoder.decode(Data(repeating: 0, count: count)) == nil)
        }
        precondition(decoder.malformed == 5 && decoder.packets == 0)
        var bytes = [UInt8](repeating: 0, count: 205)
        precondition(make_test_packet(&bytes) == 0)
        bytes[204] = 255
        let pcm = decoder.decode(Data(bytes))!
        precondition(pcm.count == 1600)
        precondition(decoder.decodedFrames == 5 && decoder.sampleCount == 800)
        precondition(decoder.rms > 0.05 && decoder.rms < 0.5)
        var energy = 0.0
        for i in stride(from: 0, to: pcm.count, by: 2) {
            let sample = Int16(bitPattern: UInt16(pcm[i]) | UInt16(pcm[i + 1]) << 8)
            energy += pow(Double(sample) / 32768, 2)
        }
        precondition(abs(sqrt(energy / 800) - decoder.rms) < 0.000001)
        precondition(decoder.decode(Data(bytes)) == nil && decoder.duplicates == 1)
        bytes[204] = 0
        precondition(decoder.decode(Data(bytes)) != nil && decoder.missing == 0)
        bytes[204] = 3
        precondition(decoder.decode(Data(bytes)) != nil && decoder.missing == 2)
        let fresh = G2LC3Decoder()!
        precondition(fresh.decode(Data(bytes)) != nil && fresh.missing == 0)
        var output = [Int16](repeating: 0, count: 160)
        let handle = g2_lc3_create()!
        defer { g2_lc3_destroy(handle) }
        precondition(g2_lc3_decode(handle, &bytes, 39, &output, 160) == -1)
        precondition(g2_lc3_decode(handle, &bytes, 40, &output, 159) == -1)
        print("PASS: native LC3, PCM byte order/RMS, packet bounds, sequence wrap/gaps/duplicates, session reset")
    }
}
