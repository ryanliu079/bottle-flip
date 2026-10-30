import XCTest
@testable import GameCore

final class PlayerProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1790766000)
    private func calendar(_ zone: String = "Europe/London") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func missStage(_ player: inout PlayerProgress) {
        for _ in 0..<3 {
            XCTAssertTrue(player.launch(strength: 0.1, now: now))
            XCTAssertTrue(player.resolve(success: false))
            player.continueRound()
        }
    }
    private func win(_ player: inout PlayerProgress) {
        XCTAssertTrue(player.launch(strength: 0.5, now: now))
        XCTAssertTrue(player.resolve(success: true))
        player.continueRound()
    }
    func testOnlyAcceptedSuccessAwardsExactlyTenCoins() {
        var player = PlayerProgress(now: now)
        XCTAssertFalse(player.resolve(success: true))
        XCTAssertTrue(player.launch(strength: 0.5, now: now))
        XCTAssertFalse(player.launch(strength: 0.5, now: now))
        XCTAssertTrue(player.resolve(success: true))
        XCTAssertFalse(player.resolve(success: true))
        XCTAssertEqual(player.coins, 10)
        XCTAssertEqual(player.health, 10)
        player.continueRound(); player.continueRound()
        XCTAssertEqual(player.round.stageNumber, 2)
    }
    func testThirdTryWinCostsNoHealth() {
        var player = PlayerProgress(now: now, stageNumber: 21)
        for _ in 0..<2 {
            player.launch(strength: 0.1, now: now); player.resolve(success: false); player.continueRound()
        }
        win(&player)
        XCTAssertEqual(player.health, 10)
        XCTAssertEqual(player.coins, 10)
        XCTAssertEqual(player.round.stageNumber, 22)
    }
    func testTenFailedStagesExhaustHealthAndBlockThrows() {
        var player = PlayerProgress(now: now, stageNumber: 21)
        for failure in 1...10 {
            missStage(&player)
            XCTAssertEqual(player.health, 10 - failure)
            XCTAssertEqual(player.round.stageNumber, 21)
            XCTAssertEqual(player.coins, 0)
        }
        XCTAssertFalse(player.canPlay)
        XCTAssertFalse(player.launch(strength: 0.5, now: now))
        XCTAssertEqual(player.round.attemptsUsed, 0)
        XCTAssertFalse(player.resolve(success: true))
    }
    func testUnlimitedModeWorksWithExhaustedHealthWithoutChangingItsBalance() {
        var player = PlayerProgress(now: now, stageNumber: 21)
        for _ in 0..<10 { missStage(&player) }
        XCTAssertEqual(player.health, 0)
        XCTAssertTrue(player.canPlay(usesHealth: false))
        for _ in 0..<60 {
            XCTAssertTrue(player.launch(strength: 0.1, now: now, usesHealth: false))
            XCTAssertTrue(player.resolve(success: false, usesHealth: false))
            XCTAssertFalse(player.resolve(success: false, usesHealth: false))
            player.continueRound()
        }
        XCTAssertEqual(player.health, 0)
        XCTAssertEqual(player.round.stageNumber, 21)
        XCTAssertTrue(player.launch(strength: 0.5, now: now, usesHealth: false))
        XCTAssertTrue(player.resolve(success: true, usesHealth: false))
        player.continueRound()
        XCTAssertEqual(player.coins, 10)
        XCTAssertEqual(player.health, 0)
        XCTAssertEqual(player.round.stageNumber, 22)
    }

    func testWinningCanContinueBeyondTenStages() {
        var player = PlayerProgress(now: now)
        for _ in 0..<100 { win(&player) }
        XCTAssertEqual(player.health, 10)
        XCTAssertEqual(player.coins, 1000)
        XCTAssertEqual(player.round.stageNumber, 101)
    }
    func testRefillAtLocalMidnightDoesNotStackOrRepeat() {
        let cal = calendar()
        let midnight = cal.dateInterval(of: .day, for: now)!.end
        var player = PlayerProgress(now: now, stageNumber: 21)
        missStage(&player)
        XCTAssertFalse(player.refreshHealth(now: midnight.addingTimeInterval(-1), calendar: cal))
        XCTAssertEqual(player.health, 9)
        XCTAssertTrue(player.refreshHealth(now: midnight, calendar: cal))
        XCTAssertEqual(player.health, 10)
        XCTAssertFalse(player.refreshHealth(now: midnight.addingTimeInterval(1), calendar: cal))
        XCTAssertFalse(player.refreshHealth(now: now, calendar: cal))
        XCTAssertTrue(player.refreshHealth(now: midnight.addingTimeInterval(86400 * 3), calendar: cal))
        XCTAssertEqual(player.health, 10)
    }
    func testExhaustedPlayerCanLaunchAfterMidnight() {
        var player = PlayerProgress(now: now, stageNumber: 21)
        for _ in 0..<10 { missStage(&player) }
        let midnight = calendar().dateInterval(of: .day, for: now)!.end
        XCTAssertTrue(player.launch(strength: 0.5, now: midnight, calendar: calendar()))
        XCTAssertEqual(player.health, 10)
    }
    func testRefillUsesCalendarDayAcrossDaylightSaving() {
        let cal = calendar()
        for date in [(2026, 3, 29, 23.0), (2026, 10, 25, 25.0)] {
            let start = cal.date(from: DateComponents(year: date.0, month: date.1, day: date.2))!
            let end = cal.dateInterval(of: .day, for: start)!.end
            XCTAssertEqual(end.timeIntervalSince(start), date.3 * 3600, accuracy: 0.01)
            var player = PlayerProgress(now: start)
            XCTAssertFalse(player.refreshHealth(now: end.addingTimeInterval(-1), calendar: cal))
            XCTAssertTrue(player.refreshHealth(now: end, calendar: cal))
            XCTAssertEqual(player.nextRefill(now: start, calendar: cal), end)
        }
    }
    func testPurchaseAffordabilityOwnershipAndFreeReequip() {
        var player = PlayerProgress(now: now)
        XCTAssertEqual(player.select(BottleAppearance.mint), .insufficientCoins)
        XCTAssertEqual(player.bottleAppearance, .classic)
        for _ in 0..<5 { win(&player) }
        XCTAssertEqual(player.select(BottleAppearance.mint), .purchased)
        XCTAssertEqual(player.coins, 0)
        XCTAssertEqual(player.select(BottleAppearance.classic), .equipped)
        XCTAssertEqual(player.select(BottleAppearance.mint), .equipped)
        XCTAssertEqual(player.coins, 0)
        XCTAssertEqual(player.ownedBottles, [.classic, .mint])
        XCTAssertEqual(player.select(TableAppearance.walnut), .insufficientCoins)
        for _ in 0..<10 { win(&player) }
        XCTAssertEqual(player.select(TableAppearance.walnut), .purchased)
        XCTAssertEqual(player.select(TableAppearance.oak), .equipped)
        XCTAssertEqual(player.select(TableAppearance.walnut), .equipped)
        XCTAssertEqual(player.coins, 0)
        XCTAssertEqual(player.health, 10)
    }
    func testReloadOfSuccessfulResultCannotPayAgain() throws {
        var player = PlayerProgress(now: now)
        player.launch(strength: 0.5, now: now); player.resolve(success: true)
        var restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(player))
        restored.restoreInterruptedRound()
        XCTAssertFalse(restored.resolve(success: true))
        XCTAssertEqual(restored.coins, 10)
        restored.continueRound()
        XCTAssertEqual(restored.round.stageNumber, 2)
    }
    func testInterruptedThirdAttemptCostsHealthOnlyOnceOnRestore() throws {
        var player = PlayerProgress(now: now, stageNumber: 21)
        for _ in 0..<2 {
            player.launch(strength: 0.1, now: now); player.resolve(success: false); player.continueRound()
        }
        player.launch(strength: 0.1, now: now)
        var restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(player))
        restored.restoreInterruptedRound(); restored.restoreInterruptedRound()
        XCTAssertEqual(restored.health, 9)
        XCTAssertEqual(restored.round.phase, .result(success: false))
        restored.continueRound()
        XCTAssertEqual(restored.round.stageNumber, 21)
        XCTAssertEqual(restored.round.attemptsUsed, 0)
    }
    func testOldSaveWithoutMissCounterPreservesWalletAndUnlocks() throws {
        var player = PlayerProgress(now: now)
        for _ in 0..<20 { win(&player) }
        player.select(BottleAppearance.mint)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(player)) as? [String: Any])
        var round = try XCTUnwrap(object["round"] as? [String: Any])
        round.removeValue(forKey: "failedAttempts")
        object["round"] = round
        object.removeValue(forKey: "highestCompletedStage")
        object.removeValue(forKey: "lastReward")
        object.removeValue(forKey: "stageMisses")
        let restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.coins, player.coins)
        XCTAssertEqual(restored.ownedBottles, player.ownedBottles)
        XCTAssertEqual(restored.round.stageNumber, player.round.stageNumber)
        XCTAssertEqual(restored.round.failedAttempts, 0)
    }

    func testFirstClearAwardsTenReplayAwardsOneAndCannotPayTwice() throws {
        var player = PlayerProgress(now: now)
        player.launch(strength: 0.5, now: now); player.resolve(success: true)
        XCTAssertEqual(player.lastReward, 10)
        XCTAssertEqual(player.highestCompletedStage, 1)
        XCTAssertTrue(player.selectStage(1))
        XCTAssertTrue(player.launch(strength: 0.5, now: now))
        XCTAssertTrue(player.resolve(success: true))
        XCTAssertFalse(player.resolve(success: true))
        XCTAssertEqual(player.coins, 11)
        XCTAssertEqual(player.lastReward, 1)
        var restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(player))
        restored.restoreInterruptedRound()
        XCTAssertEqual(restored.lastReward, 1)
        XCTAssertFalse(restored.resolve(success: true))
        XCTAssertEqual(restored.coins, 11)
        restored.continueRound()
        win(&restored)
        XCTAssertEqual(restored.coins, 21)
        XCTAssertEqual(restored.highestCompletedStage, 2)
    }

    func testStagePickerRejectsLockedStagesAndSwitchesDuringFlight() {
        var player = PlayerProgress(now: now)
        XCTAssertFalse(player.selectStage(0))
        XCTAssertFalse(player.selectStage(2))
        win(&player)
        XCTAssertEqual(player.unlockedStageCount, 2)
        XCTAssertFalse(player.selectStage(3))
        XCTAssertTrue(player.selectStage(1))
        player.launch(strength: 0.5, now: now)
        XCTAssertFalse(player.selectStage(2))
        XCTAssertEqual(player.round.stageNumber, 1)
        player.resolve(success: false); player.continueRound()
        XCTAssertTrue(player.selectStage(1))
        XCTAssertEqual(player.round.attemptsUsed, 1)
    }

    func testAdaptiveHelpSurvivesLeavingStageAndReturnsToNormalAfterClear() throws {
        var player = PlayerProgress(now: now, stageNumber: 105)
        for _ in 0..<35 {
            player.launch(strength: 0.1, now: now, usesHealth: false)
            player.resolve(success: false, usesHealth: false)
            player.continueRound()
        }
        let helpedLimit = player.round.stage.maximumLean
        XCTAssertTrue(player.selectStage(1))
        var restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(player))
        XCTAssertTrue(restored.selectStage(105))
        XCTAssertEqual(restored.round.failedAttempts, 35)
        XCTAssertEqual(restored.round.stage.maximumLean, helpedLimit)
        win(&restored)
        XCTAssertEqual(restored.highestCompletedStage, 105)
        XCTAssertTrue(restored.selectStage(105))
        XCTAssertEqual(restored.round.failedAttempts, 0)
        XCTAssertEqual(restored.round.stage.maximumLean, BottleStage.at(105).maximumLean)
    }

    func testLegacySavedSuccessIsAlreadyCompletedOnUpgrade() throws {
        var player = PlayerProgress(now: now)
        player.launch(strength: 0.5, now: now); player.resolve(success: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(player)) as? [String: Any])
        object.removeValue(forKey: "highestCompletedStage")
        object.removeValue(forKey: "lastReward")
        object.removeValue(forKey: "stageMisses")
        var restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(restored.hasCompleted(1))
        XCTAssertEqual(restored.lastReward, 10)
        XCTAssertTrue(restored.selectStage(1))
        win(&restored)
        XCTAssertEqual(restored.coins, 11)
    }

    func testAtomicStoreRestoresWalletHealthStageAndAppearances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProgressStore(url: directory.appendingPathComponent("player.json"))
        XCTAssertNil(try store.load())
        var player = PlayerProgress(now: now)
        for _ in 0..<20 { win(&player) }
        player.select(BottleAppearance.mint); player.select(TableAppearance.walnut)
        missStage(&player)
        try store.save(player)
        XCTAssertEqual(try store.load(), player)
        try Data("broken save".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: store.url, encoding: .utf8), "broken save")
    }
}
