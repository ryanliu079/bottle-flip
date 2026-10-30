import XCTest
@testable import GameCore

final class JourneyTests: XCTestCase {
    func testEveryStageHasOneChapterAndEveryWorldHasFortyStages() {
        XCTAssertEqual(JourneyWorld.allCases.count, 3)
        XCTAssertEqual(WorldJourney.chapters.count, 12)
        for world in JourneyWorld.allCases {
            XCTAssertEqual(world.chapters.count, 4)
            XCTAssertEqual(world.chapters.flatMap { Array($0.stages) }, Array(world.stages))
        }
        for stage in 1...120 { XCTAssertEqual(WorldJourney.chapters.filter { $0.stages.contains(stage) }.count, 1) }
        XCTAssertEqual(WorldJourney.chapter(at: 20).id, "kitchen")
        XCTAssertEqual(WorldJourney.chapter(at: 21).id, "garden")
        XCTAssertEqual(WorldJourney.chapter(at: 40).world, .everyday)
        XCTAssertEqual(WorldJourney.chapter(at: 41).world, .water)
        XCTAssertEqual(WorldJourney.chapter(at: 81).world, .ice)
    }
    func testFinalClearStopsAt120AndReplayCannotEarnAFirstClearAgain() throws {
        var player = PlayerProgress()
        for _ in 1...120 {
            XCTAssertTrue(player.launch(strength: 0.5, usesHealth: false))
            XCTAssertTrue(player.resolve(success: true, usesHealth: false))
            player.continueRound()
        }
        XCTAssertTrue(player.campaignComplete)
        XCTAssertEqual(player.coins, 1200)
        XCTAssertEqual(player.unlockedStageCount, 120)
        XCTAssertEqual(player.round.stageNumber, 120)
        XCTAssertFalse(player.selectStage(121))
        var restored = try JSONDecoder().decode(PlayerProgress.self, from: JSONEncoder().encode(player))
        restored.restoreInterruptedRound(usesHealth: false)
        XCTAssertTrue(restored.launch(strength: 0.5, usesHealth: false))
        restored.resolve(success: true, usesHealth: false)
        XCTAssertEqual(restored.lastReward, 1)
        restored.continueRound()
        XCTAssertEqual(restored.round.stageNumber, 120)
        XCTAssertEqual(restored.coins, 1201)
    }
    func testLegacyBeyondCampaignMigrationKeepsWalletOwnershipAndLifetimeCompletion() throws {
        var original = PlayerProgress(stageNumber: 1000)
        original.launch(strength: 0.5, usesHealth: false)
        original.resolve(success: true, usesHealth: false)
        original.select(BottleAppearance.classic)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["coins"] = 420
        object["ownedBottles"] = ["classic", "mint"]
        object["bottleAppearance"] = "mint"
        var migrated = try JSONDecoder().decode(PlayerProgress.self, from: JSONSerialization.data(withJSONObject: object))
        migrated.restoreInterruptedRound(usesHealth: false)
        XCTAssertEqual(migrated.round.stageNumber, 120)
        XCTAssertEqual(migrated.highestCompletedStage, 1000)
        XCTAssertEqual(migrated.coins, 420)
        XCTAssertEqual(migrated.bottleAppearance, .mint)
        XCTAssertTrue(migrated.ownedBottles.contains(.mint))
        XCTAssertEqual(migrated.unlockedStageCount, 120)
        XCTAssertTrue(migrated.campaignComplete)
        migrated.launch(strength: 0.5, usesHealth: false)
        migrated.resolve(success: true, usesHealth: false)
        XCTAssertEqual(migrated.lastReward, 1)
    }
}
