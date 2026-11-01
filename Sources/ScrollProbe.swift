import AppKit
import ApplicationServices

/// Decides whether a scroll gesture is actually moving the content under the pointer, using the scroll position the
/// app reports through Accessibility. Nothing here assumes which direction is "up": the relationship between scroll
/// direction and position is learned from the app, because it depends on natural-scrolling settings and the app.
/// All methods run on one serial queue.
final class ScrollProbe {
    /// bar: a real vertical scroll bar (value 0...1). content: no usable bar, so the scrolled content's own
    /// frame (Word reports a dummy bar but its pages move live).
    private enum Source { case bar(AXUIElement, pid_t), content(AXUIElement, pid_t) }
    private enum Kind { case unknown, scrollable(Source) }

    private var kind: Kind = .unknown
    private var desc = ""
    private var appID = ""
    private var targetPoint = CGPoint(x: -1e6, y: -1e6)
    private var targetTime = Date.distantPast
    /// The scroll area behind the current target, reused while the pointer stays inside it.
    private var areaEl: AXUIElement?
    private var areaPid: pid_t = 0
    private var readFailures = 0
    /// One element of the scrolled content whose position is watched: a single Accessibility call per sample.
    private var contentAnchor: AXUIElement?
    private var slowReads = 0

    private var lastPos: Double?
    private var lastSampleTime = Date.distantPast
    private var gestureStart = Date.distantPast
    private var lastChange = Date.distantPast
    private var dySign = 0
    private var continuous = true

    /// A spot where scrolling in some direction went nowhere, so the same push there is silent immediately.
    private var blockedPos: Double?
    private var blockedSigns = Set<Int>()
    /// Content-frame sources only count once their position has been seen to change.
    private var trustedContent = Set<pid_t>()
    /// Bundle IDs of apps whose content position has been seen to change, remembered across launches.
    private var trustedApps: Set<String>
    /// "bundle|t" (trackpad) or "bundle|m" (mouse) -> the scroll direction sign that moves a bar value toward 1.
    private var polarity: [String: Int]
    private var polCandidate: (key: String, value: Int)?

    private var lastVerdict: Bool?
    private var windowCache: (time: Date, point: CGPoint, value: (pid: pid_t, layer: Int)?)?

    init() {
        // Bound every Accessibility call so one unresponsive app can't stall the queue.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        polarity = (UserDefaults.standard.dictionary(forKey: "polarity") as? [String: Int]) ?? [:]
        trustedApps = Set(UserDefaults.standard.stringArray(forKey: "trustedContentApps") ?? [])
    }

    // MARK: Decision

    func shouldClick() -> Bool { verdict().click }

    /// The app reports a scroll position that has proven reliable (a bar, or content frames seen to move).
    var hasUsableInfo: Bool {
        guard case .scrollable(let src) = kind else { return false }
        return isTrusted(src)
    }

    private func eps(_ s: Source) -> Double { if case .bar = s { return 1e-7 } else { return 0.5 } }
    private var polKey: String { "\(appID)|\(continuous ? "t" : "m")" }

    private func isTrusted(_ s: Source) -> Bool {
        switch s {
        case .bar: return true
        case .content(_, let pid): return trustedContent.contains(pid) || trustedApps.contains(appID)
        }
    }

    private func verdict() -> (click: Bool, reason: String) {
        guard case .scrollable(let src) = kind, isTrusted(src) else { return (true, "no usable scroll info") }
        guard dySign != 0 else { return (true, "no vertical direction") }
        if let pos = lastPos {
            if let bp = blockedPos, abs(bp - pos) <= eps(src), blockedSigns.contains(dySign) { return (false, "blocked here (\(dySign))") }
            if case .bar = src, let s1 = polarity[polKey] {
                let towardOne = dySign == s1
                if (towardOne && pos >= 0.9995) || (!towardOne && pos <= 0.0005) { return (false, "at edge pos=\(String(format: "%.4f", pos))") }
            }
        }
        let now = Date()
        if now.timeIntervalSince(gestureStart) > 0.25 && now.timeIntervalSince(lastChange) > 0.25 { return (false, "position not changing") }
        return (true, "moving")
    }

    // MARK: Sampling

