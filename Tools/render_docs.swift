// Renders Scrollo's real SwiftUI interface to PNGs for the documentation.
// Built from the app's own sources (see scripts/render-docs.sh), so the images always match the app.
// Usage: render_docs <output-dir>
import AppKit
import SwiftUI

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Representative settings for the screenshots (this tool has its own preferences domain, so nothing real is touched).
let s = Settings.shared
s.enabled = true; s.volume = 0.65; s.soundID = "softpop"; s.spacing = 140
s.haptics = true; s.hapticStrength = 2; s.visualizer = .scrolling; s.tintBars = true
ScrollMonitor.shared.markRunningForDocs()
s.muteAtEdges = true; s.clickOnMomentum = true; s.clickWithoutInfo = false

func capture(_ name: String, _ view: NSView, chrome window: NSWindow? = nil) {
    let target = (window?.contentView?.superview) ?? view
    target.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return }
    target.cacheDisplay(in: target.bounds, to: rep)
    let url = out.appendingPathComponent(name + ".png")
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    print("wrote", url.lastPathComponent, Int(rep.size.width), "x", Int(rep.size.height))
}

func show<V: View>(_ root: V, size: NSSize, title: String? = nil, chrome: Bool) -> (NSWindow, NSView) {
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: size),
                     styleMask: chrome ? [.titled, .closable] : [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .darkAqua)
    w.contentView = host
    if let title { w.title = title }
    w.backgroundColor = chrome ? .windowBackgroundColor : .clear
    app.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    return (w, host)
}

// Menu bar panel (sits on a solid dark backdrop here; in the app it is a frosted material).
do {
    let (w, host) = show(MenuContent(openSettings: {}).environment(\.colorScheme, .dark), size: NSSize(width: 360, height: 430), chrome: false)
    host.frame.size = host.fittingSize
    w.setContentSize(host.fittingSize)
    capture("menu-panel", host)
    w.orderOut(nil)
}

// Settings window, one image per tab.
let tabs = ["sound", "behavior", "haptics", "visualizer"]
let (sw, shost) = show(SettingsView(), size: NSSize(width: 480, height: 480), title: "Scrollo Settings", chrome: true)
for (i, name) in tabs.enumerated() {
    SettingsNav.shared.tab = i
    RunLoop.current.run(until: Date().addingTimeInterval(0.9))
    // The tab bar is drawn by the system, so grab the real on-screen window instead of re-drawing it.
    let url = out.appendingPathComponent("settings-" + name + ".png")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", String(sw.windowNumber), url.path]
    try? p.run(); p.waitUntilExit()
    print("captured", url.lastPathComponent, p.terminationStatus)
}
_ = shost
sw.orderOut(nil)
print("done")
