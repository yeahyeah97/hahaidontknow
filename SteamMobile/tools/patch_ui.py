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
                 : "Continue your game with Madeira's native DXMT, Wine and FEX runtime.")
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
                    Text("Measure DX9, Wine and FEX throughput. RAW removes presentation pacing but cannot remove CPU/GPU bottlenecks.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                }.padding(.vertical, 8)
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
                    Label("Runtime health", systemImage: "waveform.path.ecg")
                        .font(.headline).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 9) {
                        Label("FEX JIT code translation", systemImage: "bolt.fill")
                        Label("DXMT Metal renderer / DirectX 9", systemImage: "cube.transparent")
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
    @State private var lastCloudUnlocks: [Int: Set<String>] = [:]
    @State private var newlyConfirmed: [String] = []
    private var unlockedCount: Int { achievements.filter(\.unlocked).count }

    private func refresh() {
        guard selectedAppID > 0, !inFlight else { return }
        let appID = selectedAppID
        inFlight = true
        error = nil
        newlyConfirmed = []
        achievements = []
        Task { @MainActor in
            defer { inFlight = false }
            do {
                let serverAchievements = try await library.steamMobileAchievements(for: appID)
                // First read seeds the baseline without noisy "unlock" popups
                // for trophies earned months ago. Later reads show only
                // additional achievements actually confirmed by Steam.
                let confirmed = Set(serverAchievements.filter(\.unlocked).map(\.id))
                if let baseline = lastCloudUnlocks[appID] {
                    let fresh = confirmed.subtracting(baseline)
                    newlyConfirmed = serverAchievements.filter { fresh.contains($0.id) }
                        .map(\.title)
                    if !newlyConfirmed.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
                lastCloudUnlocks[appID] = confirmed
                achievements = serverAchievements
            } catch {
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
                        ForEach(Array(library.owned.prefix(150))) { game in
                            Text(game.name).tag(game.id)
                        }
                    }
                    .tint(.cyan)
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
                    Text("Madeira hands your Steam login to Valve's game client during gameplay. Account-stat refresh resumes after the game closes; we never open a competing Steam session or claim that local files were confirmed as Steam unlocks.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.75))
                }
            }.padding(16)
        }
        .background(SteamMobilePalette.bg.ignoresSafeArea())
        .onAppear {
            library.start()
            if selectedAppID == 0, let first = library.owned.first {
                selectedAppID = first.id
                refresh()
            }
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
            lastCloudUnlocks = [:]
            error = nil
            library.start()
        }
    }
}

struct SteamMobileLaunchersTab: View {
    var openInstaller: () -> Void
    @State private var showSteam = false
    @State private var showDock = false
    var startDock: (DockGame, Bool) -> Void
    private let titles = ["EA App", "Epic Games", "Ubisoft Connect", "GOG Galaxy", "Battle.net"]
    private let symbols = ["soccerball", "square.stack", "circle.hexagongrid.fill", "moon.stars.fill", "gamecontroller.fill"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LAUNCHER HUB").font(.title2.weight(.black)).foregroundStyle(.white)
                Text("Windows launcher installers run through Wine. Individual sign-in, WebView and DRM compatibility is experimental.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                SteamMobileCard {
                    Label("Steam", systemImage: "gamecontroller.fill")
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("Your real Steam account and Madeira Dock.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.75))
                    HStack {
                        Button("Sign in") { showSteam = true }.buttonStyle(.borderedProminent)
                        Button("Open Dock") { showDock = true }.buttonStyle(.bordered)
                    }
                }
                ForEach(Array(titles.enumerated()), id: \.offset) { i, name in
                    SteamMobileCard {
                        HStack {
                            Image(systemName: symbols[i])
                                .font(.title).foregroundStyle(SteamMobilePalette.violet)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.headline).foregroundStyle(.white)
                                Text("Experimental installer · not verified")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("Import EXE", action: openInstaller)
                                .font(.caption.weight(.bold)).buttonStyle(.bordered)
                        }
                    }
                }
                SteamMobileCard {
                    Label("Steam achievements", systemImage: "trophy")
                        .font(.headline).foregroundStyle(.white)
                    Text("Legitimate achievement synchronization needs a working native Steam client/Steamworks callback bridge. Not currently available in this build.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.75))
                }
            }.padding(16)
        }
        .background(SteamMobilePalette.bg.ignoresSafeArea())
        .sheet(isPresented: $showSteam) { SteamSignInView() }
        .sheet(isPresented: $showDock) { MadeiraDockView(start: startDock) }
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
            SteamMobileLaunchersTab(openInstaller: { browser = true }, startDock: startDock)
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
                SteamMobileLibraryHero(item: model.entries.first(where: { $0.desktop != true })) {
                    selected = $0
                }
                HStack {
                    Button { selected = model.entries.first(where: { $0.desktop == true }) ?? .desktopEntry } label: {''',
        "Steam Mobile real library home hero")
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
    return src + "\n" + UI_APPEND

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
        print("Steam Mobile SwiftUI native library integrated")
if __name__=="__main__": main()