    func sample(at p: CGPoint, dySign dir: Int, continuous cont: Bool) {
        let now = Date()
        if now.timeIntervalSince(lastSampleTime) > 0.4 { gestureStart = now; lastChange = now; lastPos = nil }   // new gesture
        lastSampleTime = now
        if dir != 0 { dySign = dir }
        continuous = cont
        if now.timeIntervalSince(targetTime) > 1.0 || hypot(p.x - targetPoint.x, p.y - targetPoint.y) > 24 { retarget(p, now) }
        guard case .scrollable(let src) = kind else { logVerdict(); return }
        // An app busy rendering can miss a lookup deadline; only a run of failures counts as "no info".
        let t0 = Date()
        let reading = read(src)
        let took = Date().timeIntervalSince(t0)
        if took > 0.04, Settings.shared.debugEdge, (slowReads < 20) { slowReads += 1; dlog("probe slow read: \(Int(took * 1000)) ms for \(desc)") }
        guard let pos = reading else {
            readFailures += 1
            if readFailures == 1 || readFailures == 6, Settings.shared.debugEdge { dlog("probe read failed x\(readFailures) for \(desc)") }
            if readFailures >= 6 { kind = .unknown }
            logVerdict(); return
        }
        readFailures = 0

        if let last = lastPos, abs(pos - last) > eps(src) {
            lastChange = now
            if let bp = blockedPos, abs(pos - bp) > eps(src) { blockedPos = nil; blockedSigns = [] }   // moved off the blocked spot
            if case .content(_, let pid) = src, !isTrusted(src) {
                trustedContent.insert(pid)
                trustedApps.insert(appID)
                UserDefaults.standard.set(Array(trustedApps), forKey: "trustedContentApps")
                dlog("probe \(desc): content moves while scrolling, now trusted (remembered)")
            }
            if case .bar = src, dySign != 0 { learnPolarity(delta: pos - last) }
        }
        if lastPos == nil, Settings.shared.debugEdge { dlog("probe first read in gesture: \(desc) pos=\(pos) dir=\(dySign) trusted=\(isTrusted(src))") }
        lastPos = pos

        // A gesture that goes nowhere marks this spot as blocked for this direction.
        if dySign != 0, isTrusted(src), now.timeIntervalSince(gestureStart) > 0.25, now.timeIntervalSince(lastChange) > 0.25 {
            if blockedPos == nil || abs(blockedPos! - pos) > eps(src) { blockedPos = pos; blockedSigns = [] }
            blockedSigns.insert(dySign)
        }
        logVerdict()
    }

    /// Two agreeing observations of (scroll direction, position change) fix the polarity for this app and device.
    private func learnPolarity(delta: Double) {
        let cand = (delta > 0 ? 1 : -1) * dySign
        let key = polKey
        if let c = polCandidate, c.key == key, c.value == cand, polarity[key] != cand {
            polarity[key] = cand
            UserDefaults.standard.set(polarity, forKey: "polarity")
            dlog("probe learned polarity \(key) = \(cand)")
        }
        polCandidate = (key, cand)
    }

    private func logVerdict() {
        guard Settings.shared.debugEdge else { return }
        let v = verdict()
        if v.click != lastVerdict { lastVerdict = v.click; dlog("probe \(desc) -> \(v.click ? "click" : "silent") (\(v.reason))") }
    }

    private func retarget(_ p: CGPoint, _ now: Date) {
        // Still in the same scroll area (and that app's window is still on top there): nothing to look up again.
        // An unreadable frame means the app is busy, so keep the target rather than lose it.
        if case .scrollable = kind, let a = areaEl, topWindow(at: p)?.pid == areaPid {
            if let f = frame(a), !f.contains(p) {} else { targetPoint = p; targetTime = now; return }
        }
        let (k, d) = classify(p)
        // A failed lookup near the previous area (a timeout, or a broken accessibility chain) must not erase it.
        if case .unknown = k, case .scrollable = kind, topWindow(at: p)?.pid == areaPid,
           hypot(p.x - targetPoint.x, p.y - targetPoint.y) < 150 {
            targetPoint = p; targetTime = now; return
        }
        if !sameSource(k) { lastPos = nil; lastChange = now; blockedPos = nil; blockedSigns = [] }
        if d != desc, Settings.shared.debugEdge { dlog("probe target: \(d)") }
        kind = k; desc = d; targetPoint = p; targetTime = now
    }

    private func sameSource(_ new: Kind) -> Bool {
        switch (kind, new) {
        case (.scrollable(.bar(let a, _)), .scrollable(.bar(let b, _))): return CFEqual(a, b)
        case (.scrollable(.content(let a, _)), .scrollable(.content(let b, _))): return CFEqual(a, b)
        default: return false
        }
    }

    private func read(_ s: Source) -> Double? {
        switch s {
        case .bar(let bar, _): return (attr(bar, kAXValueAttribute) as? NSNumber)?.doubleValue
        case .content(let area, _): return contentTop(area)
        }
    }

    // MARK: Accessibility lookups

    /// A real vertical scroll bar: it reports a value and is enabled with a non-empty frame (Word's is a dummy).
    private func usableBar(of area: AXUIElement) -> AXUIElement? {
        guard let bar = attr(area, kAXVerticalScrollBarAttribute) else { return nil }
        let b = bar as! AXUIElement
        guard (attr(b, kAXValueAttribute) as? NSNumber) != nil else { return nil }
        if let en = attr(b, kAXEnabledAttribute) as? NSNumber, !en.boolValue { return nil }
        if let f = frame(b), f.width <= 0 || f.height <= 0 { return nil }
        return b
    }

