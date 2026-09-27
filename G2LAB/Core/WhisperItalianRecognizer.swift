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
            encoder: encoder, decoder: decoder, joiner: joiner
        )
        let model = sherpaOnnxOnlineModelConfig(
            tokens: tokens,
            transducer: transducer,
            numThreads: 2,
            provider: "cpu",
            debug: 0,
            modelType: "zipformer2"
        )
        let features = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
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

    func process(_ samples: [Float]) -> (text: String, endpoint: Bool, decodeMs: Double, decodePasses: Int)? {
        guard let recognizer else { return nil }
        let started = CFAbsoluteTimeGetCurrent()
        recognizer.acceptWaveform(samples: samples, sampleRate: 16_000)

        var passes = 0
        while recognizer.isReady() && passes < 32 {
            recognizer.decode()
            passes += 1
        }

        let text = recognizer.getResult().text.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = recognizer.isEndpoint()
        if endpoint { recognizer.reset() }
        return (text, endpoint, (CFAbsoluteTimeGetCurrent() - started) * 1000.0, passes)
    }

    func reset() { recognizer?.reset() }
}

@MainActor
final class StreamingItalianRecognizer: ObservableObject {
    @Published private(set) var status = "KROKO IT • IDLE"
    @Published private(set) var isRunning = false
    @Published private(set) var modelReady = false
    @Published private(set) var modelState = "IDLE"
    @Published private(set) var lastInferenceMs: Double = 0
    @Published private(set) var pcmBuffersIn = 0
    @Published private(set) var pcmSamplesIn = 0
    @Published private(set) var queuedChunks = 0
    @Published private(set) var processedChunks = 0
    @Published private(set) var droppedPackets = 0
    @Published private(set) var processCalls = 0
    @Published private(set) var partialCount = 0
    @Published private(set) var finalCount = 0
    @Published private(set) var inputRMS: Double = 0

    var onText: ((String, Bool) -> Void)?

    private let queue = DispatchQueue(label: "com.g2lab.kroko.streaming", qos: .userInitiated)
    private let worker = KrokoASRWorker()
    private var lastEmittedText = ""
    private var loadStarted = false
    private var generation = 0

    // 50 ms G2 packets arrive faster than inference can occasionally complete.
    // Keep a bounded FIFO and drain it serially instead of dropping normal speech.
    private var fifo: [[Float]] = []
    private var fifoSamples = 0
    private var draining = false
    private let targetChunkSamples = 1600       // 100 ms @ 16 kHz
    private let maxBufferedSamples = 32_000     // 2 seconds, bounded
    private var loadingPreroll: [[Float]] = []
    private var loadingPrerollSamples = 0
    private let maxPrerollSamples = 16_000      // 1 second while model loads

    init() {}

    func start() {
        isRunning = true
        if modelReady {
            modelState = "READY"
            status = "KROKO IT • STREAMING"
            drainIfNeeded()
            return
        }
        modelState = "LOADING"
        status = "KROKO IT • LOADING"
        if !loadStarted {
            loadStarted = true
            loadModel()
        }
    }

    func stop() {
        isRunning = false
        resetSession()
        status = modelReady ? "KROKO IT • READY" : "KROKO IT • MODEL ERROR"
    }

    func resetSession() {
        generation += 1
        lastEmittedText = ""
        fifo.removeAll(keepingCapacity: true)
        fifoSamples = 0
        loadingPreroll.removeAll(keepingCapacity: true)
        loadingPrerollSamples = 0
        draining = false
        queue.async { [worker] in worker.reset() }
    }

    func appendPCM16(_ data: Data) {
        guard isRunning, data.count >= 2 else { return }

        var samples = [Float]()
        samples.reserveCapacity(data.count / 2)
        var energy = 0.0
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 0
            while i + 1 < bytes.count {
                let u = UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
                let s = Int16(bitPattern: u)
                let f = Float(s) / 32768.0
                samples.append(f)
                energy += Double(f * f)
                i += 2
            }
        }
        guard !samples.isEmpty else { return }

