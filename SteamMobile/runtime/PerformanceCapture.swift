// SPDX-License-Identifier: GPL-3.0-or-later
// Appended to Library.swift by patch_ui.py, so this uses its existing imports.
// Samples native counters off the render thread; no per-frame claims are made.
@MainActor private final class SteamMobilePerformanceCapture: ObservableObject {
    static let shared = SteamMobilePerformanceCapture()

    struct Sample: Codable {
        let elapsedSeconds: Double
        let intervalSeconds: Double
        let presentCount: UInt64
        let presentDelta: UInt64?
        let presentsPerSecond: Double?
        let counterReset: Bool
        let delayedSample: Bool
        let appActive: Bool
        let physicalFootprintBytes: UInt64?
        let thermalState: Int
        let lowPowerMode: Bool
        let pacingMode: Int32
        let jitHelperReady: Bool
    }

    struct Report: Codable {
        let schema: Int
        let build: String
        let label: String
        let startedAt: Date
        let osVersion: String
        let requestedDurationSeconds: Double
        let durationSeconds: Double
        let termination: String
        let measurement: String
        let limitations: [String]
        let samples: [Sample]
    }

    @Published private(set) var recording = false
    @Published private(set) var elapsed = 0.0
    @Published private(set) var rate: Double?
    @Published private(set) var exportURL: URL?
    @Published private(set) var error: String?
    private var timer: Timer?
    private var samples: [Sample] = []
    private var startedAt = Date()
    private var started = 0.0
    private var lastTime = 0.0
    private var lastCount: UInt64 = 0
    private var requestedDuration = 120.0
    private var label = ""

    func start(label: String, duration: Double) {
        guard !recording, [120.0, 600.0, 1800.0].contains(duration) else { return }
        self.label = String(label.prefix(200))
        requestedDuration = duration
        samples = []
        samples.reserveCapacity(Int(duration) + 2)
        startedAt = Date()
        started = ProcessInfo.processInfo.systemUptime
        lastTime = started
        lastCount = madeira_get_present_count()
        elapsed = 0; rate = nil; error = nil; exportURL = nil
        recording = true
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        clock.tolerance = 0.1
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    private func sample() {
        guard recording else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let interval = now - lastTime
        guard interval > 0 else { return }
        let count = madeira_get_present_count()
        let delta: UInt64? = count >= lastCount ? count - lastCount : nil
        var info = task_vm_info_data_t()
        var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
            }
        }
        elapsed = now - started
        rate = delta.map { Double($0) / interval }
        let process = ProcessInfo.processInfo
        samples.append(Sample(elapsedSeconds: elapsed, intervalSeconds: interval,
            presentCount: count, presentDelta: delta, presentsPerSecond: rate,
            counterReset: delta == nil, delayedSample: interval > 2.5,
            appActive: UIApplication.shared.applicationState == .active,
            physicalFootprintBytes: status == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil,
            thermalState: process.thermalState.rawValue, lowPowerMode: process.isLowPowerModeEnabled,
            pacingMode: madeira_get_vsync_locked(), jitHelperReady: StikJITHelper.ready))
        lastCount = count; lastTime = now
        if elapsed >= requestedDuration { finish(reason: "duration-reached") }
    }

    func stop() {
        guard recording else { return }
        sample()
        if recording { finish(reason: "user-stopped") }
    }

    private func finish(reason: String) {
        timer?.invalidate(); timer = nil; recording = false
        let report = Report(schema: 1,
            build: Bundle.main.object(forInfoDictionaryKey: "SteamMobileSourceCommit") as? String ?? "unrecorded",
            label: label, startedAt: startedAt, osVersion: UIDevice.current.systemVersion,
            requestedDurationSeconds: requestedDuration, durationSeconds: elapsed, termination: reason,
            measurement: "DXMT aggregate present counter sampled at approximately 1 Hz",
            limitations: [
                "Counts include RAW skipped presents; these are not displayed frames.",
                "Intervals include startup, menus, pauses and all swapchains using this counter.",
                "No per-frame timing, 1% lows, GPU utilization or FEX cache statistics are inferred.",
                "Uninstrumented render paths may produce no samples; zero counts do not prove zero game FPS.",
                "jitHelperReady is the existing helper check, not an independent JIT execution test.",
                "Long or background sampling intervals are flagged; timer scheduling is not a frame clock.",
                "Game, scene, resolution and translation route in the label are user-provided."
            ], samples: samples)
        do {
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
                .appendingPathComponent("PerformanceReports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = directory.appendingPathComponent("SteamMobile-\(UUID().uuidString).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: output, options: .atomic)
            exportURL = output
        } catch { self.error = "Could not save capture: " + error.localizedDescription }
    }
}

private struct SteamMobileCaptureCard: View {
    @ObservedObject private var capture = SteamMobilePerformanceCapture.shared
    @State private var label = ""
    @State private var duration = 120.0
    var body: some View {
        SteamMobileCard {
            Label("Benchmark capture", systemImage: "waveform.path")
                .font(.headline).foregroundStyle(.white)
            TextField("Game, scene, resolution and renderer", text: $label)
                .textFieldStyle(.roundedBorder).disabled(capture.recording)
            Picker("Duration", selection: $duration) {
                Text("2 minutes").tag(120.0)
                Text("10 minutes").tag(600.0)
                Text("30 minutes").tag(1800.0)
            }.disabled(capture.recording).tint(.cyan)
            if capture.recording {
                Text("Recording: \(Int(capture.elapsed)) seconds")
                    .foregroundStyle(.white)
                if let rate = capture.rate {
                    Text(String(format: "%.1f presents/s in the latest sample", rate))
                        .font(.footnote).foregroundStyle(.cyan)
                }
                Button("Stop and save") { capture.stop() }.buttonStyle(.bordered)
            } else {
                Button("Start capture") { capture.start(label: label, duration: duration) }
                    .buttonStyle(.borderedProminent)
            }
            if let url = capture.exportURL {
                ShareLink(item: url) { Label("Export measurement JSON", systemImage: "square.and.arrow.up") }
            }
            if let error = capture.error { Text(error).foregroundStyle(.orange).font(.footnote) }
            Text("Capture continues while you play in this app. Exports present throughput, physical memory, thermal state and pacing changes. RAW includes skipped presents. Frame times and 1% lows are unavailable in this capture.")
                .font(.caption).foregroundStyle(.white.opacity(0.75))
        }
    }
}
