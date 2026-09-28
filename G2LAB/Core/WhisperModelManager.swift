import Foundation
import CoreML
import WhisperKit

@MainActor
final class WhisperModelManager: ObservableObject {
    struct ModelOption: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let approxMB: Int
    }

    struct LanguageOption: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let models: [ModelOption] = [
        .init(id: "openai_whisper-tiny", title: "Whisper Tiny", subtitle: "Fastest • multilingual", approxMB: 77),
        .init(id: "openai_whisper-base", title: "Whisper Base", subtitle: "Balanced • multilingual", approxMB: 147),
        .init(id: "openai_whisper-small", title: "Whisper Small", subtitle: "Higher accuracy • multilingual", approxMB: 486),
        .init(id: "openai_whisper-large-v3-v20240930_626MB", title: "Whisper Large v3", subtitle: "Best quality • compressed multilingual", approxMB: 626)
    ]

    let languages: [LanguageOption] = [
        .init(id: "it", title: "Italiano"),
        .init(id: "en", title: "English"),
        .init(id: "es", title: "Español"),
        .init(id: "fr", title: "Français"),
        .init(id: "de", title: "Deutsch"),
        .init(id: "pt", title: "Português"),
        .init(id: "nl", title: "Nederlands"),
        .init(id: "pl", title: "Polski"),
        .init(id: "ja", title: "日本語"),
        .init(id: "ko", title: "한국어"),
        .init(id: "zh", title: "中文")
    ]

    @Published private(set) var installed = Set<String>()
    @Published var selectedModelID: String
    @Published var selectedLanguageCode: String
    @Published private(set) var activeDownloadID: String?
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var modelState = "NO MODEL"
    @Published private(set) var isLoading = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var liveText = ""
    @Published private(set) var inferenceMs: Double = 0
    @Published private(set) var bufferedSeconds: Double = 0
    @Published private(set) var lastError: String?

    var onTranscript: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    private var whisperKit: WhisperKit?
    private var audioBuffer: [Float] = []
    private var samplesSinceInference = 0
    private var sessionGeneration = 0
    private var inferenceTask: Task<Void, Never>?

    private let minimumInferenceSamples = 8_000
    private let maximumWindowSamples = 160_000

    init() {
        selectedModelID = UserDefaults.standard.string(forKey: "g2.whisper.model") ?? "openai_whisper-base"
        selectedLanguageCode = UserDefaults.standard.string(forKey: "g2.whisper.language") ?? "it"
        try? FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        refreshInstalled()
    }

    var selectedModel: ModelOption {
        models.first(where: { $0.id == selectedModelID }) ?? models[1]
    }

    var selectedLanguageName: String {
        languages.first(where: { $0.id == selectedLanguageCode })?.title ?? selectedLanguageCode
    }

    var selectedModelInstalled: Bool { installed.contains(selectedModelID) }
    var ready: Bool { whisperKit != nil && modelState == "READY" }

    func isInstalled(_ id: String) -> Bool { installed.contains(id) }

    func selectModel(_ id: String) {
        guard models.contains(where: { $0.id == id }) else { return }
        if selectedModelID != id {
            stopSession()
            whisperKit = nil
        }
        selectedModelID = id
        UserDefaults.standard.set(id, forKey: "g2.whisper.model")
        modelState = installed.contains(id) ? "INSTALLED" : "NOT INSTALLED"
        lastError = nil
    }

    func selectLanguage(_ code: String) {
        guard languages.contains(where: { $0.id == code }) else { return }
        selectedLanguageCode = code
        UserDefaults.standard.set(code, forKey: "g2.whisper.language")
        onLog?("WHISPER: language -> \(code)")
    }

    func refreshInstalled() {
        var found = Set<String>()
        for model in models where findModelFolder(model.id) != nil {
            found.insert(model.id)
        }
        installed = found
        if whisperKit == nil {
            modelState = found.contains(selectedModelID) ? "INSTALLED" : "NOT INSTALLED"
        }
    }

    func download(_ model: ModelOption) {
        guard activeDownloadID == nil else { return }
        activeDownloadID = model.id
        downloadProgress = 0
        lastError = nil
        modelState = "DOWNLOADING"
        onLog?("WHISPER: downloading \(model.id)")

        Task {
            do {
                _ = try await WhisperKit.download(
                    variant: model.id,
                    downloadBase: modelsRoot,
                    useBackgroundSession: false,
                    from: "argmaxinc/whisperkit-coreml",
                    progressCallback: { progress in
                    Task { @MainActor [weak self] in
                        guard self?.activeDownloadID == model.id else { return }
                        self?.downloadProgress = progress.fractionCompleted
                    }
                })
                refreshInstalled()
                activeDownloadID = nil
                downloadProgress = 1
                modelState = installed.contains(selectedModelID) ? "INSTALLED" : "NOT INSTALLED"
                onLog?("WHISPER: download complete \(model.id)")
                if model.id == selectedModelID {
                    await loadSelectedModel()
                }
            } catch {
                activeDownloadID = nil
                modelState = "DOWNLOAD FAILED"
                lastError = error.localizedDescription
                onLog?("WHISPER DOWNLOAD ERROR: \(error.localizedDescription)")
            }
        }
    }

    func delete(_ model: ModelOption) {
        guard activeDownloadID == nil else { return }
        if model.id == selectedModelID {
            stopSession()
            whisperKit = nil
        }
        if let folder = findModelFolder(model.id) {
            do {
                try FileManager.default.removeItem(at: folder)
                onLog?("WHISPER: deleted \(model.id)")
            } catch {
                lastError = error.localizedDescription
                onLog?("WHISPER DELETE ERROR: \(error.localizedDescription)")
            }
        }
        refreshInstalled()
    }

    func loadSelectedModel() async {
        guard !isLoading else { return }
        guard let folder = findModelFolder(selectedModelID) else {
            modelState = "NOT INSTALLED"
            lastError = "Download a model first."
            return
        }

        isLoading = true
        modelState = "LOADING"
        lastError = nil
        let started = CFAbsoluteTimeGetCurrent()
        do {
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                computeOptions: ModelComputeOptions(
                    melCompute: .cpuAndGPU,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            whisperKit = try await WhisperKit(config)
            modelState = "READY"
            onLog?("WHISPER: \(selectedModel.title) READY in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started))s")
        } catch {
            whisperKit = nil
            modelState = "LOAD FAILED"
            lastError = error.localizedDescription
            onLog?("WHISPER LOAD ERROR: \(error.localizedDescription)")
        }
        isLoading = false
    }

    func startSession() async -> Bool {
        if whisperKit == nil {
            await loadSelectedModel()
        }
        guard whisperKit != nil else { return false }
        sessionGeneration &+= 1
        inferenceTask?.cancel()
        inferenceTask = nil
        audioBuffer.removeAll(keepingCapacity: true)
        samplesSinceInference = 0
        bufferedSeconds = 0
        liveText = ""
        inferenceMs = 0
        isTranscribing = true
        onLog?("WHISPER: session START model=\(selectedModelID) lang=\(selectedLanguageCode)")
        return true
    }

    func stopSession() {
        sessionGeneration &+= 1
        inferenceTask?.cancel()
        inferenceTask = nil
        isTranscribing = false
        audioBuffer.removeAll(keepingCapacity: false)
        samplesSinceInference = 0
        bufferedSeconds = 0
        onLog?("WHISPER: session STOP")
    }

    func appendPCM16(_ data: Data) {
        guard isTranscribing, whisperKit != nil else { return }
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return }

        var samples = [Float]()
        samples.reserveCapacity(bytes.count / 2)
        var i = 0
        while i + 1 < bytes.count {
            let bits = UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
            let sample = Int16(bitPattern: bits)
            samples.append(Float(sample) / 32768.0)
            i += 2
        }

        audioBuffer.append(contentsOf: samples)
        if audioBuffer.count > maximumWindowSamples {
            audioBuffer.removeFirst(audioBuffer.count - maximumWindowSamples)
        }
        samplesSinceInference += samples.count
        bufferedSeconds = Double(audioBuffer.count) / 16_000.0
        scheduleInferenceIfNeeded()
    }

    private func scheduleInferenceIfNeeded() {
        guard inferenceTask == nil,
              samplesSinceInference >= minimumInferenceSamples,
              audioBuffer.count >= minimumInferenceSamples,
              let kit = whisperKit else { return }

        samplesSinceInference = 0
        let generation = sessionGeneration
        let snapshot = audioBuffer
        let language = selectedLanguageCode

        inferenceTask = Task { [weak self] in
            guard let self else { return }
            let started = CFAbsoluteTimeGetCurrent()
            do {
                let options = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: language,
                    temperature: 0,
                    temperatureFallbackCount: 2,
                    sampleLength: 224,
                    usePrefillPrompt: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: true
                )
                let results = try await kit.transcribe(
                    audioArray: snapshot,
                    decodeOptions: options,
                    callback: { progress in
                    let partial = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !partial.isEmpty {
                        Task { @MainActor [weak self] in
                            guard let self, self.sessionGeneration == generation, self.isTranscribing else { return }
                            self.publishTranscript(partial)
                        }
                    }
                    return nil
                })
                guard self.sessionGeneration == generation, self.isTranscribing else {
                    self.inferenceTask = nil
                    return
                }
                let final = results
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                self.inferenceMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
                if !final.isEmpty { self.publishTranscript(final) }
            } catch is CancellationError {
                // Session changed.
            } catch {
                guard self.sessionGeneration == generation else { return }
                self.lastError = error.localizedDescription
                self.onLog?("WHISPER ASR ERROR: \(error.localizedDescription)")
            }
            self.inferenceTask = nil
            if self.samplesSinceInference >= self.minimumInferenceSamples {
                self.scheduleInferenceIfNeeded()
            }
        }
    }

    private func publishTranscript(_ text: String) {
        let clean = text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != liveText else { return }
        liveText = clean
        onTranscript?(clean)
    }

    private var modelsRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("G2LAB/WhisperModels", isDirectory: true)
    }

    private func findModelFolder(_ id: String) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelsRoot.path),
              let enumerator = fm.enumerator(
                at: modelsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return nil }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == id else { continue }
            let config = url.appendingPathComponent("config.json")
            if fm.fileExists(atPath: config.path) {
                enumerator.skipDescendants()
                return url
            }
        }
        return nil
    }
}
