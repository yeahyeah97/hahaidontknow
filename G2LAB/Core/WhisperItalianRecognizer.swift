import Foundation
import whisper

@MainActor
final class WhisperItalianRecognizer: ObservableObject {
    @Published private(set) var status = "WHISPER • LOADING"
    @Published private(set) var isRunning = false
    @Published private(set) var modelReady = false
    @Published private(set) var lastInferenceMs: Double = 0

    var onText: ((String, Bool) -> Void)?

    private var context: OpaquePointer?
    private var samples: [Float] = []
    private var lastInferenceAt = Date.distantPast
    private var inferenceRunning = false

    private let inferenceQueue = DispatchQueue(label: "com.g2lab.whisper", qos: .userInitiated)
    private let sampleRate = 16_000
    private let minSamples = 12_800          // 0.8 s
    private let maxSamples = 64_000          // 4.0 s rolling window
    private let inferenceInterval = 0.45     // aggressive partial updates

    init() {
        loadModel()
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func start() {
        guard modelReady else {
            status = "WHISPER MODEL NOT READY"
            return
        }
        isRunning = true
        status = "WHISPER ITALIAN • LIVE"
    }

    func stop() {
        isRunning = false
        status = modelReady ? "WHISPER ITALIAN • READY" : "WHISPER MODEL ERROR"
    }

    func resetSession() {
        samples.removeAll(keepingCapacity: true)
        lastInferenceAt = .distantPast
    }

    func appendPCM16(_ data: Data) {
        guard isRunning, modelReady, data.count >= 2 else { return }

        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 0
            while i + 1 < bytes.count {
                let u = UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
                let s = Int16(bitPattern: u)
                samples.append(Float(s) / 32768.0)
                i += 2
            }
        }

        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        let now = Date()
        guard samples.count >= minSamples,
              !inferenceRunning,
              now.timeIntervalSince(lastInferenceAt) >= inferenceInterval,
              let context else { return }

        lastInferenceAt = now
        inferenceRunning = true

        let snapshot = samples
        let started = CFAbsoluteTimeGetCurrent()

        inferenceQueue.async { [weak self] in
            guard let self else { return }

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.n_threads = 4
            params.translate = false
            params.no_context = true
            params.no_timestamps = true
            params.single_segment = true
            params.print_special = false
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = false
            params.suppress_blank = true
            params.suppress_non_speech_tokens = true
            params.temperature = 0.0
            params.max_tokens = 64

            var resultText = ""
            let rc: Int32 = "it".withCString { language in
                params.language = language
                return snapshot.withUnsafeBufferPointer { buffer in
                    whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
                }
            }

            if rc == 0 {
                let count = whisper_full_n_segments(context)
                if count > 0 {
                    for i in 0..<count {
                        if let c = whisper_full_get_segment_text(context, i) {
                            resultText += String(cString: c)
                        }
                    }
                }
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000.0
            let cleaned = resultText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "  ", with: " ")

            DispatchQueue.main.async {
                self.inferenceRunning = false
                self.lastInferenceMs = elapsed

                if rc != 0 {
                    self.status = "WHISPER ERROR \(rc)"
                    return
                }

                self.status = String(format: "WHISPER ITALIAN • %.0f ms", elapsed)
                if !cleaned.isEmpty {
                    self.onText?(cleaned, false)
                }
            }
        }
    }

    private func loadModel() {
        let direct = Bundle.main.path(forResource: "ggml-model-q5_0", ofType: "bin")
        let nested = Bundle.main.path(forResource: "ggml-model-q5_0", ofType: "bin", inDirectory: "Models")

        guard let path = direct ?? nested else {
            status = "WHISPER MODEL MISSING"
            return
        }

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            let ctx = whisper_init_from_file(path)
            DispatchQueue.main.async {
                self.context = ctx
                self.modelReady = ctx != nil
                self.status = ctx == nil ? "WHISPER MODEL LOAD FAILED" : "WHISPER ITALIAN • READY"
            }
        }
    }
}