    /// Top of one element of the scrolled content, in screen coordinates (it shifts as the content scrolls).
    /// The element is picked once per scroll area and then re-read cheaply.
    private func contentTop(_ area: AXUIElement) -> Double? {
        if let a = contentAnchor, let y = positionY(a) { return y }
        let kids = (attr(area, "AXVisibleChildren") as? [AXUIElement]) ?? (attr(area, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        for k in kids.prefix(4) {
            guard let f = frame(k), f.height > 0 else { continue }
            contentAnchor = k
            return Double(f.minY)
        }
        return nil
    }

    private func positionY(_ el: AXUIElement) -> Double? {
        guard let pv = attr(el, kAXPositionAttribute) else { return nil }
        var pt = CGPoint.zero
        return AXValueGetValue(pv as! AXValue, .cgPoint, &pt) ? Double(pt.y) : nil
    }

    private func frame(_ el: AXUIElement) -> CGRect? {
        guard let pv = attr(el, kAXPositionAttribute), let sv = attr(el, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &pt), AXValueGetValue(sv as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    private func classify(_ p: CGPoint) -> (Kind, String) {
        areaEl = nil
        if isSkippedBrowser(at: p) { return (.unknown, "browser (not probed)") }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.08)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(p.y), &hit) == .success, var el = hit else {
            return (.unknown, "no element")
        }
        let start = el
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        appID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid\(pid)"
        AXUIElementSetMessagingTimeout(el, 0.08)
        for _ in 0..<80 {
            if (attr(el, kAXRoleAttribute) as? String) == "AXScrollArea", let r = source(for: el, pid: pid) { return r }
            guard let parent = attr(el, kAXParentAttribute) else { break }
            el = parent as! AXUIElement
        }
        // Some elements (Preview's PDF text, for one) have a broken parent chain. Search their window instead.
        if let w = (attr(start, kAXWindowAttribute) ?? attr(start, kAXTopLevelUIElementAttribute)) {
            if let area = innermostScrollArea(in: w as! AXUIElement, at: p), let r = source(for: area, pid: pid) {
                return (r.0, r.1 + " (via window)")
            }
        }
        return (.unknown, "\(appID) no scroll info")
    }

    private func source(for area: AXUIElement, pid: pid_t) -> (Kind, String)? {
        contentAnchor = nil
        if let bar = usableBar(of: area) { areaEl = area; areaPid = pid; return (.scrollable(.bar(bar, pid)), "\(appID) scrollbar") }
        if contentTop(area) != nil {
            areaEl = area; areaPid = pid
            // An app that publishes its visible children keeps them up to date as it scrolls.
            if attr(area, "AXVisibleChildren") != nil { trustedContent.insert(pid) }
            return (.scrollable(.content(area, pid)), "\(appID) content-frame")
        }
        return nil
    }

    /// Smallest scroll area under the point, found by walking down from the window and only entering elements
    /// whose frame contains the point (keeps the number of Accessibility calls small).
    private func innermostScrollArea(in window: AXUIElement, at p: CGPoint) -> AXUIElement? {
        var best: (el: AXUIElement, area: CGFloat)?
        var visited = 0
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 9, visited < 250 else { return }
            visited += 1
            if (attr(el, kAXRoleAttribute) as? String) == "AXScrollArea", let f = frame(el), f.contains(p) {
                let a = f.width * f.height
                if best == nil || a < best!.area { best = (el, a) }
            }
            for k in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                if let f = frame(k), !f.contains(p) { continue }
                walk(k, depth + 1)
            }
        }
        walk(window, 0)
        return best?.el
    }

    private func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    // MARK: Window list (public API, no permission needed)

    /// Owner and layer of the topmost on-screen window under the point (Scrollo's own windows are skipped).
    private func topWindow(at p: CGPoint) -> (pid: pid_t, layer: Int)? {
        if let c = windowCache, Date().timeIntervalSince(c.time) < 0.15, hypot(c.point.x - p.x, c.point.y - p.y) < 6 { return c.value }
        var result: (pid_t, Int)?
        let me = ProcessInfo.processInfo.processIdentifier
        for w in (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? [] {
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(p) else { continue }
            result = (pid, w[kCGWindowLayer as String] as? Int ?? 0)
            break
        }
        windowCache = (Date(), p, result)
        return result
    }

    /// True when the topmost window under the point is a desktop-level window (the empty desktop).
    func overDesktop(_ p: CGPoint) -> Bool { (topWindow(at: p)?.layer ?? 0) < 0 }

    /// Chromium-based browsers switch on a full accessibility mode (which also pins the full-screen toolbar open) as
    /// soon as they are probed, and don't report scroll position anyway. They are never queried.
    private static let skippedPrefixes = ["com.brave.", "com.google.Chrome", "org.chromium.", "com.microsoft.edgemac",
                                          "com.vivaldi.", "com.operasoftware.", "company.thebrowser."]

    private func isSkippedBrowser(at p: CGPoint) -> Bool {
        guard let pid = topWindow(at: p)?.pid, let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return Self.skippedPrefixes.contains { id.hasPrefix($0) }
    }
}
