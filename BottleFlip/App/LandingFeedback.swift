import AVFoundation
#if os(iOS)
import UIKit
#endif

@MainActor
final class LandingFeedback {
    private var player: AVAudioPlayer?
    private var waterPlayer: AVAudioPlayer?
    private var celebrationPlayer: AVAudioPlayer?
    private var bodyPlayer: AVAudioPlayer?
    private var firstPart = BottleTableContact.Part.base
    private let haptics = ContactHaptics()
    private var usesRecordedImpact = false
    #if DEBUG
    private(set) var impactCount = 0
    private(set) var playbackCount = 0
    private(set) var celebrationCount = 0
    private(set) var bodyPlaybackCount = 0
    var contactCounts: (contacts: Int, body: Int, patterns: Int, supported: Bool) {
        (haptics.contacts, haptics.bodyHits, haptics.patternsStarted, haptics.supported)
    }
    var recordedSoundsReady: Bool { usesRecordedImpact && waterPlayer != nil }
    #endif

    init() {
        #if os(iOS)
        // Ambient audio respects the silent switch and mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        #endif
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        if let recording = bundle.url(forResource: "LandingOnWood", withExtension: "wav", subdirectory: "Sounds") {
            player = try? AVAudioPlayer(contentsOf: recording)
            usesRecordedImpact = player != nil
        } else {
            player = try? AVAudioPlayer(data: Self.temporaryWoodTap())
        }
        if let recording = bundle.url(forResource: "WaterSlosh", withExtension: "wav", subdirectory: "Sounds") {
            waterPlayer = try? AVAudioPlayer(contentsOf: recording)
        }
        if let sound = bundle.url(forResource: "Celebration", withExtension: "wav", subdirectory: "Sounds") {
            celebrationPlayer = try? AVAudioPlayer(contentsOf: sound)
            celebrationPlayer?.prepareToPlay()
        }
        if let sound = bundle.url(forResource: "BodyOnWood", withExtension: "wav", subdirectory: "Sounds") {
            bodyPlayer = try? AVAudioPlayer(contentsOf: sound)
            bodyPlayer?.prepareToPlay()
        }
        player?.prepareToPlay()
        bodyPlayer?.prepareToPlay()
        waterPlayer?.prepareToPlay()
    }

    func prepare() {
        player?.prepareToPlay()
        haptics.prepare()
    }

    func impact(strength: Double) {
        let intensity = min(1, max(0.4, 0.45 + strength * 0.5))
        let hitPlayer = firstPart == .body ? bodyPlayer : player
        hitPlayer?.currentTime = 0
        waterPlayer?.stop()
        hitPlayer?.volume = Float(0.45 + intensity * 0.35)
        let played = hitPlayer?.play() == true
        #if DEBUG
        impactCount += 1
        if played { playbackCount += 1 }
        #endif
    }

    func beganThrow(strength: Double) {
        celebrationPlayer?.stop()
        bodyPlayer?.stop()
        waterPlayer?.currentTime = 0
        waterPlayer?.volume = Float(0.18 + min(1, max(0, strength)) * 0.15)
        waterPlayer?.play()
    }
    func contact(_ contact: BottleTableContact) {
        haptics.contact(contact)
        if contact.first { firstPart = contact.part }
        if contact.part == .body && !contact.first {
            player?.stop()
            bodyPlayer?.currentTime = 0
            bodyPlayer?.volume = 0.78
            let played = bodyPlayer?.play() == true
            #if DEBUG
            if played { bodyPlaybackCount += 1 }
            #endif
        }
    }
    func celebrate() {
        celebrationPlayer?.currentTime = 0
        celebrationPlayer?.volume = 0.50
        let played = celebrationPlayer?.play() == true
        #if DEBUG
        if played { celebrationCount += 1 }
        #endif
    }
    func pause() {
        player?.stop(); waterPlayer?.stop(); celebrationPlayer?.stop(); bodyPlayer?.stop()
        haptics.stop()
    }

    /// A short resonant wooden knock until a real bottle-on-table recording is supplied.
    private static func temporaryWoodTap() -> Data {
        let sampleRate = 44_100, count = 7_056
        var data = Data()
        func word(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func integer(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> shift) & 255)) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); integer(UInt32(36 + count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); integer(16)
        word(1); word(1); integer(UInt32(sampleRate)); integer(UInt32(sampleRate * 2)); word(2); word(16)
        data.append(contentsOf: Array("data".utf8)); integer(UInt32(count * 2))
        var seed: UInt32 = 17
        var filtered = 0.0
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            seed = seed &* 1664525 &+ 1013904223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            filtered = filtered * 0.65 + noise * 0.35
            let resonance = (sin(2 * .pi * 145 * time) * 0.48
                + sin(2 * .pi * 370 * time) * 0.20 + sin(2 * .pi * 810 * time) * 0.08) * exp(-time * 34)
            let transient = filtered * 0.45 * exp(-time * 110)
            let attack = min(1, time * 2500)
            let sample = Int16(max(-1, min(1, (resonance + transient) * attack)) * 28000)
            word(UInt16(bitPattern: sample))
        }
        return data
    }
}
