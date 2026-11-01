import AVFoundation
import CoreAudio

struct OutputDevice: Identifiable, Hashable {
    let id: String   // CoreAudio UID
    let name: String
    let deviceID: AudioDeviceID
}

enum AudioDevices {
    private static func address(_ sel: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &cf) == noErr, let s = cf else { return nil }
        return s.takeRetainedValue() as String
    }

    private static func hasOutput(_ dev: AudioDeviceID) -> Bool {
        var a = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    static func list() -> [OutputDevice] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return OutputDevice(id: uid, name: name, deviceID: id)
        }
    }

    static func defaultOutput() -> AudioDeviceID? {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }
}

final class AudioPlayer {
    static let shared = AudioPlayer()
    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var next = 0
    private let settings = Settings.shared
    private var started = false
    private var idleWork: DispatchWorkItem?
    private var plays = 0
    private var pinned = false
    /// Bumped whenever the engine (re)starts. AVAudioPlayerNode.isPlaying can stay true after a restart
    /// while producing no sound, so each node is explicitly re-armed once per generation.
    private var generation = 0
    private var nodeGen: [Int] = []
    private var lastStart = Date.distantPast
    private var refreshWork: DispatchWorkItem?

    init() {
        for _ in 0..<8 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: SoundBank.format)
            nodes.append(n)
            nodeGen.append(-1)
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.scheduleRefresh()
        }
        // Device list or system default changed: fall back / follow default.
        for sel in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
                self?.scheduleRefresh()
            }
        }
    }

    func start() { refreshRoute() }

    /// Device changes arrive in bursts (and our own restart triggers more), so coalesce them and
    /// ignore echoes of our own restart.
    private func scheduleRefresh() {
        if Date().timeIntervalSince(lastStart) < 0.8 { return }
        refreshWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refreshRoute() }
        refreshWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    /// (Re)apply the chosen output device (or the system default) and restart the engine.
    func refreshRoute() {
        let devices = AudioDevices.list()
        // On System Default let AVAudioEngine follow the system by itself; only pin a device when one is
        // chosen (or to release an earlier pin).
        var target = devices.first { $0.id == settings.outputUID }?.deviceID
        if target == nil && pinned { target = AudioDevices.defaultOutput() }
        engine.stop()
        if var dev = target, let au = engine.outputNode.audioUnit {
            let r = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                         &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
            pinned = !settings.outputUID.isEmpty
            if r != noErr { dlog("set output device failed: \(r)") }
        }
        dlog("route: chosen=\(settings.outputUID.isEmpty ? "default" : settings.outputUID) target=\(String(describing: target)) devices=\(devices.map { $0.name })")
        engine.prepare()
        do {
            try engine.start()
            started = true
            generation += 1
            lastStart = Date()
            dlog("engine started, running=\(engine.isRunning) outFormat=\(engine.outputNode.outputFormat(forBus: 0))")
            idleWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.engine.pause() }
            idleWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
        } catch {
            started = false
            dlog("engine.start failed: \(error)")
        }
    }

    func play() {
        guard started else { dlog("play skipped: engine not started"); return }
        // The engine is paused after a few idle seconds (saves CPU); wake it on demand.
        if !engine.isRunning {
            do { try engine.start() } catch { dlog("engine.start failed on wake: \(error)"); return }
            generation += 1
            lastStart = Date()
        }
        // Starting a player node on a stopped engine raises an Objective-C exception, so never do it.
        guard engine.isRunning else { return }
        idleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.engine.pause() }
        idleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
        let bufs = SoundBank.buffers(for: settings.soundID)
        guard !bufs.isEmpty else { dlog("play skipped: no buffers for \(settings.soundID)"); return }
        let i = next
        let node = nodes[i]
        next = (next + 1) % nodes.count
        engine.mainMixerNode.outputVolume = Float(settings.volume)
        plays += 1
        if plays <= 40 { dlog("play #\(plays) \(settings.soundID) frames=\(bufs[0].frameLength) engineRunning=\(engine.isRunning) vol=\(engine.mainMixerNode.outputVolume)") }
        if nodeGen[i] != generation { node.stop(); node.play(); nodeGen[i] = generation }
        node.scheduleBuffer(bufs.randomElement()!, at: nil, options: .interrupts)
    }
}
