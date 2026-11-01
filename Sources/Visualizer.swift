import AppKit
import SwiftUI

/// Equalizer bars drawn beside the notch (or top-centre on Macs without one).
final class Visualizer: ObservableObject {
    static let shared = Visualizer()
    @Published var visible = false
    private(set) var level = 0.0
    private(set) var lastPulse = Date.distantPast
    private var panel: NSPanel?
    private var timer: Timer?
    private let settings = Settings.shared

    func pulse() {
        let now = Date()
        level = min(1, currentLevel(at: now) + 0.3)
        lastPulse = now
        if settings.visualizer == .scrolling { ensurePanel() }
    }

    func currentLevel(at t: Date) -> Double { level * exp(-t.timeIntervalSince(lastPulse) / 0.22) }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        switch settings.visualizer {
        case .off: visible = false
        case .always: visible = true; ensurePanel()
        case .scrolling: visible = Date().timeIntervalSince(lastPulse) < 0.7
        }
        // Take the (transparent) panel off screen entirely once idle, so nothing lingers at menu-bar level.
        let idle = Date().timeIntervalSince(lastPulse) > 1.2
        if settings.visualizer == .off || (settings.visualizer == .scrolling && idle) { panel?.orderOut(nil) }
    }

    /// With the menu bar auto-hidden (full-screen apps) nothing is drawn near the top, so it stays out of the way.
    private func menuBarShowing() -> Bool {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        return screen.frame.maxY - screen.visibleFrame.maxY > 1
    }

    private func ensurePanel() {
        guard menuBarShowing() else { panel?.orderOut(nil); return }
        let p = panel ?? makePanel()
        panel = p
        position(p)
        if !p.isVisible { p.orderFrontRegardless() }
        p.alphaValue = 1
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 44, height: 24),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: BarsView(model: self, settings: settings))
        return p
    }

    private func position(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        let bar = max(24, screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : f.maxY - screen.visibleFrame.maxY)
        var x = f.midX - 22
        if screen.safeAreaInsets.top > 0, var r = screen.auxiliaryTopRightArea {
            if r.minX < f.minX { r.origin.x += f.minX }
            x = r.minX + 8
        }
        p.setFrame(NSRect(x: x, y: f.maxY - bar, width: 44, height: bar), display: true)
    }
}

struct BarsView: View {
    @ObservedObject var model: Visualizer
    @ObservedObject var settings: Settings

    var body: some View {
        TimelineView(.animation) { ctx in
            bars(at: ctx.date)
        }
    }

    private func bars(at now: Date) -> some View {
        let idle = settings.visualizer == .always
        let level = max(model.currentLevel(at: now), idle ? 0.12 : 0)
        let color: Color = settings.tintBars ? SoundBank.option(settings.soundID).color : .white
        let t = now.timeIntervalSinceReferenceDate
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                bar(i, t: t, level: level, color: color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(model.visible ? 1 : 0.6)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.visible)
    }

    private func bar(_ i: Int, t: Double, level: Double, color: Color) -> some View {
        let wave = 0.5 + 0.5 * sin(t * (7 + Double(i) * 1.7) + Double(i) * 1.3)
        let height = CGFloat(3 + 13 * level * (0.35 + 0.65 * wave))
        let fill = LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        return Capsule().fill(fill).frame(width: 3, height: height)
    }
}
