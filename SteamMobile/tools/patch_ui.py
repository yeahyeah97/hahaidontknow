#!/usr/bin/env python3
"""Apply Steam Mobile's native SwiftUI deck to the pinned Madeira Library.swift.

No fake achievements, downloaded third-party installers, or impossible FPS toggles:
all active controls delegate to existing Madeira code paths. Re-runnable fail-closed
and isolated from upstream until an actual native build passes.
"""
from pathlib import Path
import argparse

def once(src, old, new, description):
    if src.count(old) != 1:
        raise RuntimeError(f"{description}: expected 1 source anchor; found {src.count(old)}")
    return src.replace(old, new, 1)

UI_APPEND = r'''
// MARK: - Steam Mobile navigation. Actual functions route to Madeira's runtime.
// Isolated navigation/skin: no game shaders, Wine state or DXMT queue mutated.
private enum SteamMobilePalette {
    static let bg = Color(red: 0.018, green: 0.033, blue: 0.078)
    static let panel = Color(red: 0.035, green: 0.077, blue: 0.155)
    static let blue = Color(red: 0.07, green: 0.44, blue: 0.98)
    static let violet = Color(red: 0.56, green: 0.28, blue: 0.99)
}

private struct SteamMobileCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SteamMobilePalette.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(.blue.opacity(0.32), lineWidth: 1))
    }
}

struct SteamMobileSteamHomeStatus: View {
    @ObservedObject private var steam = SteamOwnedLibrary.shared
    @State private var signIn = false
    var body: some View {
        SteamMobileCard {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MY STEAM GAMES").font(.title3.bold()).foregroundStyle(.white)
                    Text(steam.signedIn
                         ? "\(steam.owned.count) owned Windows games • \(steam.downloads.count) downloads"
                         : "Connect Steam to see every game you own")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if steam.refreshing { ProgressView() }
            }
            HStack(spacing: 10) {
                if steam.signedIn {
                    Button("Sync library") {
                        Task { await steam.refreshLibrary(interactive: true) }
                    }.disabled(steam.refreshing)
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Label("Tap a game below to install", systemImage: "arrow.down.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Sign in to Steam") { signIn = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { steam.start() }
        .sheet(isPresented: $signIn) { SteamSignInView() }
    }
}

struct SteamMobileLibraryHero: View {
    let item: LibraryEntry?
    var open: (LibraryEntry) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: "gamecontroller.fill").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STEAM MOBILE").font(.headline.weight(.black))
                    Text("YOUR LIBRARY · ANYWHERE")
                        .font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "apple.logo").font(.title2)
            }
            .foregroundStyle(.white)
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            Text(item?.title ?? "Ready to play")
                .font(.title2.weight(.bold)).foregroundStyle(.white)
                .lineLimit(2)
            Text(item == nil
                 ? "Import your Windows game or sign in with Steam to build your library."
                 : "Continue your game with Steam Mobile's native DXMT, Wine and FEX runtime.")
                .font(.footnote).foregroundStyle(.white.opacity(0.78))
            if let item {
                Button { open(item) } label: {
                    Label("Open game details", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            HStack(spacing: 8) {
                Label("Wine", systemImage: "checkmark.circle")
                Label("DXMT", systemImage: "cpu")
                Label("FEX JIT", systemImage: "bolt")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.83))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [SteamMobilePalette.blue.opacity(0.72),
                                    SteamMobilePalette.panel,
                                    SteamMobilePalette.violet.opacity(0.34)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22)
            .stroke(SteamMobilePalette.blue.opacity(0.58), lineWidth: 1))
    }
}

struct SteamMobilePerformanceTab: View {
    var openJIT: () -> Void
    var openOptions: () -> Void
    @State private var pacing: Int32 = 2
    private let modes: [(String, Int32)] =
        [("30", 3), ("40", 4), ("60", 1), ("MAX", 0), ("RAW", 2)]
    private func apply(_ mode: Int32) {
        pacing = mode
        madeira_set_vsync_locked(mode)
        ProMotionIntent.apply(mode: mode)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("PERFORMANCE LAB", systemImage: "speedometer")
                        .font(.headline.weight(.black)).foregroundStyle(.cyan)
                    Text("REAL PERFORMANCE. NO FAKE FPS UNLOCKS.")
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                    Text("Capture present throughput and device conditions, then compare identical gameplay runs. RAW removes presentation pacing but cannot remove CPU/GPU bottlenecks.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                }.padding(.vertical, 8)
                SteamMobileCaptureCard()
                SteamMobileCard {
                    Text("Frame pacing").font(.headline).foregroundStyle(.white)
                    HStack(spacing: 6) {
                        ForEach(modes, id: \.1) { item in
                            Button(item.0) { apply(item.1) }
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 11).padding(.vertical, 12)
                                .foregroundStyle(pacing == item.1 ? .white : .gray)
                                .background(pacing == item.1 ? SteamMobilePalette.blue
                                            : SteamMobilePalette.bg, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text("RAW = uncapped emulator throughput. MAX = display-rate presentation. iPhone screen refresh does not increase with internal FPS.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.68))
                }
                SteamMobileCard {
                    Label("Engine components", systemImage: "waveform.path.ecg")
                        .font(.headline).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 9) {
                        Label("FEX JIT code translation", systemImage: "bolt.fill")
                        Label("DXMT / Metal translation", systemImage: "cube.transparent")
                        Label("Wine Windows API bridge", systemImage: "square.stack.3d.up")
                    }.font(.subheadline).foregroundStyle(.white.opacity(0.87))
                    Button("JIT pairing & diagnostics", action: openJIT)
                        .buttonStyle(.borderedProminent)
                    Button("Advanced engine and memory settings", action: openOptions)
                        .buttonStyle(.bordered)
                }
                SteamMobileCard {
                    Label("Performance limits", systemImage: "info.circle")
                        .font(.headline).foregroundStyle(.white)
                    Text("Borderlands 1 at ~30 FPS in RAW is a genuine runtime bottleneck. Optimization effects require repeatable iPhone benchmarks, stable device temperature and identical scene/resolution.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.76))
                }
            }
            .padding(16)
        }
        .background(SteamMobilePalette.bg.ignoresSafeArea())
        .onAppear { pacing = madeira_get_vsync_locked() }
    }
}

struct SteamMobileAchievementsTab: View {
    var openSteamLibrary: () -> Void
    @ObservedObject private var library = SteamOwnedLibrary.shared
    @State private var selectedAppID = 0
    @State private var achievements: [SteamMobileAchievement] = []
    @State private var inFlight = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var newlyConfirmed: [String] = []
    private var unlockedCount: Int { achievements.filter(\.unlocked).count }

    private func refresh() {
        guard selectedAppID > 0, !inFlight,
              let account = library.steamMobileAchievementAccountKey else { return }
        let appID = selectedAppID
        let token = UUID()
        requestID = token
        let baselineKey = "SteamMobileConfirmedAchievements.v1." + account + "." + String(appID)
        inFlight = true
        error = nil
        newlyConfirmed = []
        achievements = []
        Task { @MainActor in
            defer { if requestID == token { inFlight = false } }
            do {
                let serverAchievements = try await library.steamMobileAchievements(for: appID)
                guard requestID == token, selectedAppID == appID,
                      library.steamMobileAchievementAccountKey == account,
                      SteamSignIn.isSignedIn else { return }
                // First read seeds the baseline without noisy "unlock" popups
                // for trophies earned months ago. Later reads show only
                // additional achievements actually confirmed by Steam.
                let confirmed = Set(serverAchievements.filter(\.unlocked).map(\.id))
                if let saved = UserDefaults.standard.stringArray(forKey: baselineKey) {
                    let fresh = confirmed.subtracting(Set(saved))
                    newlyConfirmed = serverAchievements.filter { fresh.contains($0.id) }
                        .map(\.title)
                    if !newlyConfirmed.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
                // Persist server-confirmed notification history across restarts.
                // Union preserves deduplication through temporary server resets.
                let previous = Set(UserDefaults.standard.stringArray(forKey: baselineKey) ?? [])
                UserDefaults.standard.set(Array(previous.union(confirmed)).sorted(), forKey: baselineKey)
                achievements = serverAchievements
            } catch {
                guard requestID == token, library.steamMobileAchievementAccountKey == account else { return }
                self.error = error.localizedDescription
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Label("REAL STEAM ACHIEVEMENTS", systemImage: "trophy.fill")
                    .font(.title2.weight(.black)).foregroundStyle(.cyan)
                SteamMobileCard {
                    HStack(spacing: 12) {
                        Image(systemName: SteamSignIn.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(SteamSignIn.isSignedIn ? .green : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SteamSignIn.isSignedIn ? "Steam account connected" : "Steam sign-in required")
                                .font(.headline).foregroundStyle(.white)
                            Text("Data requested from Valve through your authenticated Steam CM session.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Button("Open Steam library", action: openSteamLibrary)
                        .buttonStyle(.bordered)
                }
                SteamMobileCard {
                    Label("Select a Steam game", systemImage: "gamecontroller.fill")
                        .font(.headline).foregroundStyle(.white)
                    Picker("Steam game", selection: $selectedAppID) {
                        Text("Choose a game").tag(0)
                        ForEach(library.owned) { game in
                            Text(game.name).tag(game.id)
                        }
                    }
                    .tint(.cyan)
                    .disabled(inFlight)
                    .onChange(of: selectedAppID) { _, _ in refresh() }
                    HStack {
                        Button { refresh() } label: {
                            Label("Refresh from Steam", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!SteamSignIn.isSignedIn || selectedAppID == 0 || inFlight)
                        if inFlight { ProgressView().tint(.cyan) }
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                    if !newlyConfirmed.isEmpty {
                        Label("Newly confirmed on Steam: " + newlyConfirmed.joined(separator: ", "),
                              systemImage: "trophy.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    }
                }
                SteamMobileCard {
                    Label("Account achievement progress", systemImage: "chart.bar.fill")
                        .font(.headline).foregroundStyle(.white)
                    if achievements.isEmpty {
                        Text(inFlight ? "Loading actual achievement data…" :
                             "Choose a game and refresh to load achievements from Steam.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.74))
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(unlockedCount) / \(achievements.count)")
                                .font(.largeTitle.weight(.black)).foregroundStyle(.cyan)
                            Text("earned on Steam").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }
                        ProgressView(value: Double(unlockedCount),
                                     total: Double(max(1, achievements.count)))
                            .tint(.cyan)
                        ForEach(achievements) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.unlocked ? "trophy.fill" : "lock.fill")
                                    .foregroundStyle(item.unlocked ? .yellow : .gray)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.hidden && !item.unlocked ? "Hidden achievement" : item.title)
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    if !item.detail.isEmpty && (!item.hidden || item.unlocked) {
                                        Text(item.detail).font(.caption)
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    if item.unlockTimestamp > 0 {
                                        Text("Earned " + Date(timeIntervalSince1970:
                                            TimeInterval(item.unlockTimestamp)).formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2).foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                            }.padding(.vertical, 5)
                        }
                    }
                }
                SteamMobileCard {
                    Label("While playing", systemImage: "info.circle")
                        .font(.headline).foregroundStyle(.white)
                    Text("Steam Mobile passes your Steam login to Valve's game client during gameplay. Account-stat refresh resumes after the game closes; we never open a competing Steam session or claim that local files were confirmed as Steam unlocks.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.75))
                }
            }.padding(16)
        }
        .background(SteamMobilePalette.bg.ignoresSafeArea())
        .onAppear {
            library.start()
            if selectedAppID == 0, let first = library.owned.first {
                selectedAppID = first.id
            }
            // Also recheck when this tab becomes visible after gameplay.
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .steamMobileSessionEnded)) { _ in
            // Event posted after the game process ends and Madeira's Steam
            // connection is released. Never run a second account login midgame.
            refresh()
        }
        .onChange(of: library.owned.count) { _, count in
            if selectedAppID == 0, count > 0, let first = library.owned.first {
                selectedAppID = first.id
                refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SteamSignIn.didChange)) { _ in
            achievements = []
            newlyConfirmed = []
            requestID = UUID()
            inFlight = false
            selectedAppID = 0
            error = nil
            library.start()
        }
    }
}

private enum SteamMobileLauncherSource: String, CaseIterable, Identifiable {
    case ea, epic, ubisoft, gog, battle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ea: "EA App"
        case .epic: "Epic Games"
        case .ubisoft: "Ubisoft Connect"
        case .gog: "GOG Galaxy"
        case .battle: "Battle.net"
        }
    }
    var symbol: String {
        switch self {
        case .ea: "soccerball"
        case .epic: "square.stack"
        case .ubisoft: "circle.hexagongrid.fill"
        case .gog: "moon.stars.fill"
        case .battle: "gamecontroller.fill"
        }
    }
    var website: URL {
        switch self {
        case .ea: URL(string: "https://www.ea.com/ea-app")!
        case .epic: URL(string: "https://store.epicgames.com/en-US/download")!
        case .ubisoft: URL(string: "https://www.ubisoft.com/en-us/ubisoft-connect/download")!
        case .gog: URL(string: "https://www.gog.com/galaxy")!
        case .battle: URL(string: "https://download.battle.net/en-us/desktop")!
        }
    }
    // Official publisher delivery endpoints, not guessed URLs or mirrors.
    // Epic currently distributes an MSI; don't misleadingly execute it as EXE.
    var installer: URL? {
        switch self {
        case .ea:
            URL(string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe")
        case .ubisoft:
            URL(string: "https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe")
        case .battle:
            URL(string: "https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live")
        case .gog, .epic: nil
        }
    }
    var deliveryHosts: Set<String> {
        switch self {
        case .ea: ["origin-a.akamaihd.net"]
        case .ubisoft: ["static3.cdn.ubi.com"]
        case .battle: ["downloader.battle.net", "dist.blizzard.com", "us.patch.battle.net",
                       "eu.patch.battle.net", "cdn.blizzard.com", "blzstatic.com"]
        case .gog: ["content-system.gog.com", "cdn.gog.com"]
        case .epic: []
        }
    }
}

// An official publisher may redirect to its own CDN; refuse arbitrary hosts.
private final class SteamMobileLauncherRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let hosts: Set<String>
    init(hosts: Set<String>) { self.hosts = hosts }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let target = request.url
        completionHandler(target?.scheme == "https" && target?.port == nil &&
                          target?.user == nil && target?.password == nil &&
                          hosts.contains(target?.host?.lowercased() ?? "") ? request : nil)
    }
}

@MainActor
private final class SteamMobileLauncherFetcher: ObservableObject {
    @Published var busy: String?
    @Published var problem: String?
    func download(_ source: SteamMobileLauncherSource) async throws -> URL {
        guard busy == nil else { throw NSError(domain: "SteamMobileInstaller", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: "Another installer is downloading."]) }
        busy = source.id
        defer { busy = nil }
        let url: URL
        if source == .gog {
            // GOG's own version manifest; never hardcode a years-old Galaxy EXE.
            let manifest = URL(string: "https://remote-config.gog.com/components/webinstaller?component_version=2.0.0")!
            let (data, response) = try await URLSession.shared.data(from: manifest)
            guard let r = response as? HTTPURLResponse, r.statusCode == 200,
                  data.count < (1 << 20),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = root["content"] as? [String: Any],
                  let windows = content["windows"] as? [String: Any],
                  let link = windows["downloadLink"] as? String,
                  let downloadURL = URL(string: link) else {
                throw NSError(domain: "SteamMobileInstaller", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "GOG didn't provide a trusted Windows download link."])
            }
            url = downloadURL
        } else {
            guard let direct = source.installer else {
                throw NSError(domain: "SteamMobileInstaller", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "This launcher doesn't offer a verified EXE download endpoint."])
            }
            url = direct
        }
        guard url.scheme == "https", url.port == nil, url.user == nil, url.password == nil,
              source.deliveryHosts.contains(url.host?.lowercased() ?? "") else {
            throw NSError(domain: "SteamMobileInstaller", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Installer URL is not a trusted publisher host."])
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config,
                                 delegate: SteamMobileLauncherRedirects(hosts: source.deliveryHosts),
                                 delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https",
              source.deliveryHosts.contains(http.url?.host?.lowercased() ?? "") else {
            throw NSError(domain: "SteamMobileInstaller", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Publisher download was rejected or redirected outside its trusted hosts."])
        }
        let file = try FileHandle(forReadingFrom: temporary)
        defer { try? file.close() }
        let header = try file.read(upToCount: 64) ?? Data()
        guard header.count == 64, header[0] == 0x4d, header[1] == 0x5a else {
            throw NSError(domain: "SteamMobileInstaller", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "The server did not return a Windows EXE."])
        }
        let peOffset = (0..<4).reduce(UInt64(0)) { $0 | (UInt64(header[60 + $1]) << ($1 * 8)) }
        guard peOffset >= 64 && peOffset < 16 * 1024 * 1024 else {
            throw NSError(domain: "SteamMobileInstaller", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "Malformed installer PE header."])
        }
        try file.seek(toOffset: peOffset)
        let signature = try file.read(upToCount: 6) ?? Data()
        guard signature.count == 6, Array(signature.prefix(4)) == [0x50, 0x45, 0, 0],
              [0x014c, 0x8664].contains(Int(signature[4]) | Int(signature[5]) << 8) else {
            throw NSError(domain: "SteamMobileInstaller", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "Installer isn't an x86/x64 Windows executable."])
        }
        let size = try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber
        guard let bytes = size?.int64Value, bytes >= 4096, bytes < 700 * 1024 * 1024 else {
            throw NSError(domain: "SteamMobileInstaller", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "Installer has an invalid size."])
        }
        let folder = LibraryModel.drive.appendingPathComponent("SteamMobileLaunchers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.id + "-official-installer.exe")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

struct SteamMobileLaunchersTab: View {
    var runInstaller: (URL) -> Void
    var startDock: (DockGame, Bool) -> Void
    @StateObject private var fetcher = SteamMobileLauncherFetcher()
    @State private var showSteam = false
    @State private var showDock = false
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LAUNCHER HUB").font(.title2.weight(.black)).foregroundStyle(.white)
                Text("Publisher downloads • one Windows environment. Compatibility depends on Wine, Windows services and DRM.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.72))
                SteamMobileCard {
                    Label("Steam", systemImage: "gamecontroller.fill")
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("Native Steam library, installed games and game downloads.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.75))
                    HStack {
                        Button("Steam account") { showSteam = true }.buttonStyle(.borderedProminent)
                        Button("Open Steam client") { showDock = true }.buttonStyle(.bordered)
                    }
                }
                ForEach(SteamMobileLauncherSource.allCases) { launcher in
                    SteamMobileCard {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: launcher.symbol)
                                .font(.title2).foregroundStyle(SteamMobilePalette.violet)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(launcher.title).font(.headline).foregroundStyle(.white)
                                Text("Windows launcher • installation and sign-in are experimental")
                                    .font(.caption2).foregroundStyle(.orange)
                                HStack {
                                    if launcher != .epic {
                                        Button {
                                            Task {
                                                do {
                                                    let path = try await fetcher.download(launcher)
                                                    runInstaller(path)
                                                } catch {
                                                    fetcher.problem = error.localizedDescription
                                                }
                                            }
                                        } label: {
                                            if fetcher.busy == launcher.id {
                                                ProgressView().tint(.white)
                                            } else {
                                                Label("Download & run", systemImage: "arrow.down.to.line")
                                            }
                                        }.buttonStyle(.borderedProminent)
                                            .disabled(fetcher.busy != nil)
                                    }
                                    Button("Publisher site") { openURL(launcher.website) }
                                        .buttonStyle(.bordered)
                                }.font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                SteamMobileCard {
                    Text("Epic Games distributes an MSI Windows installer. This build does not auto-execute MSI packages; use the official publisher site until the Wine MSI bridge is validated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
        .background(
            LinearGradient(colors: [SteamMobilePalette.bg,
                                    SteamMobilePalette.violet.opacity(0.12),
                                    SteamMobilePalette.bg],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        )
        .sheet(isPresented: $showSteam) { SteamSignInView() }
        .sheet(isPresented: $showDock) { MadeiraDockView(start: startDock) }
        .alert("Launcher download", isPresented: Binding(
            get: { fetcher.problem != nil },
            set: { if !$0 { fetcher.problem = nil } })) {
            Button("OK", role: .cancel) { fetcher.problem = nil }
        } message: {
            Text(fetcher.problem ?? "")
        }
    }
}
'''