        pcmBuffersIn += 1
        pcmSamplesIn += samples.count
        inputRMS = sqrt(energy / Double(samples.count))

        guard modelReady else {
            loadingPreroll.append(samples)
            loadingPrerollSamples += samples.count
            while loadingPrerollSamples > maxPrerollSamples, !loadingPreroll.isEmpty {
                loadingPrerollSamples -= loadingPreroll.removeFirst().count
                droppedPackets += 1
            }
            return
        }

        enqueue(samples)
        drainIfNeeded()
    }

    private func enqueue(_ samples: [Float]) {
        fifo.append(samples)
        fifoSamples += samples.count
        while fifoSamples > maxBufferedSamples, !fifo.isEmpty {
            fifoSamples -= fifo.removeFirst().count
            droppedPackets += 1
        }
        queuedChunks = fifo.count
    }

    private func drainIfNeeded() {
        guard isRunning, modelReady, !draining, fifoSamples >= targetChunkSamples else { return }

        var chunk = [Float]()
        chunk.reserveCapacity(targetChunkSamples)
        while chunk.count < targetChunkSamples, !fifo.isEmpty {
            var head = fifo.removeFirst()
            let needed = targetChunkSamples - chunk.count
            if head.count <= needed {
                chunk.append(contentsOf: head)
                fifoSamples -= head.count
            } else {
                chunk.append(contentsOf: head.prefix(needed))
                head.removeFirst(needed)
                fifo.insert(head, at: 0)
                fifoSamples -= needed
            }
        }
        queuedChunks = fifo.count
        guard !chunk.isEmpty else { return }

        draining = true
        let session = generation
        processCalls += 1

        queue.async { [weak self, worker] in
            let result = worker.process(chunk)
            DispatchQueue.main.async {
                guard let self else { return }
                self.draining = false
                guard self.isRunning, self.generation == session else { return }

                if let result {
                    self.processedChunks += 1
                    self.lastInferenceMs = result.decodeMs
                    self.status = String(format: "KROKO IT • %.0f ms", result.decodeMs)

                    if result.endpoint {
                        if !result.text.isEmpty {
                            self.finalCount += 1
                            self.onText?(result.text, true)
                        }
                        self.lastEmittedText = ""
                    } else if !result.text.isEmpty, result.text != self.lastEmittedText {
                        self.lastEmittedText = result.text
                        self.partialCount += 1
                        self.onText?(result.text, false)
                    }
                }
                self.drainIfNeeded()
            }
        }
    }

    private func loadModel() {
        func modelPath(_ name: String, _ ext: String) -> String? {
            Bundle.main.path(forResource: name, ofType: ext, inDirectory: "Models/KrokoIT")
                ?? Bundle.main.path(forResource: name, ofType: ext)
        }

        guard
            let encoder = modelPath("it_encoder", "onnx"),
            let decoder = modelPath("it_decoder", "onnx"),
            let joiner = modelPath("it_joiner", "onnx"),
            let tokens = modelPath("it_tokens", "txt")
        else {
            modelState = "ERROR"
            status = "KROKO IT • MODEL FILES MISSING"
            return
        }

        modelState = "LOADING"
        status = "KROKO IT • INITIALIZING"

        queue.async { [weak self, worker] in
            worker.load(encoder: encoder, decoder: decoder, joiner: joiner, tokens: tokens)
            DispatchQueue.main.async {
                guard let self else { return }
                self.modelReady = worker.recognizer != nil
                if self.modelReady {
                    self.modelState = "READY"
                    self.status = self.isRunning ? "KROKO IT • STREAMING" : "KROKO IT • READY"
                    if self.isRunning {
                        for block in self.loadingPreroll { self.enqueue(block) }
                        self.loadingPreroll.removeAll(keepingCapacity: true)
                        self.loadingPrerollSamples = 0
                        self.drainIfNeeded()
                    }
                } else {
                    self.modelState = "ERROR"
                    self.status = "KROKO IT • LOAD FAILED"
                }
            }
        }
    }
}
