import Foundation
import Speech
import AVFoundation

@MainActor
final class OfflineItalianRecognizer: ObservableObject {
    @Published private(set) var status = "OFF"
    @Published private(set) var text = ""
    @Published private(set) var isRunning = false
    @Published private(set) var onDeviceAvailable = false

    var onText: ((String, Bool) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init() {
        onDeviceAvailable = recognizer?.supportsOnDeviceRecognition ?? false
        status = onDeviceAvailable ? "ITALIAN ON-DEVICE READY" : "ITALIAN ON-DEVICE UNAVAILABLE"
    }

    func start() {
        guard !isRunning else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self else { return }
                guard auth == .authorized else {
                    self.status = "SPEECH PERMISSION DENIED"
                    return
                }
                guard let recognizer = self.recognizer,
                      recognizer.isAvailable,
                      recognizer.supportsOnDeviceRecognition else {
                    self.status = "ITALIAN OFFLINE PACK UNAVAILABLE"
                    self.onDeviceAvailable = false
                    return
                }

                self.stopInternal()

                let req = SFSpeechAudioBufferRecognitionRequest()
                req.shouldReportPartialResults = true
                req.requiresOnDeviceRecognition = true
                req.taskHint = .dictation

                self.request = req
                self.isRunning = true
                self.onDeviceAvailable = true
                self.status = "ITALIAN OFFLINE • LISTENING"

                self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                    DispatchQueue.main.async {
                        guard let self else { return }

                        if let result {
                            let next = result.bestTranscription.formattedString
                            self.text = next
                            self.onText?(next, result.isFinal)
                        }

                        if let error {
                            self.status = "ASR ERROR: \(error.localizedDescription)"
                            self.stopInternal()
                        } else if result?.isFinal == true {
                            self.restartAfterFinal()
                        }
                    }
                }
            }
        }
    }

    func stop() {
        stopInternal()
        status = onDeviceAvailable ? "ITALIAN ON-DEVICE READY" : "ITALIAN ON-DEVICE UNAVAILABLE"
    }

    func appendPCM16(_ data: Data, sampleRate: Double = 16_000) {
        guard isRunning, let request else { return }
        guard data.count >= 2 else { return }

        let frameCount = AVAudioFrameCount(data.count / 2)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
        let channel = buffer.int16ChannelData?[0] else { return }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            memcpy(channel, base, data.count)
        }
        request.append(buffer)
    }

    private func restartAfterFinal() {
        guard isRunning else { return }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRunning = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.start()
        }
    }

    private func stopInternal() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRunning = false
    }
}
