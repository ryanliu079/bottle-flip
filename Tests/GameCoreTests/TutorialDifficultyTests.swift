import XCTest
@testable import GameCore

final class TutorialDifficultyTests: XCTestCase {
    private func win(_ player: inout PlayerProgress) {
        XCTAssertTrue(player.launch(strength: 0.5, usesHealth: false))
        XCTAssertTrue(player.resolve(success: true, usesHealth: false))
        player.continueRound()
    }
    private func miss(_ player: inout PlayerProgress) {
        XCTAssertTrue(player.launch(strength: 0.1, usesHealth: false))
        XCTAssertTrue(player.resolve(success: false, usesHealth: false))
        player.continueRound()
    }
    private func reload(_ player: PlayerProgress) throws -> PlayerProgress {
        try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(player))
    }

    func testTutorialRampIsLinearAndIgnoresPrecisionChallenges() {
        for stage in 1...20 {
            let expected = stage <= 5 ? 20 : 20 - Double(stage - 5) * 2 / 3
            XCTAssertEqual(WorldJourney.leanDegrees(at: stage), expected, accuracy: 1e-10)
            XCTAssertEqual(BottleStage.at(stage, precisionLevel: 2).maximumLean,
                           expected * .pi / 180, accuracy: 1e-10)
        }
        XCTAssertEqual(WorldJourney.leanDegrees(at: 21), 8)
        var player = PlayerProgress()
        for _ in 1...20 { win(&player) }
        XCTAssertEqual(player.firstTryStreak, 0)
        XCTAssertEqual(player.precisionLevel, 0)
        XCTAssertEqual(player.round.stageNumber, 21)
    }

    func testTutorialIsFreeEvenAtZeroHealthAndAfterRelaunch() throws {
        var player = PlayerProgress(stageNumber: 21)
        for _ in 0..<30 {
            XCTAssertTrue(player.launch(strength: 0.1))
            XCTAssertTrue(player.resolve(success: false))
            player.continueRound()
        }
        XCTAssertEqual(player.health, 0)
        XCTAssertFalse(player.canPlay)
        XCTAssertTrue(player.selectStage(20))
        XCTAssertTrue(player.canPlay)
        for _ in 0..<8 {
            XCTAssertTrue(player.launch(strength: 0.1))
            XCTAssertTrue(player.resolve(success: false))
            player.continueRound()
        }
        XCTAssertTrue(player.launch(strength: 0.1))
        var restored = try reload(player)
        restored.restoreInterruptedRound()
        XCTAssertEqual(restored.health, 0)
        restored.continueRound()
        XCTAssertTrue(restored.canPlay)
        restored.selectStage(21)
        XCTAssertFalse(restored.canPlay)
    }

    func testFiveNewFirstTryClearsAffectOnlyTheNextStageAndCapAtTwentyPercent() {
        var player = PlayerProgress(stageNumber: 21)
        for count in 1...4 {
            win(&player)
            XCTAssertEqual(player.firstTryStreak, count)
            XCTAssertEqual(player.round.precisionLevel, 0)
        }
        let before = player.round.stage.maximumLean
        player.launch(strength: 0.5, usesHealth: false)
        player.resolve(success: true, usesHealth: false)
        XCTAssertTrue(player.lastStreakMilestone)
        XCTAssertEqual(player.precisionLevel, 1)
        XCTAssertEqual(player.round.stage.maximumLean, before)
        XCTAssertFalse(player.resolve(success: true))
        player.continueRound()
        XCTAssertEqual(player.round.stageNumber, 26)
        XCTAssertEqual(player.firstTryStreak, 0)
        XCTAssertEqual(player.round.stage.maximumLean, BottleStage.at(26).maximumLean * 0.9, accuracy: 1e-10)
        for _ in 0..<5 { win(&player) }
        XCTAssertEqual(player.round.precisionLevel, 2)
        XCTAssertEqual(player.round.stage.maximumLean, BottleStage.at(31).maximumLean * 0.8, accuracy: 1e-10)
        for _ in 0..<10 { win(&player) }
        XCTAssertEqual(player.precisionLevel, 2)
    }

    func testFirstMissResetsStreakAndRetryWinCannotStartOne() {
        var player = PlayerProgress(stageNumber: 21)
        for _ in 0..<4 { win(&player) }
        miss(&player)
        XCTAssertEqual(player.firstTryStreak, 0)
        win(&player)
        XCTAssertEqual(player.firstTryStreak, 0)
        XCTAssertEqual(player.precisionLevel, 0)
        win(&player)
        XCTAssertEqual(player.firstTryStreak, 1)
    }

    func testThreeMissesRemoveExtraChallengeOnlyOnRetry() throws {
        var player = PlayerProgress(stageNumber: 21)
        for _ in 0..<10 { win(&player) }
        let challenged = player.round.stage.maximumLean
        for attempt in 1...3 {
            XCTAssertTrue(player.launch(strength: 0.1, usesHealth: false))
            XCTAssertTrue(player.resolve(success: false, usesHealth: false))
            XCTAssertEqual(player.round.stage.maximumLean, challenged)
            if attempt < 3 { player.continueRound() }
        }
        var restored = try reload(player)
        restored.restoreInterruptedRound(usesHealth: false)
        restored.continueRound()
        XCTAssertEqual(restored.precisionLevel, 0)
        XCTAssertEqual(restored.round.stage.maximumLean, BottleStage.at(31).maximumLean)
        XCTAssertEqual(restored.round.failedAttempts, 3)
        win(&restored)
        XCTAssertEqual(restored.firstTryStreak, 0)
    }

    func testReplayCannotFarmStreakAndReturningKeepsUnfinishedChallenge() throws {
        var player = PlayerProgress(stageNumber: 21)
        for _ in 0..<6 { win(&player) }
        let stage = player.round.stageNumber
        let limit = player.round.stage.maximumLean
        XCTAssertEqual(player.firstTryStreak, 1)
        for _ in 0..<6 {
            XCTAssertTrue(player.selectStage(21))
            win(&player)
        }
        XCTAssertEqual(player.firstTryStreak, 1)
        XCTAssertEqual(player.precisionLevel, 1)
        var restored = try reload(player)
        restored.selectStage(stage)
        XCTAssertEqual(restored.round.stage.maximumLean, limit)
        miss(&restored)
        restored.selectStage(1)
        restored.selectStage(stage)
        win(&restored)
        XCTAssertEqual(restored.firstTryStreak, 0)
    }

    func testSuccessfulSaveAndInterruptedThrowCannotDoubleCountStreak() throws {
        var player = PlayerProgress(stageNumber: 21)
        for _ in 0..<4 { win(&player) }
        player.launch(strength: 0.5, usesHealth: false)
        var interrupted = try reload(player)
        interrupted.restoreInterruptedRound(usesHealth: false)
        interrupted.restoreInterruptedRound(usesHealth: false)
        XCTAssertEqual(interrupted.firstTryStreak, 0)
        XCTAssertEqual(interrupted.round.failedAttempts, 1)
        player.resolve(success: true, usesHealth: false)
        var restored = try reload(player)
        restored.restoreInterruptedRound(usesHealth: false)
        XCTAssertTrue(restored.lastStreakMilestone)
        XCTAssertEqual(restored.precisionLevel, 1)
        XCTAssertFalse(restored.resolve(success: true))
        restored.continueRound()
        XCTAssertEqual(restored.round.precisionLevel, 1)
        XCTAssertEqual(restored.coins, 50)
    }

    func testOldSavesDefaultNewSettingsAndKeepEconomyAndMisses() throws {
        var player = PlayerProgress(stageNumber: 30)
        for _ in 0..<6 { win(&player) }
        player.select(BottleAppearance.mint)
        miss(&player)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(player)) as? [String: Any])
        for key in ["tutorialHintsEnabled", "firstTryStreak", "precisionLevel", "lastStreakMilestone", "stagePrecision"] {
            data.removeValue(forKey: key)
        }
        var round = try XCTUnwrap(data["round"] as? [String: Any])
        round.removeValue(forKey: "precisionLevel")
        data["round"] = round
        var restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONSerialization.data(withJSONObject: data))
        restored.restoreInterruptedRound()
        XCTAssertEqual(restored.coins, player.coins)
        XCTAssertEqual(restored.ownedBottles, player.ownedBottles)
        XCTAssertEqual(restored.highestCompletedStage, player.highestCompletedStage)
        XCTAssertEqual(restored.round.failedAttempts, 1)
        XCTAssertEqual(restored.round.precisionLevel, 0)
        XCTAssertEqual(restored.firstTryStreak, 0)
        XCTAssertTrue(restored.tutorialHintsEnabled)
        restored.setTutorialHints(false)
        XCTAssertFalse(try reload(restored).tutorialHintsEnabled)
    }

    func testAllChallengedStagesStayAchievableAndOnlyChangeLandingTolerance() {
        for number in 21...120 {
            let base = BottleStage.at(number)
            let challenged = BottleStage.at(number, precisionLevel: 2)
            XCTAssertGreaterThanOrEqual(challenged.maximumLean, .pi / 180 - 1e-10)
            XCTAssertGreaterThanOrEqual(challenged.maximumLean, base.maximumLean * 0.8 - 1e-10)
            for offset in [-0.002, 0, 0.002] {
                let strength = base.comfortableStrength + offset
                let profile = ThrowProfile(strength: strength, stage: challenged)
                XCTAssertEqual(profile.landingAngle, ThrowProfile(strength: strength, stage: base).landingAngle)
                XCTAssertLessThan(abs(ThrowProfile.uprightError(profile.landingAngle)), challenged.maximumLean)
            }
        }
    }
}