def patch(src):
    src = once(src, '    static let title = "Madeira"',
               '    static let title = "Steam Mobile"',
               "Steam Mobile header branding")
    a = '''            settings
                .tabItem { Image(systemName: "gearshape.fill").accessibilityLabel("Settings") }
                .tag(1)'''
    b = '''            SteamMobilePerformanceTab(
                openJIT: { jit.showSetup = true },
                openOptions: { switchTab(to: 1); settingsSheet = .allSettings }
            )
                .tabItem { Label("Performance", systemImage: "speedometer") }
                .tag(2)
            SteamMobileLaunchersTab(runInstaller: { url in
                do {
                    let entry = try LibraryModel.inspect(url)
                    play(entry)
                } catch {
                    model.error = error.localizedDescription
                }
            }, startDock: startDock)
                .tabItem { Label("Launchers", systemImage: "square.stack.3d.up.fill") }
                .tag(3)
            SteamMobileAchievementsTab(openSteamLibrary: { switchTab(to: 0) })
                .tabItem { Label("Achievements", systemImage: "trophy.fill") }
                .tag(4)
            settings
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(1)'''
    src = once(src, a, b, "Steam Mobile add performance and launcher tabs")
    src = once(src, '''            library
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .tabItem { Image(systemName: "square.grid.2x2.fill").accessibilityLabel("Library") }''',
        '''            library
                .background(SteamMobilePalette.bg.ignoresSafeArea())
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }''',
        "Steam Mobile library tab")
    src = once(src, '''        .navigationTitle("")
        .toolbar {
            LibraryLargeTitle()
            if tab == 0 { libraryToolbar } else { settingsToolbar }
        }''',
        '''        .navigationTitle("")
        .preferredColorScheme(.dark)
        .toolbar {
            LibraryLargeTitle()
            if tab == 0 { libraryToolbar }
            else if tab == 1 { settingsToolbar }
        }''', "Steam Mobile title and dark style")
    src = once(src,
        '''        .background(LibraryNavSearch(text: tab == 0 ? $search : $settingsSearch,
                                     placeholder: tab == 0 ? "Search your library" : "Search settings")
            .frame(width: 0, height: 0))''',
        '''        .background {
            if tab == 0 || tab == 1 {
                LibraryNavSearch(text: tab == 0 ? $search : $settingsSearch,
                                 placeholder: tab == 0 ? "Search your library" : "Search settings")
                    .frame(width: 0, height: 0)
            }
        }''', "Steam Mobile remove unrelated search on extra tabs")
    src = once(src,
        '''            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Button { selected = model.entries.first(where: { $0.desktop == true }) ?? .desktopEntry } label: {''',
        '''            VStack(alignment: .leading, spacing: 24) {
                SteamMobileSteamHomeStatus()
                HStack {
                    Button { selected = model.entries.first(where: { $0.desktop == true }) ?? .desktopEntry } label: {''',
        "Steam Mobile real library home hero")
    # The authenticated, downloadable Steam collection belongs on Home.
    # Don't put uninstalled games below the local EXE import collection.
    src = once(src,
        'let steamFirst = MadeiraDock.enabled && SteamGamesSection.hasInstalled',
        'let steamFirst = MadeiraDock.enabled',
        "Steam first on home")
    src = once(src,
        'part: .installed, open: { selected = $0 })',
        'part: .all, open: { selected = $0 })',
        "Show installed and uninstalled Steam games together")
    src = once(src,
        '''                    if MadeiraDock.enabled {
                        SteamGamesSection(search: search, layout: layout, sort: sort, width: viewport.size.width,
                                          part: steamFirst ? .notInstalled : .all, open: { selected = $0 })
                    }''',
        '''                    if MadeiraDock.enabled && !steamFirst {
                        SteamGamesSection(search: search, layout: layout, sort: sort, width: viewport.size.width,
                                          part: .all, open: { selected = $0 })
                    }''',
        "Do not duplicate Steam account catalog")
    src = src.replace("Copy a game's folder into Madeira › wine › drive_c", "Copy a game's folder into Steam Mobile › wine › drive_c")
    src = src.replace("Restart Madeira to start another game", "Restart Steam Mobile to start another game")
    # Prefer conservative synchronization for known crash-on-start games
    # until the user explicitly chooses otherwise. Other games retain their
    # prior defaults; this changes no owned games, accounts or Steam entitlements.
    src = once(src,
        '''            setenv("MADEIRA_FASTSYNC", fastSync == false ? "0" : mode, 1)''',
        '''            let startupSafe = [8980, 729040, 49520, 1462040, 1091500].contains(steamAppID ?? -1)
            let useFastSync = fastSync ?? !startupSafe
            setenv("MADEIRA_FASTSYNC", useFastSync ? mode : "0", 1)''',
        "Conservative Borderlands launch sync defaults")
    src = once(src,
        '''Toggle("Fast synchronization", isOn: Binding(get: { entry.fastSync ?? true }, set: { entry.fastSync = $0 }))''',
        '''Toggle("Fast synchronization", isOn: Binding(
                            get: { entry.fastSync ?? ![8980, 729040, 49520, 1462040, 1091500].contains(entry.steamAppID ?? -1) },
                            set: { entry.fastSync = $0 }))''',
        "Make default safe sync state visible and user reversible")
    # An explicit, reversible per-game compatibility baseline. Never force
    # risky engine flags or automatically downgrade a user's successful profile.
    # This helps test whether a splash-then-exit is related to sync/upscaling/
    # CPU/GPU emulation switches; it cannot solve missing DLLs/DRM.
    src = once(src,
        '''                Section {
                    Toggle("Reduced-precision x87", isOn: $entry.reducedX87)''',
        '''                if entry.desktop != true {
                    Section {
                        Button {
                            entry.fastSync = false
                            entry.semaphoreFastPath = false
                            entry.frameGeneration = nil
                            entry.metalFXUpscale = nil
                            entry.avx = nil
                            entry.reportNVIDIA = nil
                            entry.reducedX87 = false
                            entry.cpuCount = nil
                            entry.anisotropyLimit = nil
                            entry.liveLogs = true
                            entry.fpsMode = 1
                            model.save(entry)
                        } label: {
                            Label("Apply safe launch settings", systemImage: "shield.lefthalf.filled")
                        }
                        Text("Disables experimental frame generation, MetalFX, AVX emulation and fast sync for this game. Enables live diagnostic logs. Your installed game and saves are unchanged. Quit the current Wine session, then launch again.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let appID = entry.steamAppID {
                            Text("Steam game \(appID): the official Steam client still checks the license. A launcher crash, missing runtime or incompatible DRM cannot be fixed by performance settings alone.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("Steam Mobile • Startup Rescue") }
                }
                Section {
                    Toggle("Reduced-precision x87", isOn: $entry.reducedX87)''',
        "Expose real per-game safe-start diagnostic action")
    src = once(src,
        '''        .onReceive(controller.commands) { command in
            if selected == nil, !browser, !onboarding.presented, command == "tab" { switchTab(to: 1 - tab) }
        }''',
        '''        .onReceive(controller.commands) { command in
            if selected == nil, !browser, !onboarding.presented, command == "tab" {
                switchTab(to: tab == 0 ? 2 : tab == 2 ? 3 : tab == 3 ? 4 : tab == 4 ? 1 : 0)
            }
        }''', "Steam Mobile controller tab cycle")
    if "struct SteamMobilePerformanceTab" in src:
        raise RuntimeError("Already has UI appended; refuse duplicate patch")
    return src + "\n" + UI_APPEND + "\n" + (Path(__file__).resolve().parents[1] / "runtime/PerformanceCapture.swift").read_text(encoding="utf-8")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--madeira",required=True,type=Path)
    ap.add_argument("--check",action="store_true")
    args=ap.parse_args()
    target=args.madeira/"app/Madeira/Library.swift"
    result=patch(target.read_text())
    if args.check:
        print("Steam Mobile SwiftUI anchors verified")
    else:
        target.write_text(result)
        # Keep the native Valve depot downloader and license/credits untouched,
        # but ensure the Windows game-download UI uses Steam Mobile branding.
        games = args.madeira/"app/Madeira/SteamGames.swift"
        if games.is_file():
            copy = games.read_text()
            copy = copy.replace("You can leave Madeira while it downloads:", "You can leave Steam Mobile while it downloads:")
            games.write_text(copy)
        # Surface Steam Dock's real start/exit signals. Steam LaunchApp result
        # code 0 does not mean that the game successfully entered gameplay.
        dock = args.madeira / "app/Madeira/MadeiraDock.swift"
        dock_src = dock.read_text(encoding="utf-8")
        dock_src = once(
            dock_src,
            '''        "launch-client-error", "launch-option-index", "launch-option-invalid", "launch-option-missing",''',
            '''        "launch-request-submitted", "launch-game-running", "launch-game-ended",
        "launch-host-result", "launch-client-error", "launch-option-index", "launch-option-invalid", "launch-option-missing",''',
            "Expose all actual Steam Dock game process status changes",
        )
        dock.write_text(dock_src, encoding="utf-8")
        screen = args.madeira / "app/Madeira/DockStartScreen.swift"
        screen_src = screen.read_text(encoding="utf-8")
        screen_src = once(
            screen_src,
            '''        if fields["launch-client-error"] == "0" { return "The game is starting. Waiting for its window…" }''',
            '''        if fields["launch-game-ended"] == "1" {
            return "Steam started the game, but it exited before displaying gameplay. Open the diagnostics log."
        }
        if fields["launch-client-error"] == "0" { return "The game is starting. Waiting for its window…" }''',
            "Do not display an indefinite waiting message when the guest process exited",
        )
        screen_src = once(
            screen_src,
            '''                if let words = DockStartStatus.failure(result: current.result, words: current.failure, launching: model.launching) {
                    failure = words''',
            '''                let gameExitedBeforeWindow = current.result == 0 && current.fields["launch-game-ended"] == "1"
                let words = gameExitedBeforeWindow
                    ? "Steam launched this title, but its Windows process exited before showing gameplay. In Steam Mobile, open Game details → Startup Rescue, then export the session log if it persists."
                    : DockStartStatus.failure(result: current.result, words: current.failure, launching: model.launching)
                if let words {
                    failure = words''',
            "Explain early game process exit separately from Steam licence or sign-in failures",
        )
        screen.write_text(screen_src, encoding="utf-8")
        # A subset of Steam products publish separate launch entries for a
        # configuration utility and a playable game. For the two Borderlands
        # editions, prefer another *Steam-authored* valid Windows game option
        # only if one exists on disk; otherwise keep Steam's default exactly.
        # No direct-launch shortcut or license bypass is created.
        cv = args.madeira / "app/Madeira/ContentView.swift"
        if cv.is_file():
            cv_src = cv.read_text(encoding="utf-8")
            cv_src = once(
                cv_src,
                '''            let chosen = options.flatMap { SteamDirectStart.choose($0, installFolder: installFolder)?.launchIndex }
            let launchOption = chosen ?? 0''',
                r'''            let defaultChoice = options.flatMap { SteamDirectStart.choose($0, installFolder: installFolder) }
            let alternate: SteamDirectStart.Choice? = (game.id == 8980 || game.id == 729040)
                ? options.flatMap { entries in
                    SteamDirectStart.choose(entries.filter { option in
                        let filename = option.executable
                            .replacingOccurrences(of: "\\", with: "/")
                            .split(separator: "/").last.map(String.init)?.lowercased() ?? ""
                        return !filename.contains("launcher") &&
                               !filename.contains("config") &&
                               !filename.contains("setup") &&
                               !filename.contains("settings")
                    }, installFolder: installFolder)
                } : nil
            let chosen = (alternate ?? defaultChoice)?.launchIndex
            let launchOption = chosen ?? 0''',
                "Prefer official Steam game launch option over configuration utility for Borderlands",
            )
            cv_src = once(
                cv_src,
                '''            LogStore.shared.log("[madeira-dock] launch option \(launchOption)\(chosen == nil ? " (none chosen: the default)" : "")")''',
                '''            let selectedProgram = (alternate ?? defaultChoice)?.program
                .split(separator: "/").last.map(String.init) ?? "steam-default"
            LogStore.shared.log("[steam-mobile-launch] app=\(game.id) launch-option=\(launchOption) program=\(selectedProgram) mode=\(alternate == nil ? "normal" : "play-option")")''',
                "Make selected game launch program visible in non-sensitive diagnostics",
            )
            cv.write_text(cv_src, encoding="utf-8")
        print("Steam Mobile SwiftUI + early-exit diagnostics integrated")
if __name__=="__main__": main()
