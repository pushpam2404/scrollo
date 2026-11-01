import AppKit

/// Trackpad taps. Uses MultitouchSupport's actuator (the Taptic Engine) for five distinct levels and
/// falls back to the public NSHapticFeedbackManager if that private framework or any symbol is missing.
enum Haptics {
    static let levelNames = ["Whisper", "Light", "Medium", "Firm", "Heavy"]

    /// (actuation ID, repeats) per level. IDs 1...6 are the built-in click shapes, higher = stronger.
    private static let table: [(id: Int32, repeats: Int)] = [(1, 1), (2, 1), (4, 1), (6, 1), (6, 2)]

    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetID = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias ActCreate = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias ActOpen = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ActActuate = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32

    private static var actuators: [UnsafeMutableRawPointer] = []
    private static var actuate: ActActuate?
    private static var prepared = false

    private static func prepare() {
        guard !prepared else { return }
        prepared = true
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let l = dlsym(h, "MTDeviceCreateList"), let g = dlsym(h, "MTDeviceGetDeviceID"),
              let c = dlsym(h, "MTActuatorCreateFromDeviceID"), let o = dlsym(h, "MTActuatorOpen"),
              let a = dlsym(h, "MTActuatorActuate") else {
            dlog("haptics: MultitouchSupport unavailable, using NSHapticFeedbackManager")
            return
        }
        let list = unsafeBitCast(l, to: CreateList.self)
        let getID = unsafeBitCast(g, to: GetID.self)
        let create = unsafeBitCast(c, to: ActCreate.self)
        let open = unsafeBitCast(o, to: ActOpen.self)
        guard let devs = list()?.takeRetainedValue() else { return }
        for i in 0..<CFArrayGetCount(devs) {
            var devID: UInt64 = 0
            guard let dev = CFArrayGetValueAtIndex(devs, i), getID(dev, &devID) == 0, devID != 0,
                  let act = create(devID), open(act) == 0 else { continue }
            actuators.append(act)
        }
        actuate = unsafeBitCast(a, to: ActActuate.self)
        dlog("haptics: \(actuators.count) actuator(s) opened")
    }

    static func tap() {
        let s = Settings.shared
        guard s.haptics else { return }
        fire(level: s.hapticStrength)
    }

    static func fire(level: Int) {
        prepare()
        let lv = max(0, min(table.count - 1, level))
        if let actuate, !actuators.isEmpty {
            let (id, repeats) = table[lv]
            for r in 0..<repeats {
                let go = { for a in actuators { _ = actuate(a, id, 0, 0, 0) } }
                if r == 0 { go() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.014 * Double(r), execute: go) }
            }
        } else {
            let p: [NSHapticFeedbackManager.FeedbackPattern] = [.alignment, .alignment, .generic, .levelChange, .levelChange]
            NSHapticFeedbackManager.defaultPerformer.perform(p[lv], performanceTime: .now)
        }
    }

    /// Plays every level in order so the differences can be felt back to back.
    static func sweep() {
        for lv in 0..<table.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(lv)) { fire(level: lv) }
        }
    }
}
