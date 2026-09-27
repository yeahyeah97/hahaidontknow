import Foundation
#if canImport(SherpaOnnx)
import SherpaOnnx
#elseif canImport(SherpaOnnxShared)
import SherpaOnnxShared
#endif

private final class KrokoASRWorker {
    var recognizer: SherpaOnnxRecognizer?

    func load(encoder: String, decoder: String, joiner: String, tokens: String) {
        let transducer = sherpaOnnxOnlineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner
        )

        let model = sherpaOnnxOnlineModelConfig(
            tokens: tokens,
            transducer: transducer,
            numThreads: 2,
            provider: "cpu",
            debug: 0,
            modelType: "zipformer2"
        )

        let features = sherpaOnnxFeatureConfig(
            sampleRate: 16_000,
            featureDim: 80
        )

        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: features,
            modelConfig: model,
            enableEndpoint: true,
            rule1MinTrailingSilence: 0.8,
            rule2MinTrailingSilence: 0.45,
            rule3MinUtteranceLength: 15,
            decodingMethod: "greedy_search",
            maxActivePaths: 4
        )

        recognizer = SherpaOnnxRecognizer(config: &config)
    }

    func process(_ samples: [Float]) -> (text: String, endpoint: Bool, decodeMs: Double)? {
        guard let recognizer else { return nil }

        let started = CFAbsoluteTimeGetCurrent()
        recognizer.acceptWaveform(samples: samples, sampleRate: 16_000)

        var decodePasses = 0
        while recognizer.isReady() && decodePasses < 16 {
            recognizer.decode()
            decodePasses += 1
        }

        let text = recognizer.getResult().text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let endpoint = recognizer.isEndpoint()
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000.0
        return (text, endpoint, elapsed)
    }

    func reset() {
        recognizer?.reset()
    }
}

@MainActor
final class StreamingItalianRecognizer: ObservableObject {
    @Published private(set) var status = "KROKO IT • LOADING"
    @Published private(set) var isRunning = false
    @Published private(set) var modelReady = false
    @Published private(set) var lastInferenceMs: Double = 0

    var onText: ((String, Bool) -> Void)?

    private let queue = DispatchQueue(label: "com.g2lab.kroko.streaming", qos: .userInitiated)
    private let worker = KrokoASRWorker()
    private var lastEmittedText = ""
    private var loadStarted = false

    init() {
        status = "KROKO IT • IDLE"
    }

    func start() {
        isRunning = true

        if modelReady {
            status = "KROKO IT • STREAMING"
            return
        }

        status = "KROKO IT • LOADING"
        if !loadStarted {
            loadStarted = true
            loadModel()
        }
    }

    func stop() {
        isRunning = false
        status = modelReady ? "KROKO IT • READY" : "KROKO IT • MODEL ERROR"
    }

    func resetSession() {
        lastEmittedText = ""
        queue.async { [worker] in
            worker.reset()
        }
    }

    func appendPCM16(_ data: Data) {
        guard isRunning, modelReady, data.count >= 2 else { return }

        var samples = [Float]()
        samples.reserveCapacity(data.count / 2)

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

        queue.async { [weak self, worker] in
            guard let result = worker.process(samples) else { return }

            DispatchQueue.main.async {
                guard let self else { return }
                self.lastInferenceMs = result.decodeMs
                self.status = String(format: "KROKO IT • %.0f ms", result.decodeMs)

                if result.endpoint {
                    if !result.text.isEmpty {
                        self.onText?(result.text, true)
                    }
                    self.lastEmittedText = ""
                    self.queue.async { [worker] in
                        worker.reset()
                    }
                } else if !result.text.isEmpty, result.text != self.lastEmittedText {
                    self.lastEmittedText = result.text
                    self.onText?(result.text, false)
                }
            }
        }
    }

    private func loadModel() {
        func modelPath(_ name: String, _ ext: String) -> String? {
            Bundle.main.path(
                forResource: name,
                ofType: ext,
                inDirectory: "Models/KrokoIT"
            ) ?? Bundle.main.path(forResource: name, ofType: ext)
        }

        guard
            let encoder = modelPath("it_encoder", "onnx"),
            let decoder = modelPath("it_decoder", "onnx"),
            let joiner = modelPath("it_joiner", "onnx"),
            let tokens = modelPath("it_tokens", "txt")
        else {
            status = "KROKO IT • MODEL FILES MISSING"
            return
        }

        status = "KROKO IT • INITIALIZING"

        queue.async { [weak self, worker] in
            worker.load(
                encoder: encoder,
                decoder: decoder,
                joiner: joiner,
                tokens: tokens
            )

            DispatchQueue.main.async {
                guard let self else { return }
                self.modelReady = worker.recognizer != nil
                if self.modelReady {
                    self.status = self.isRunning ? "KROKO IT • STREAMING" : "KROKO IT • READY"
                } else {
                    self.status = "KROKO IT • LOAD FAILED"
                }
            }
        }
    }
}
