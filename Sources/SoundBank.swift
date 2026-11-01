import AVFoundation
import SwiftUI

struct SoundOption: Identifiable {
    let id: String      // also the WAV file name in Resources/Sounds
    let name: String
    let color: Color
}

enum SoundBank {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    static let all: [SoundOption] = [
        .init(id: "softpop", name: "Soft Pop", color: .mint),
        .init(id: "bubble", name: "Bubble", color: .cyan),
        .init(id: "bloop", name: "Bloop", color: .blue),
        .init(id: "cavedrip", name: "Cave Drip", color: .indigo),
        .init(id: "thock", name: "Thock", color: .brown),
        .init(id: "woodclick", name: "Wood Click", color: .orange),
        .init(id: "woodtick", name: "Wood Tick", color: .yellow),
        .init(id: "softclick", name: "Soft Click", color: .teal),
        .init(id: "gumpop", name: "Gum Pop", color: .pink),
        .init(id: "bigpop", name: "Big Pop", color: .purple),
    ]

    static func option(_ id: String) -> SoundOption { all.first { $0.id == id } ?? all[0] }

    private static var cache: [String: [AVAudioPCMBuffer]] = [:]

    /// Three slightly pitch-shifted variants so rapid scrolling doesn't sound machine-gunned.
    static func buffers(for id: String) -> [AVAudioPCMBuffer] {
        if let c = cache[id] { return c }
        guard let url = Bundle.main.url(forResource: id, withExtension: "wav", subdirectory: "Sounds"),
              let file = try? AVAudioFile(forReading: url),
              let src = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: src)) != nil else {
            dlog("failed to load sound \(id)")
            return []
        }
        let b = [0.96, 1.0, 1.04].map { resample(src, ratio: $0) }
        cache[id] = b
        return b
    }

    /// Linear-interpolation resample; ratio > 1 plays faster (higher pitch, shorter).
    private static func resample(_ src: AVAudioPCMBuffer, ratio: Double) -> AVAudioPCMBuffer {
        if ratio == 1 { return src }
        let n = Int(Double(src.frameLength) / ratio)
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        out.frameLength = AVAudioFrameCount(n)
        let s = src.floatChannelData![0], d = out.floatChannelData![0]
        let last = Int(src.frameLength) - 1
        for i in 0..<n {
            let p = Double(i) * ratio
            let i0 = min(Int(p), last), i1 = min(i0 + 1, last)
            let f = Float(p - Double(i0))
            d[i] = s[i0] * (1 - f) + s[i1] * f
        }
        return out
    }
}
