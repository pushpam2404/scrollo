import SwiftUI

let mint = Color(red: 0.42, green: 0.82, blue: 0.67)

struct MenuContent: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var monitor = ScrollMonitor.shared
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scrollo").font(.headline)
                Spacer()
                Toggle("", isOn: $settings.enabled).toggleStyle(.switch).labelsHidden()
            }
            if !monitor.running {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                    Text("Scrollo listens for scroll events to play the clicks. Nothing is recorded or sent anywhere.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Grant access…") { monitor.promptForAccess() }
                }
            }
            VStack(spacing: 12) {
                SliderRow(title: "Volume", value: "\(Int((settings.volume * 100).rounded()))%") {
                    Slider(value: $settings.volume, in: 0...1)
                }
                // Position 0 = haptics off, 1...5 = Whisper ... Heavy.
                SliderRow(title: "Haptics", value: "") {
                    Slider(value: Binding(get: { settings.haptics ? Double(settings.hapticStrength + 1) : 0 },
                                          set: { v in
                                              let n = Int(v.rounded())
                                              settings.haptics = n > 0
                                              if n > 0 { settings.hapticStrength = n - 1 }
                                          }), in: 0...5)
                }
                SliderRow(title: "Click spacing", value: "\(Int(settings.spacing)) px") {
                    Slider(value: Binding(get: { settings.spacing },
                                          set: { settings.spacing = ($0 / 5).rounded() * 5 }), in: 50...500)
                }
            }
            SoundGrid()
            Divider()
            HStack {
                Button("Settings…", action: openSettings).keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .tint(mint)
        .preferredColorScheme(.dark)
    }
}

/// A titled control row with the current value shown on the right.
struct SliderRow<Content: View>: View {
    let title: String
    let value: String
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
                if let trailing { trailing }
            }
            content
        }
    }
}

struct SoundGrid: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 5), spacing: 6) {
            ForEach(SoundBank.all) { s in
                let on = settings.soundID == s.id
                Button {
                    settings.soundID = s.id
                    AudioPlayer.shared.play()
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8).fill(s.color.gradient).frame(width: 28, height: 28)
                            .overlay(Image(systemName: "waveform").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.9)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(mint, lineWidth: on ? 2 : 0))
                        Text(s.name).font(.caption2).multilineTextAlignment(.center)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(on ? mint.opacity(0.22) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

final class DeviceList: ObservableObject {
    @Published var items = AudioDevices.list()
}

/// Which Settings tab is showing (also lets the docs renderer capture each one).
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab = 0
}

struct SettingsView: View {
    @ObservedObject var nav = SettingsNav.shared
    @ObservedObject var settings = Settings.shared
    @StateObject private var devs = DeviceList()

    var body: some View {
        TabView(selection: $nav.tab) {
            Form {
                Section("Click sound") { SoundGrid() }
                Section {
                    HStack { Text("Volume"); Slider(value: $settings.volume, in: 0...1) }
                    Picker("Output", selection: $settings.outputUID) {
                        Text("System Default").tag("")
                        ForEach(devs.items) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: settings.outputUID) { _, _ in AudioPlayer.shared.refreshRoute() }
                } footer: {
                    Text("If the chosen device disconnects, Scrollo falls back to the system default until it returns.")
                }
            }
            .tabItem { Label("Sound", systemImage: "speaker.wave.2") }.tag(0)

            Form {
                Section {
                    HStack {
                        Text("Spacing")
                        Slider(value: Binding(get: { settings.spacing },
                                              set: { settings.spacing = ($0 / 5).rounded() * 5 }), in: 50...500)
                        Text("\(Int(settings.spacing)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    Text("How far you scroll on a trackpad between clicks. Wheel mice click once per notch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Only click when the content moves", isOn: $settings.muteAtEdges)
                    Text("Stays silent when nothing on screen actually scrolls: page edges, rubber-banding, windows with nothing to scroll.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Click during momentum scrolling", isOn: $settings.clickOnMomentum)
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    if let m = settings.loginMessage { Text(m).font(.caption).foregroundStyle(.orange) }
                }
                Section("Apps without scroll info") {
                    Toggle("Also click in apps that don't report scrolling", isOn: $settings.clickWithoutInfo)
                    Text("Scrollo only clicks in apps that tell it where the page is (Preview, Word, Pages, Finder, Terminal and most native apps). Browsers, WhatsApp, Spotify and similar apps don't, so it stays silent there. Turn this on to click there anyway; it can't detect page edges in those apps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }.tag(1)

            Form {
                Toggle("Trackpad haptics", isOn: $settings.haptics)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Strength")
                        Spacer()
                        Text(Haptics.levelNames[max(0, min(4, settings.hapticStrength))]).foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(settings.hapticStrength) },
                                          set: { settings.hapticStrength = Int($0.rounded()) }), in: 0...4)
                    HStack { Text("Whisper"); Spacer(); Text("Heavy") }.font(.caption2).foregroundStyle(.secondary)
                }
                .disabled(!settings.haptics)
                HStack {
                    Button("Test") { Haptics.fire(level: settings.hapticStrength) }
                    Button("Feel all levels") { Haptics.sweep() }
                }
                Text("Uses the Taptic Engine on Force Touch trackpads. Five fixed steps, since macOS has no smooth amplitude control. Needs a Force Touch trackpad.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Haptics", systemImage: "hand.tap") }.tag(2)

            Form {
                Picker("Equalizer", selection: $settings.visualizer) {
                    ForEach(VisualizerMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Tint bars with sound color", isOn: $settings.tintBars)
                Text("Bars appear beside the notch (top centre on Macs without one).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Visualizer", systemImage: "waveform") }.tag(3)
        }
        .formStyle(.grouped)
        .tint(mint)
        .preferredColorScheme(.dark)
        .frame(width: 480, height: 480)
        .onAppear { devs.items = AudioDevices.list() }
    }
}
