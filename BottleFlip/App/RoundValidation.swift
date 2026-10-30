#if DEBUG
import Foundation
#if SWIFT_PACKAGE
import GameCore
#endif

/// Exercises the normal model launch/result callback, including recovery from lost scene frames.
@MainActor
final class RoundValidation {
    private weak var model: GameModel?
    init(model: GameModel) { self.model = model }

    func start() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let model else { return }
            var rows: [[String: Any]] = []
            for (offset, expected, direction) in [(-0.30, false, 1.0), (0, true, 1.0),
                                                 (0, true, -1.0), (0.30, false, -1.0), (0, true, 1.0)] {
                let stage = model.round.stage
                let used = model.round.attemptsUsed
                model.launch(strength: stage.comfortableStrength + offset, direction: direction)
                // An extra gesture must not consume another attempt during flight.
                model.launch(strength: 1, direction: direction)
                let countedOnce = model.round.attemptsUsed == used + 1
                for _ in 0..<60 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !model.isFlying { break }
                }
                rows.append(["stage": stage.number, "direction": direction,
                             "expected": expected, "actual": model.result.map { $0 as Any } ?? "stuck",
                             "passed": model.result == expected && countedOnce, "scene": model.scene.validationSnapshot])
                model.continueRound()
                try? await Task.sleep(for: .milliseconds(350))
            }
            let completed = model.round.stage.number == 4 && model.round.phase == .ready
            rows.append(["case": "wins keep health and award once", "coins": model.player.coins,
                         "health": model.player.health, "passed": model.player.coins == 30 && model.player.health == 10])
            let feedback = model.impactFeedbackCounts
            rows.append(["case": "one sound per tabletop impact", "impacts": feedback.impacts,
                         "sounds": feedback.sounds, "recordedAudio": feedback.recorded,
                         "passed": feedback.impacts == 5 && feedback.sounds == 5 && feedback.recorded])
            let physical = model.physicalFeedbackCounts
            rows.append(["case": "separate body hits and physical haptics", "contacts": physical.contacts,
                         "bodyHits": physical.body, "bodySounds": physical.bodySounds,
                         "patternsStarted": physical.patterns, "hardwareSupported": physical.supported,
                         "passed": physical.body == 2 && physical.bodySounds == 2 && physical.contacts > 5
                            && (!physical.supported || physical.patterns == physical.contacts)])
            rows.append(["case": "celebration sound only on successes", "played": physical.celebrations,
                         "passed": physical.celebrations == 3])
            model.selectStage(1)
            model.launch(strength: model.round.stage.comfortableStrength)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if !model.isFlying { break }
            }
            rows.append(["case": "completed stage replay earns one coin", "coins": model.player.coins,
                         "passed": model.result == true && model.player.coins == 31 && model.player.lastReward == 1
                            && model.player.highestCompletedStage == 3])
            model.resetValidation()
            model.launch(strength: model.round.stage.comfortableStrength)
            model.scene.isPaused = true
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if !model.isFlying { break }
            }
            model.scene.isPaused = false
            rows.append(["case": "interrupted scene recovers", "passed": model.result == false])
            model.continueRound()
            for _ in 0..<2 {
                model.launch(strength: model.round.stage.comfortableStrength - 0.3)
                for _ in 0..<60 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !model.isFlying { break }
                }
                model.continueRound()
                try? await Task.sleep(for: .milliseconds(350))
            }
            rows.append(["case": "three misses retry stage under the build health policy", "health": model.player.health,
                         "passed": model.player.health == (model.healthEnabled ? 9 : 10) && model.player.coins == 0 && model.round.stage.number == 1])
            model.resetValidation(stageNumber: 41)
            model.launch(strength: model.round.stage.comfortableStrength)
            try? await Task.sleep(for: .milliseconds(150))
            model.setPaused(true)
            let pausedAngle = model.scene.validationSnapshot["angle"]
            try? await Task.sleep(for: .seconds(1))
            let held = model.isFlying && model.scene.isPaused && model.scene.validationSnapshot["angle"] == pausedAngle
            model.setPaused(false)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if !model.isFlying { break }
            }
            rows.append(["case": "pause freezes and resume completes the live throw", "passed": held && model.result == true])
            model.resetValidation(stageNumber: 40)
            model.launch(strength: model.round.stage.comfortableStrength)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if !model.isFlying { break }
            }
            let boundaryWon = model.result == true
            model.continueRound()
            rows.append(["case": "stage 40 clear enters Water at stage 41", "passed": boundaryWon && model.round.stageNumber == 41 && model.chapter.id == "fountain"])
            model.resetValidation(stageNumber: 120)
            model.launch(strength: model.round.stage.comfortableStrength)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if !model.isFlying { break }
            }
            let finalWon = model.finalClear && model.player.lastReward == 10
            model.continueRound()
            rows.append(["case": "final clear completes campaign and opens journey", "passed": finalWon && model.player.campaignComplete && model.showStages && model.round.stageNumber == 120])
            model.showStages = false
            model.selectStage(120)
            model.launch(strength: model.round.stage.comfortableStrength)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if !model.isFlying { break }
            }
            rows.append(["case": "final stage replay awards one coin", "passed": model.result == true && model.player.lastReward == 1 && model.player.coins == 11])
            model.resetValidation(stageNumber: 20)
            model.launch(strength: model.round.stage.comfortableStrength)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if !model.isFlying { break }
            }
            let graduated = model.tutorialGraduation && model.actionTitle == "Explore the Garden"
            model.continueRound()
            rows.append(["case": "tutorial graduation enters Garden with no precision modifier",
                         "passed": graduated && model.round.stageNumber == 21 && !model.isTutorial && !model.precisionChallenge])
            var firstTryWins = true
            for _ in 0..<5 {
                model.launch(strength: model.round.stage.comfortableStrength)
                for _ in 0..<60 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !model.isFlying { break }
                }
                firstTryWins = firstTryWins && model.result == true && model.round.attemptsUsed == 1
                model.continueRound()
                try? await Task.sleep(for: .milliseconds(350))
            }
            let challengeLimit = model.round.stage.maximumLean
            let sceneLimit = model.scene.validationSnapshot["maximumLean"] ?? 0
            rows.append(["case": "five first-try clears apply the tighter limit to the actual scene",
                         "passed": firstTryWins && model.round.stageNumber == 26 && model.precisionChallenge
                            && abs(challengeLimit - BottleStage.at(26).maximumLean * 0.9) < 1e-8
                            && abs(sceneLimit - challengeLimit) < 1e-8])
            var missesAtStableLimit = true
            for _ in 0..<3 {
                model.launch(strength: model.round.stage.comfortableStrength - 0.3)
                for _ in 0..<60 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !model.isFlying { break }
                }
                missesAtStableLimit = missesAtStableLimit && model.result == false
                    && abs(model.round.stage.maximumLean - challengeLimit) < 1e-8
                model.continueRound()
                try? await Task.sleep(for: .milliseconds(350))
            }
            rows.append(["case": "three actual misses return the scene to its base tolerance",
                         "passed": missesAtStableLimit && !model.precisionChallenge
                            && model.round.stageNumber == 26 && model.player.firstTryStreak == 0
                            && abs((model.scene.validationSnapshot["maximumLean"] ?? 0) - BottleStage.at(26).maximumLean) < 1e-8])
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let report: [String: Any] = ["complete": true, "continuedPastOriginalStages": completed,
                                        "passed": completed && rows.allSatisfy { $0["passed"] as? Bool == true }, "cases": rows]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: directory.appendingPathComponent("round-validation.json"), options: .atomic)
            }
        }
    }
}
#endif
