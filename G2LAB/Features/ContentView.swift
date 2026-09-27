import SwiftUI

struct ContentView: View {
    @EnvironmentObject var g2: G2Controller
    @StateObject private var permissions = PermissionCenter()
    @State private var showDiagnostics = false

    private let accent = Color(red: 0.55, green: 0.28, blue: 0.98)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.055, green: 0.05, blue: 0.085)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    deviceCard
                    captionCard
                    quickActions
                    permissionsCard
                    performanceCard
                    diagnostics
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            permissions.requestStartupPermissions()
            g2.startLink()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 52, height: 52)
                Image(systemName: "eyeglasses")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("G2 LAB")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                Text("ACCESSIBILITY ENGINE  •  v0.4.0 b7")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(g2.linkReady ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
        }
    }

    private var deviceCard: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("EVEN REALITIES G2")
                        .font(.headline)
                    Text(g2.status)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(g2.linkReady ? .green : .secondary)
                }

                Spacer()

                if let battery = g2.batteryLevel {
                    HStack(spacing: 6) {
                        Image(systemName: g2.batteryCharging ? "bolt.fill" : batterySymbol(battery))
                            .foregroundStyle(battery < 20 ? .red : .green)
                        Text("\(battery)%")
                            .font(.subheadline.monospaced().weight(.bold))
                    }
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.18), Color.white.opacity(0.035)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 155)

                Image(systemName: "eyeglasses")
                    .font(.system(size: 88, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.92), accent.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            if g2.linkReady {
                HStack(spacing: 10) {
                    statusPill(icon: "wave.3.right", title: "BLE", value: signalText)
                    statusPill(icon: "mic.fill", title: "MIC", value: g2.micActive ? "ACTIVE" : (g2.micEnabled ? "WAITING" : "OFF"))
                    statusPill(icon: "captions.bubble.fill", title: "ASR", value: g2.captionsEnabled ? "LIVE" : "OFF")
                }
            } else {
                VStack(spacing: 10) {
                    Button {
                        g2.scan()
                    } label: {
                        Label("Scan for G2", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    ForEach(Array(g2.devices.enumerated()), id: \.offset) { _, d in
                        Button {
                            g2.connect(d)
                        } label: {
                            HStack {
                                Image(systemName: "eyeglasses")
                                Text(d.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("LIVE CAPTIONS", systemImage: "captions.bubble.fill")
                    .font(.headline)
                Spacer()
                Text(g2.captionStatus)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("MIC \(g2.micActive ? "ACTIVE" : "—") • PCM \(g2.pcmActive ? "ACTIVE" : "—") • ASR \(g2.asrLive ? "LIVE" : "—")")
                .font(.caption2.monospaced())

            Text(g2.captionText.isEmpty ? "Parla in italiano… le caption appariranno qui e sul G2." : g2.captionText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(g2.captionText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)

            HStack(spacing: 10) {
                Button {
                    g2.toggleCaptions()
                } label: {
                    Label(
                        g2.captionsEnabled ? "Stop captions" : "Start captions",
                        systemImage: g2.captionsEnabled ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(g2.captionsEnabled ? .red : accent)

                Button {
                    g2.clearHUD()
                } label: {
                    Image(systemName: "rectangle.slash")
                        .frame(width: 34)
                }
                .buttonStyle(.bordered)
            }

            Text("Direct G2 display: 5401/5402 • right lens primary. G2 microphone transport is still being reverse-engineered; 6402 is display, not mic.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK CONTROLS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                quickButton("Mic", g2.micEnabled ? "mic.fill" : "mic.slash.fill") {
                    g2.toggleMic()
                }
                quickButton("G2 Menu", "square.grid.2x2") {
                    g2.openMenu()
                }
                quickButton("HUD Test", "text.viewfinder") {
                    g2.showProof()
                }
            }

            Text("This build only reports MENU OPEN after a verified direct G2 link and a real HUD write is queued. Direct gesture decoding is next.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("APP ACCESS", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Spacer()
                Button("Request again") {
                    permissions.requestStartupPermissions()
                }
                .font(.caption)
            }

            permissionRow("Bluetooth", value: "Requested when scanning", icon: "wave.3.right")
            permissionRow("Microphone", value: permissions.microphone, icon: "mic.fill")
            permissionRow("Speech fallback", value: permissions.speech, icon: "waveform")
            permissionRow("Notifications", value: permissions.notifications, icon: "bell.fill")
            permissionRow("Background BLE", value: "DECLARED", icon: "arrow.triangle.2.circlepath")

            Text("CoreBluetooth background-central is declared. iOS controls Background App Refresh separately; this build no longer claims the toggle is enabled when Settings does not expose it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("LINK & PERFORMANCE", systemImage: "gauge.with.dots.needle.67percent")
                .font(.headline)

            HStack {
                metric("LINK", g2.linkReady ? "VERIFIED" : "OFF")
                metric("LEVEL", String(format: "%.3f", g2.micLevel))
                metric("HUD", g2.linkReady ? "READY" : "OFF")
            }

            Text("Battery/latency mode: coalesced HUD writes, one PCM stream, ASR only while captions are enabled, reconnect backoff enabled.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var diagnostics: some View {
        DisclosureGroup(isExpanded: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(g2.logs.prefix(50).enumerated()), id: \.offset) { _, line in
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
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.065))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
    }

    private var signalText: String {
        guard let dbm = g2.signalDbm else { return "—" }
        return "\(dbm)"
    }

    private func batterySymbol(_ level: Int) -> String {
        if level >= 90 { return "battery.100" }
        if level >= 60 { return "battery.75" }
        if level >= 35 { return "battery.50" }
        if level >= 15 { return "battery.25" }
        return "battery.0"
    }

    private func statusPill(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(accent)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced().weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func quickButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }

    private func permissionRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
