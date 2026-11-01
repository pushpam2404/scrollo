import AppKit
import ApplicationServices

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    if let refcon {
        Unmanaged<ScrollMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

/// NSLog output is redacted as <private>, so diagnostics go to a plain file.
func dlog(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Scrollo.log")
    if let sz = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, sz > 300_000 { try? FileManager.default.removeItem(at: url) }
    let line = "\(Date()) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

final class ScrollMonitor: ObservableObject {
    static let shared = ScrollMonitor()
    @Published private(set) var running = false
    /// Set by Diagnostics so its synthetic scrolls don't play sounds.
    var probeSilence = false
    private(set) var probeClicks = 0

    /// Used by the docs renderer so screenshots show the normal (permission granted) state.
    func markRunningForDocs() { running = true }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let settings = Settings.shared
    private var acc = 0.0
    private var lastClick = Date.distantPast
    private let axQueue = DispatchQueue(label: "scrollo.ax", qos: .userInteractive)
    private let probe = ScrollProbe()
    private var lastSample = Date.distantPast
    /// At most one background sample is queued at a time, so a slow app can't build up a backlog.
    private var samplePending = false

    var trusted: Bool { AXIsProcessTrusted() }

    func promptForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        guard tap == nil else { return }
        guard trusted else { dlog("waiting: AXIsProcessTrusted=false"); return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: tapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            dlog("tapCreate failed (accessibility=\(trusted), inputMonitoring=\(CGPreflightListenEventAccess()))")
            return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        running = true
        dlog("tap installed")
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            if let t = self?.tap { CGEvent.tapEnable(tap: t, enable: true) }
        }
    }

    func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        guard type == .scrollWheel, settings.enabled else { return }

        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        if momentum && !settings.clickOnMomentum { return }

        let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let loc = event.location
        let mustMove = settings.muteAtEdges
        // Vertical scroll direction as the event reports it (0 when the scroll is mostly horizontal). What the
        // sign means for a given app is learned by the probe, not assumed.
        let lineDy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let vy = abs(dy) > 0 ? dy : lineDy
        let dir = abs(dx) > abs(vy) ? 0 : (vy > 0 ? 1 : (vy < 0 ? -1 : 0))

        // Watch the content's scroll position (throttled) so clicks only follow real movement.
        if mustMove {
            let now = Date()
            if now.timeIntervalSince(lastSample) >= 0.025, !samplePending {
                lastSample = now
                samplePending = true
                axQueue.async { [weak self, probe] in
                    probe.sample(at: loc, dySign: dir, continuous: continuous)
                    DispatchQueue.main.async { self?.samplePending = false }
                }
            }
        }

        var clicks = 0
        if continuous {
            acc += abs(dy) + abs(dx)
            let step = max(8, settings.spacing)
            clicks = min(3, Int(acc / step))
            acc -= Double(clicks) * step
            if acc > step { acc = 0 }
        } else {
            let lines = max(abs(event.getDoubleValueField(.scrollWheelEventDeltaAxis1)),
                            abs(event.getDoubleValueField(.scrollWheelEventDeltaAxis2)))
            clicks = lines > 0 ? min(4, max(1, Int(lines.rounded()))) : 0
        }
        guard clicks > 0 else { return }

        let enqueued = Date()
        axQueue.async { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince(enqueued) >= 0.3 {   // stale: a slow app held the queue up
                if self.settings.debugEdge { dlog("dropped a stale click decision (\(Int(Date().timeIntervalSince(enqueued) * 1000)) ms old)") }
                return
            }
            defer {
                let ms = Date().timeIntervalSince(enqueued) * 1000
                if ms > 60, self.settings.debugEdge { dlog("slow decision: \(Int(ms)) ms (queue wait + probe)") }
            }
            if mustMove {
                self.probe.sample(at: loc, dySign: dir, continuous: continuous)
                // Only apps that report their scroll position can be judged; elsewhere stay quiet.
                if !self.settings.clickWithoutInfo && !self.probe.hasUsableInfo { return }
                guard self.probe.shouldClick(), !self.probe.overDesktop(loc) else { return }
            }
            DispatchQueue.main.async { self.fire(clicks) }
        }
    }

    private func fire(_ n: Int) {
        guard !probeSilence else { probeClicks += n; return }
        for i in 0..<n {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012 * Double(i)) { [self] in
                let now = Date()
                guard now.timeIntervalSince(lastClick) > 0.006 else { return }
                lastClick = now
                AudioPlayer.shared.play()
                Haptics.tap()
                Visualizer.shared.pulse()
            }
        }
    }
}
