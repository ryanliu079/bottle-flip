#if DEBUG
import AVFoundation
#if SWIFT_PACKAGE
import GameCore
#endif

/// Device/simulator checks use a temporary player, never the saved campaign or mute preference.
@MainActor
final class SoundtrackValidation {
    private weak var model: GameModel?
    init(model: GameModel) { self.model = model }

    func start() {
        Task { @MainActor [weak self] in
            guard let model = self?.model else { return }
            var rows: [[String: Any]] = []
            @MainActor func check(_ name: String, _ passed: Bool) {
                rows.append(["case": name, "passed": passed, "music": model.musicSnapshot])
            }
            @MainActor func playing() -> Bool { model.musicSnapshot["playing"] as? Bool == true }
            @MainActor func time() -> Double { model.musicSnapshot["time"] as? Double ?? -1 }
            @MainActor func loads() -> Int { model.musicSnapshot["loads"] as? Int ?? -1 }
            @MainActor func wait(_ ms: Int = 1500) async { try? await Task.sleep(for: .milliseconds(ms)) }
            model.setMusicEnabled(true)
            model.activate(true)
            model.resetValidation(stageNumber: 41)
            await wait()
            check("Water music plays and loops indefinitely", playing() && model.musicSnapshot["loops"] as? Int == -1)
            let oldLoads = loads(), oldTime = time()
            model.resetValidation(stageNumber: 42)
            await wait(100)
            check("same arrangement continues without restarting", loads() == oldLoads && time() >= oldTime)
            let phase = time()
            model.resetValidation(stageNumber: 44)
            check("new arrangement crossfades at matching musical position",
                  loads() == oldLoads + 1 && abs(time() - phase) < 0.2 && model.musicSnapshot["outgoing"] as? Bool == true)
            await wait()
            check("crossfade releases outgoing player", playing() && model.musicSnapshot["outgoing"] as? Bool == false)
            model.setPaused(true)
            let pausedTime = time()
            await wait(250)
            check("pause freezes playback", !playing() && abs(time() - pausedTime) < 0.05)
            model.setPaused(false)
            await wait(250)
            check("resume keeps playback position", playing() && time() > pausedTime)
            model.setMusicEnabled(false)
            check("mute stops music", !playing())
            model.activate(false)
            model.activate(true)
            check("mute survives background and foreground", !playing())
            model.setMusicEnabled(true)
            await wait(250)
            check("unmute resumes", playing())
            model.activate(false)
            model.resetValidation(stageNumber: 81)
            check("changing chapter in background remains silent", !playing())
            model.activate(true)
            await wait()
            check("Ice piano cue resumes on foreground", playing() && model.musicSnapshot["cue"] as? String == JourneySoundtrack.cue(at: 81).resourceName)
            model.seekMusicNearLoopEnd()
            let loopLoads = loads()
            await wait(600)
            check("actual loop wraps with no reload", playing() && time() < 1 && loads() == loopLoads)
            #if os(iOS)
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            check("audio interruption suspends music", !playing())
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                           AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
            check("permitted interruption recovery resumes music", playing())
            #endif
            model.resetValidation(stageNumber: 1)
            await wait()
            model.launch(strength: model.round.stage.comfortableStrength)
            for _ in 0..<70 {
                await wait(100)
                if !model.isFlying { break }
            }
            check("successful throw keeps music playing and ducks for celebration",
                  model.result == true && playing() && (model.musicSnapshot["duck"] as? Float ?? 1) < 0.5)
            await wait(2600)
            check("music recovers after celebration", playing() && model.musicSnapshot["duck"] as? Float == 1)
            let retryLoads = loads()
            model.continueRound()
            check("next stage in same arrangement preserves player", playing() && loads() == retryLoads)

            // Inspect every bundled cue through the platform decoder, including exact sample count.
            model.activate(false)
            struct Entry: Decodable { let file: String; let firstStage: Int; let frames: Int64; let sampleRate: Double }
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            do {
                let catalogURL = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Music")!
                let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: catalogURL))
                check("catalog has all 36 arrangements", entries.count == 36)
                for entry in entries {
                    let cue = JourneySoundtrack.cue(at: entry.firstStage)
                    guard let url = SoundtrackPlayer.url(for: cue) else { check(entry.file, false); continue }
                    let audio = try AVAudioFile(forReading: url)
                    let player = try AVAudioPlayer(contentsOf: url)
                    check("decode \(entry.file)", audio.length == entry.frames
                          && audio.processingFormat.channelCount == 2 && audio.processingFormat.sampleRate == entry.sampleRate
                          && abs(player.duration - Double(entry.frames) / entry.sampleRate) < 1 / entry.sampleRate
                          && player.prepareToPlay())
                }
            } catch { rows.append(["case": "bundled audio", "passed": false, "error": String(describing: error)]) }
            let report: [String: Any] = ["complete": true, "passed": rows.allSatisfy { $0["passed"] as? Bool == true }, "cases": rows]
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("music-validation.json"), options: .atomic)
            } catch { print("Music validation report failed: \(error)") }
        }
    }
}
#endif
