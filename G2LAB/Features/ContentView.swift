import SwiftUI

struct ContentView: View {
    @EnvironmentObject var g2: G2Controller
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("G2 LAB").font(.system(size: 34, weight: .black, design: .rounded))
                        Text("ACCESSIBILITY & AUGMENTED COMMUNICATION SUITE").font(.caption).foregroundStyle(.secondary)
                        HStack { Circle().frame(width: 9); Text(g2.status).font(.headline.monospaced()) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    GroupBox("G2 LINK") {
                        VStack(spacing: 10) {
                            Button("SCAN G2") { g2.scan() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                            ForEach(Array(g2.devices.enumerated()), id: \.offset) { _, d in
                                Button("CONNECT  •  \(d.name)") { g2.connect(d) }.buttonStyle(.bordered)
                            }
                            HStack {
                                Button("LINK ACTIVE HUD") { g2.showProof() }
                                Button("CLEAR") { g2.clearHUD() }
                            }.buttonStyle(.bordered)
                        }
                    }
                    GroupBox("G2 MICROPHONE") {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: g2.micLevel)
                            Text(String(format: "PCM LEVEL  %.3f", g2.micLevel)).font(.caption.monospaced())
                            Button(g2.micEnabled ? "STOP MIC" : "START MIC") { g2.toggleMic() }.buttonStyle(.borderedProminent)
                        }
                    }
                    GroupBox("NEXT ENGINE") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("🇮🇹 Offline Italian captions")
                            Text("Rolling transcript • instant replay • sound awareness • translation • AI transcript actions")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("DIAGNOSTIC CONSOLE") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(g2.logs.prefix(35).enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding()
            }.navigationBarHidden(true).preferredColorScheme(.dark)
        }
    }
}
