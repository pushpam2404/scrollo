import AppKit
import ApplicationServices

/// Debug tool: write `app=<bundle id>` to ~/Library/Logs/Scrollo.probe and Scrollo activates that app, dumps what its
/// scroll area reports through Accessibility, scrolls it with synthetic events and logs the scroll position after each
/// step. Results go to ~/Library/Logs/Scrollo.log with a PROBE prefix.
enum Diagnostics {
    private static let cmdURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Scrollo.probe")
    private static let queue = DispatchQueue(label: "scrollo.diagnostics")

    static func start() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            guard let cmd = try? String(contentsOf: cmdURL, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(at: cmdURL)
            queue.async { run(cmd) }
        }
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func log(_ s: String) { dlog("PROBE " + s) }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        guard let pv = attr(el, kAXPositionAttribute), let sv = attr(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: p, size: sz)
    }

    private static func run(_ cmd: String) {
        var id = ""
        for line in cmd.split(separator: "\n") where line.hasPrefix("app=") { id = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        if cmd.contains("haptics") {
            log("haptics sweep start (levels 0...4, 0.6s apart)")
            DispatchQueue.main.sync { Haptics.sweep() }
            Thread.sleep(forTimeInterval: 3.5)
            log("haptics sweep finished without crashing")
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { log("\(id): not running"); return }
        log("=== \(id) pid \(app.processIdentifier)")
        _ = DispatchQueue.main.sync { app.activate() }
        Thread.sleep(forTimeInterval: 1.0)

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let wins = attr(axApp, kAXWindowsAttribute) as? [AXUIElement], let win = wins.first, let f = frame(win) else {
            log("no window with a frame"); return
        }
        let pt = CGPoint(x: f.midX, y: f.minY + f.height * 0.6)
        log("window frame \(f) probe point \(pt)")

        // What is under the point, and what do its scroll areas report?
        let sys = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(pt.x), Float(pt.y), &hit) == .success, var el = hit else { log("no element at point"); return }
        var bars: [(String, AXUIElement)] = []
        var firstArea: AXUIElement?
        for depth in 0..<60 {
            let role = attr(el, kAXRoleAttribute) as? String ?? "?"
            if role == "AXScrollArea" {
                if firstArea == nil { firstArea = el }
                var names: CFArray?; AXUIElementCopyAttributeNames(el, &names)
                log("depth \(depth) AXScrollArea attrs=\((names as? [String]) ?? [])")
                for key in [kAXVerticalScrollBarAttribute, kAXHorizontalScrollBarAttribute] {
                    guard let bar = attr(el, key) else { log("  \(key): none"); continue }
                    let b = bar as! AXUIElement
                    var bn: CFArray?; AXUIElementCopyAttributeNames(b, &bn)
                    log("  \(key): value=\(String(describing: attr(b, kAXValueAttribute))) min=\(String(describing: attr(b, kAXMinValueAttribute))) max=\(String(describing: attr(b, kAXMaxValueAttribute))) enabled=\(String(describing: attr(b, kAXEnabledAttribute))) frame=\(String(describing: frame(b)))")
                    log("  \(key) attrs=\((bn as? [String]) ?? [])")
                    if key == kAXVerticalScrollBarAttribute { bars.append(("depth\(depth)", b)) }
                }
            } else if depth < 6 { log("depth \(depth) \(role)") }
            guard let parent = attr(el, kAXParentAttribute) else { break }
            el = parent as! AXUIElement
        }
        func contentSig() -> String {
            guard let a = firstArea else { return "no area" }
            let kids = (attr(a, "AXVisibleChildren") as? [AXUIElement]) ?? (attr(a, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            let fs = kids.prefix(8).compactMap { frame($0) }.filter { $0.height > 0 }
            guard let top = fs.map({ $0.minY }).min(), let bot = fs.map({ $0.maxY }).max() else { return "kids=\(kids.count) no frames" }
            return "kids=\(kids.count) top=\(Int(top)) bottom=\(Int(bot))"
        }
        if bars.isEmpty { log("no vertical scroll bar found; content only: \(contentSig())") }

        func read() -> String { contentSig() + " | " + bars.map { "\($0.0)=" + (((attr($0.1, kAXValueAttribute) as? NSNumber)?.doubleValue).map { String(format: "%.5f", $0) } ?? "nil") }.joined(separator: " ") }
        func post(_ dy: Int32) {
            CGWarpMouseCursorPosition(pt)
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) else { return }
            e.location = pt
            e.post(tap: .cgSessionEventTap)
        }
        ScrollMonitor.shared.probeSilence = true
        defer { ScrollMonitor.shared.probeSilence = false }

        let mon = ScrollMonitor.shared
        func burst(_ dy: Int32, _ n: Int, gap: TimeInterval = 0.03) -> Int {
            let before = mon.probeClicks
            for _ in 0..<n { post(dy); Thread.sleep(forTimeInterval: gap) }
            Thread.sleep(forTimeInterval: 0.25)
            return mon.probeClicks - before
        }
        func rest() { Thread.sleep(forTimeInterval: 0.9) }   // lets the gesture end

        log("start position: \(read())")
        for sign in [Int32(1), Int32(-1)] {
            let name = sign > 0 ? "+dy" : "-dy"
            _ = burst(sign * 120, 70); rest()                                  // drive to one end
            log("end reached with \(name): \(read())")
            let into = burst(sign * 120, 20); rest()                           // keep pushing into the edge
            log("\(name) pushing INTO the edge, 20 events: clicks=\(into) (want ~0)   \(read())")
            var flicks: [Int] = []
            for _ in 0..<4 { flicks.append(burst(sign * 120, 5)); rest() }     // short flicks at the edge
            log("\(name) 4 short flicks at the edge: clicks=\(flicks) (want all ~0)")
            let away = burst(-sign * 120, 20); rest()                          // scroll back off the edge
            log("\(-sign > 0 ? "+dy" : "-dy") moving AWAY from the edge, 20 events: clicks=\(away) (want > 0)   \(read())")
            let mid = burst(-sign * 120, 20); rest()                           // well inside the document
            log("\(-sign > 0 ? "+dy" : "-dy") mid-document, 20 events: clicks=\(mid) (want ~9)   \(read())")
        }
        log("=== done")
    }
}
