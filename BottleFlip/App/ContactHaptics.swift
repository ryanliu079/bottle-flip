#if os(iOS)
import CoreHaptics
import UIKit
#endif
import Foundation

@MainActor
final class ContactHaptics {
    #if os(iOS)
    private var engine: CHHapticEngine?
    private var players: [any CHHapticPatternPlayer] = []
    private let fallback = UIImpactFeedbackGenerator(style: .heavy)
    #endif
    #if DEBUG
    private(set) var contacts = 0
    private(set) var bodyHits = 0
    private(set) var patternsStarted = 0
    var supported: Bool {
        #if os(iOS)
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #else
        return false
        #endif
    }
    #endif

    init() {
        #if os(iOS)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.players.removeAll()
                try? self?.engine?.start()
            }
        }
        #endif
    }

    func prepare() {
        #if os(iOS)
        stopPlayers()
        try? engine?.start()
        fallback.prepare()
        #endif
    }

    func contact(_ contact: BottleTableContact) {
        #if DEBUG
        contacts += 1
        if contact.part == .body && !contact.first { bodyHits += 1 }
        #endif
        #if os(iOS)
        let strong = contact.first || contact.part == .body
        let intensity = Float(min(1, max(strong ? 0.85 : 0.15, contact.energy)))
        let sharpness: Float = contact.part == .body ? 0.40 : contact.part == .cap ? 0.90 : 0.70
        guard let engine else { fallback.impactOccurred(intensity: CGFloat(intensity)); return }
        do {
            try engine.start()
            let duration = strong ? 0.22 : 0.065
            var events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    .init(parameterID: .hapticIntensity, value: intensity),
                    .init(parameterID: .hapticSharpness, value: sharpness)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    .init(parameterID: .hapticIntensity, value: intensity * (strong ? 0.55 : 0.28)),
                    .init(parameterID: .hapticSharpness, value: 0.16),
                    .init(parameterID: .decayTime, value: Float(duration)),
                    .init(parameterID: .releaseTime, value: Float(duration * 0.5))
                ], relativeTime: 0.006, duration: duration)
            ]
            if strong {
                // Reflections through the plastic and water give the initial shock texture.
                for (time, level) in [(0.035, Float(0.30)), (0.080, Float(0.12))] {
                    events.append(.init(eventType: .hapticTransient, parameters: [
                        .init(parameterID: .hapticIntensity, value: intensity * level),
                        .init(parameterID: .hapticSharpness, value: 0.32)
                    ], relativeTime: time))
                }
            }
            let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 1),
                .init(relativeTime: duration * 0.25, value: 0.8),
                .init(relativeTime: duration * 0.65, value: 0.3),
                .init(relativeTime: duration + 0.006, value: 0)
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: events, parameterCurves: [curve])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            players.append(player)
            if players.count > 8 { players.removeFirst() }
            #if DEBUG
            patternsStarted += 1
            #endif
        } catch {
            fallback.impactOccurred(intensity: CGFloat(intensity))
        }
        #endif
    }

    func stop() {
        #if os(iOS)
        stopPlayers()
        engine?.stop(completionHandler: nil)
        #endif
    }
    #if os(iOS)
    private func stopPlayers() {
        for player in players { try? player.stop(atTime: 0) }
        players.removeAll()
    }
    #endif
}
