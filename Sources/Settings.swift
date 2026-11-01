import Foundation
import ServiceManagement

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    @Published var soundID: String { didSet { d.set(soundID, forKey: "soundID") } }
    /// Scroll points between clicks on trackpads (smaller = denser).
    @Published var spacing: Double { didSet { d.set(spacing, forKey: "spacing") } }
    @Published var muteAtEdges: Bool { didSet { d.set(muteAtEdges, forKey: "muteAtEdges") } }
    @Published var clickOnMomentum: Bool { didSet { d.set(clickOnMomentum, forKey: "clickOnMomentum") } }
    @Published var outputUID: String { didSet { d.set(outputUID, forKey: "outputUID") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var hapticStrength: Int { didSet { d.set(hapticStrength, forKey: "hapticStrength") } }
    var debugEdge = true   // logs edge-detection verdicts to ~/Library/Logs/Scrollo.log
    /// Also click in apps that report no scroll position (their edges can't be detected there).
    @Published var clickWithoutInfo: Bool { didSet { d.set(clickWithoutInfo, forKey: "clickWithoutInfo") } }
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }
    @Published var loginMessage: String?

    init() {
        d.register(defaults: [
            "enabled": true, "volume": 0.6, "soundID": "softpop", "spacing": 120.0,
            "muteAtEdges": true, "clickOnMomentum": true, "outputUID": "",
            "haptics": false, "hapticStrength": 2,
            "clickWithoutInfo": false,
        ])
        enabled = d.bool(forKey: "enabled")
        volume = d.double(forKey: "volume")
        let saved = d.string(forKey: "soundID") ?? "softpop"
        soundID = SoundBank.all.contains { $0.id == saved } ? saved : "softpop"
        spacing = min(500, max(50, d.double(forKey: "spacing")))
        muteAtEdges = d.bool(forKey: "muteAtEdges")
        clickOnMomentum = d.bool(forKey: "clickOnMomentum")
        outputUID = d.string(forKey: "outputUID") ?? ""
        haptics = d.bool(forKey: "haptics")
        hapticStrength = d.integer(forKey: "hapticStrength")
        clickWithoutInfo = d.bool(forKey: "clickWithoutInfo")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        let svc = SMAppService.mainApp
        do {
            if launchAtLogin { try svc.register() } else { try svc.unregister() }
            loginMessage = svc.status == .requiresApproval
                ? "Approve Scrollo in System Settings > General > Login Items." : nil
        } catch {
            loginMessage = "Launch at login failed: \(error.localizedDescription)"
        }
    }
}
