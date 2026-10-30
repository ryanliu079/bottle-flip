import AVFoundation
#if SWIFT_PACKAGE
import GameCore
#endif

/// At most two streamed players: the current loop and the outgoing crossfade.
@MainActor
final class SoundtrackPlayer: NSObject {
    private var player: AVAudioPlayer?
    private var outgoing: AVAudioPlayer?
    private var cue: JourneySoundtrack?
    private var active = false
    private var interrupted = false
    private var mix: Float = 1
    private var duck: Float = 1
    private var fadeTask: Task<Void, Never>?
    private var duckTask: Task<Void, Never>?
    private let gain: Float = 0.60
    #if DEBUG
    private var loadCount = 0
    #endif

    override init() {
        super.init()
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(interruptionChanged(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mediaServicesReset(_:)),
                                               name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        #endif
    }

    static func url(for cue: JourneySoundtrack) -> URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: cue.resourceName, withExtension: "caf", subdirectory: "Music")
    }

    func select(stage: Int) {
        let next = JourneySoundtrack.cue(at: stage)
        guard cue != next || player == nil else { return }
        guard let url = Self.url(for: next), let incoming = try? AVAudioPlayer(contentsOf: url) else {
            // A missing cue must not leave another kingdom's music playing.
            stopTransition()
            player?.stop()
            player = nil
            cue = nil
            return
        }
        incoming.numberOfLoops = -1
        incoming.volume = 0
        incoming.prepareToPlay()
        // The three arrangements share a form and tempo, so preserve their musical position.
        if cue?.chapterID == next.chapterID, let player {
            incoming.currentTime = player.currentTime.truncatingRemainder(dividingBy: incoming.duration)
        }
        stopTransition()
        outgoing = player
        player = incoming
        cue = next
        #if DEBUG
        loadCount += 1
        #endif
        if active && !interrupted {
            incoming.play()
            fadeIn()
        } else {
            stopTransition()
            mix = 1
            applyVolumes()
        }
    }

    func setActive(_ value: Bool) {
        active = value
        if value && !interrupted { resume() } else { suspend() }
    }

    private func resume() {
        guard let player, !player.isPlaying else { return }
        player.volume = 0
        if player.play() { fadeIn() }
    }

    private func suspend() {
        stopTransition()
        duckTask?.cancel()
        duckTask = nil
        duck = 1
        player?.pause()
        mix = 1
        applyVolumes()
    }

    private func stopTransition() {
        fadeTask?.cancel()
        fadeTask = nil
        outgoing?.stop()
        outgoing = nil
    }

    private func fadeIn() {
        fadeTask?.cancel()
        mix = 0
        applyVolumes()
        fadeTask = Task { @MainActor [weak self] in
            let start = ContinuousClock.now
            while true {
                guard !Task.isCancelled, let self else { return }
                self.mix = Self.fadeProgress(since: start, duration: 1.2)
                self.applyVolumes()
                if self.mix >= 1 { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            self?.outgoing?.stop()
            self?.outgoing = nil
            self?.fadeTask = nil
        }
    }

    func duckForCelebration() {
        guard active, !interrupted else { return }
        duckTask?.cancel()
        duck = 0.42
        applyVolumes()
        duckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            let start = ContinuousClock.now
            while true {
                guard let self, !Task.isCancelled else { return }
                let progress = Self.fadeProgress(since: start, duration: 0.6)
                self.duck = progress >= 1 ? 1 : 0.42 + 0.58 * progress
                self.applyVolumes()
                if progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            self?.duckTask = nil
        }
    }

    /// Render work can delay a timer tick; fades follow elapsed time rather than tick counts.
    private static func fadeProgress(since start: ContinuousClock.Instant, duration: Double) -> Float {
        let elapsed = start.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return min(1, Float(seconds / duration))
    }

    private func applyVolumes() {
        player?.volume = gain * duck * mix
        outgoing?.volume = gain * duck * (1 - mix)
    }

    #if os(iOS)
    @objc private func interruptionChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            interrupted = true
            suspend()
        } else {
            interrupted = false
            let options = AVAudioSession.InterruptionOptions(rawValue:
                notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if active && options.contains(.shouldResume) { resume() }
        }
    }

    @objc private func mediaServicesReset(_ notification: Notification) {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        let stageCue = cue
        suspend()
        player = nil
        cue = nil
        interrupted = false
        if let stage = (1...WorldJourney.stageCount).first(where: { JourneySoundtrack.cue(at: $0) == stageCue }) {
            select(stage: stage)
        }
    }
    #endif

    #if DEBUG
    var snapshot: [String: Any] {
        ["cue": cue?.resourceName ?? "", "playing": player?.isPlaying ?? false,
         "time": player?.currentTime ?? 0, "duration": player?.duration ?? 0,
         "loops": player?.numberOfLoops ?? 0, "loads": loadCount,
         "outgoing": outgoing != nil, "gain": player?.volume ?? 0, "duck": duck]
    }
    func seekNearLoopEnd() { if let player { player.currentTime = max(0, player.duration - 0.2) } }
    #endif
}
