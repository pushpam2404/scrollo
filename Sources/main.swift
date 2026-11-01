import AppKit
import SwiftUI
import Combine

/// Lets controls in a borderless panel take focus.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: NSPanel?
    private var lastClosed = Date.distantPast
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    private var poll: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarGlyph()
        item.button?.target = self
        item.button?.action = #selector(toggle)

        Settings.shared.$enabled.receive(on: RunLoop.main)
            .sink { [weak self] on in self?.item.button?.alphaValue = on ? 1 : 0.4 }.store(in: &bag)

        AudioPlayer.shared.start()
        Visualizer.shared.start()
        if UserDefaults.standard.bool(forKey: "debugProbe") { Diagnostics.start() }   // developer tool, off by default
        let monitor = ScrollMonitor.shared
        if !monitor.trusted { monitor.promptForAccess() }
        monitor.start()
        // Pick up the Accessibility grant without a relaunch.
        poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            if !monitor.running { monitor.start() }
        }
    }

    /// Template glyph: scroll wheel with a lit notch and sound waves, drawn to match the app icon.
    private static func menuBarGlyph() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let wheel = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 1.5, width: 7, height: 15), xRadius: 3.5, yRadius: 3.5)
            wheel.lineWidth = 1.5; wheel.stroke()
            NSBezierPath(roundedRect: NSRect(x: 8, y: 8.25, width: 4, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            for r in [7.0, 9.4] {
                for dir in [0.0, 180.0] {
                    let p = NSBezierPath()
                    p.appendArc(withCenter: NSPoint(x: 10, y: 9), radius: CGFloat(r), startAngle: dir - 32, endAngle: dir + 32)
                    p.lineWidth = 1.4; p.lineCapStyle = .round; p.stroke()
                }
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Scrollo"
        return img
    }

    /// A borderless panel anchored under the status item. NSPopover mis-positions itself on notched
    /// screens (its top ends up under the menu bar), so the frame is computed and clamped by hand.
    private func makePanel() -> NSPanel {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: MenuContent(openSettings: { [weak self] in self?.showSettings() }))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            self?.closePanel()
        }
        return p
    }

    private func closePanel() {
        guard let p = panel, p.isVisible else { return }
        p.orderOut(nil)
        lastClosed = Date()
    }

    @objc private func toggle() {
        if let p = panel, p.isVisible { closePanel(); return }
        if Date().timeIntervalSince(lastClosed) < 0.25 { return }   // this click just dismissed it
        guard let button = item.button, let bw = button.window else { return }
        let p = panel ?? makePanel()
        panel = p
        let size = (p.contentView as! NSHostingView<MenuContent>).fittingSize
        let anchor = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let vf = (bw.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let x = min(max(anchor.midX - size.width / 2, vf.minX + 8), vf.maxX - size.width - 8)
        p.setFrame(NSRect(x: x, y: vf.maxY - size.height - 6, width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        closePanel()
        if settingsWindow == nil {
            defer { settingsWindow?.center() }
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Scrollo Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
