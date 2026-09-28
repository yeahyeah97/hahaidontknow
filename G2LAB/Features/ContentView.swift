import SwiftUI

struct ContentView: View {
    @EnvironmentObject var g2: G2Controller
    @EnvironmentObject var models: WhisperModelManager

    @State private var tab = 0
    @State private var showDiagnostics = false

    private let accent = Color(red: 0.62, green: 0.35, blue: 1.0)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.055, green: 0.035, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    connectionCard
                    tabPicker

                    if tab == 0 {
                        captionsCard
                    } else if tab == 1 {
                        modelsCard
                    } else {
                        glassesCard
                    }

                    diagnostics
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            models.refreshInstalled()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(accent.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: "eyeglasses")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("G2 ACCESS")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                Text("NATIVE G2 + OFFLINE WHISPER  •  v0.5.1")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(g2.linkReady ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EVEN REALITIES G2")
                        .font(.headline)
                    Text(g2.status)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(g2.linkReady ? .green : .secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    lensDot("L", ready: g2.leftReady)
                    lensDot("R", ready: g2.rightReady)
                }
            }

            HStack(spacing: 10) {
                Button {
                    g2.connect()
                } label: {
                    Label(g2.linkReady ? "Reconnect" : "Connect G2", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)

                Button {
                    g2.disconnect()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 34)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(card)
    }

    private var tabPicker: some View {
        Picker("Section", selection: $tab) {
            Text("CAPTIONS").tag(0)
            Text("MODELS").tag(1)
            Text("GLASSES").tag(2)
        }
        .pickerStyle(.segmented)
    }

    private var captionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("LIVE CAPTIONS", systemImage: "captions.bubble.fill")
                    .font(.headline)
                Spacer()
                Text(models.ready ? "OFFLINE READY" : models.modelState)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(models.ready ? .green : .secondary)
            }

            HStack(spacing: 10) {
                metric("MODEL", shortModel)
                metric("LANG", models.selectedLanguageName)
                metric("LEVEL", String(format: "%.3f", g2.micLevel))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("TRANSCRIPT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(g2.captionText.isEmpty ? "Download a model, connect G2, then start captions." : g2.captionText)
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(g2.captionText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))

            Picker("Language", selection: Binding(
                get: { models.selectedLanguageCode },
                set: { models.selectLanguage($0) }
            )) {
                ForEach(models.languages) { language in
                    Text(language.title).tag(language.id)
                }
            }
            .pickerStyle(.menu)

            Button {
                Task { await g2.toggleCaptions() }
            } label: {
                Label(
                    g2.captionsEnabled ? "Stop Live Captions" : "Start Live Captions",
                    systemImage: g2.captionsEnabled ? "stop.fill" : "waveform.and.mic"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(g2.captionsEnabled ? .red : accent)
            .disabled(!g2.linkReady || (!models.selectedModelInstalled && !g2.captionsEnabled))

            if !models.selectedModelInstalled {
                Button {
                    tab = 1
                } label: {
                    Label("Download an offline model", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Text("PCM \(g2.pcmActive ? "LIVE" : "—")")
                Spacer()
                Text(String(format: "%.0f ms inference", models.inferenceMs))
                Spacer()
                Text(String(format: "%.1fs buffer", models.bufferedSeconds))
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(card)
    }

    private var modelsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("OFFLINE MODEL LIBRARY", systemImage: "square.stack.3d.up.fill")
                .font(.headline)

            Text("Models download once to this iPhone. After installation, speech recognition runs locally without an internet connection. Language is selected separately because these Whisper packages are multilingual.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(models.models) { model in
                modelRow(model)
            }

            if let error = models.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .background(card)
    }

    private func modelRow(_ model: WhisperModelManager.ModelOption) -> some View {
        let installed = models.isInstalled(model.id)
        let selected = models.selectedModelID == model.id
        let downloading = models.activeDownloadID == model.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(model.title)
                            .font(.subheadline.weight(.bold))
                        if selected {
                            Text("SELECTED")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(accent.opacity(0.25), in: Capsule())
                        }
                    }
                    Text("\(model.subtitle) • ~\(model.approxMB) MB")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if installed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if downloading {
                ProgressView(value: models.downloadProgress)
                Text("\(Int(models.downloadProgress * 100))%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if installed {
                    Button(selected ? "Selected" : "Use") {
                        models.selectModel(model.id)
                        Task { await models.loadSelectedModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selected ? .green : accent)
                    .disabled(selected && models.ready)

                    Button(role: .destructive) {
                        models.delete(model)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(models.activeDownloadID != nil || g2.captionsEnabled)
                } else {
                    Button {
                        models.selectModel(model.id)
                        models.download(model)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(models.activeDownloadID != nil)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private var glassesCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("G2 NATIVE MENU", systemImage: "list.bullet.rectangle.fill")
                .font(.headline)

            Text("This build uses the G2 firmware's native list container with event capture. Scroll changes the highlighted row on the glasses; tap returns the selected row to the iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                g2.openMenu()
            } label: {
                Label("Open G2 Menu", systemImage: "square.grid.2x2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(!g2.linkReady)

            HStack(spacing: 10) {
                Button {
                    g2.hudTest()
                } label: {
                    Label("HUD Test", systemImage: "text.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    g2.clearHUD()
                } label: {
                    Label("Clear", systemImage: "rectangle.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Text("LAST INPUT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(g2.lastInput)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(accent)
            }
        }
        .padding(18)
        .background(card)
    }

    private var diagnostics: some View {
        DisclosureGroup(isExpanded: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    Text("LINK: \(g2.status)")
                    Text("AUDIO: \(g2.validAudioPackets)/\(g2.micPackets) valid • bad \(g2.invalidAudioPackets)")
                    Text("PCM: \(g2.pcmActive ? "ACTIVE" : "OFF") • LEVEL \(String(format: "%.4f", g2.micLevel))")
                    Text("WHISPER: \(models.modelState)")
                    Text("MODEL: \(models.selectedModelID)")
                    Text("LANG: \(models.selectedLanguageCode)")
                    Text("BUFFER: \(String(format: "%.2fs", models.bufferedSeconds))")
                    Text("INFERENCE: \(String(format: "%.0fms", models.inferenceMs))")
                    Text("INPUT: \(g2.lastInput)")
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))

                Divider().padding(.vertical, 7)

                ForEach(Array(g2.logs.prefix(70).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
        } label: {
            Label("Diagnostics", systemImage: "terminal.fill")
                .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .background(card)
    }

    private var shortModel: String {
        switch models.selectedModelID {
        case "openai_whisper-tiny": return "TINY"
        case "openai_whisper-base": return "BASE"
        case "openai_whisper-small": return "SMALL"
        default: return "LARGE"
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.065))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            }
    }

    private func lensDot(_ label: String, ready: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ready ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.monospaced().weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospaced().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
