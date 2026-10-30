import XCTest
@testable import GameCore

final class GameCoreTests: XCTestCase {
    func testExactlyThreeAttemptsAndRetryKeepsStage() {
        var round = RoundState()
        let stage = round.stage
        for attempt in 1...3 {
            XCTAssertTrue(round.launch(strength: 0.2))
            XCTAssertEqual(round.attemptsUsed, attempt)
            XCTAssertFalse(round.launch(strength: 0.8))
            XCTAssertTrue(round.resolve(success: false))
            XCTAssertFalse(round.resolve(success: true))
            round.continueRound()
        }
        XCTAssertEqual(round.stage, stage)
        XCTAssertEqual(round.attemptsUsed, 0)
        XCTAssertEqual(round.phase, .ready)
    }

    func testProgressionContinuesPastTheOldFinalStage() {
        var round = RoundState()
        for stage in 1...1000 {
            XCTAssertEqual(round.stage.number, stage)
            XCTAssertTrue(round.launch(strength: 0.5))
            XCTAssertTrue(round.resolve(success: true))
            round.continueRound()
        }
        XCTAssertEqual(round.stage.number, 1001)
        XCTAssertEqual(round.phase, .ready)
    }

    func testBoundsAndStrongerThrowsHaveMoreLiftAndSpin() {
        for stage in BottleStage.validationSamples {
            var previous = ThrowProfile(strength: -1, stage: stage)
            for step in 1...100 {
                let next = ThrowProfile(strength: Double(step) / 100, stage: stage)
                XCTAssertGreaterThan(next.initialLift, previous.initialLift)
                XCTAssertGreaterThan(next.initialSpin, previous.initialSpin)
                XCTAssertGreaterThan(next.maximumHeight, previous.maximumHeight)
                previous = next
            }
            XCTAssertEqual(ThrowProfile(strength: 5, stage: stage).strength, 1)
            XCTAssertEqual(ThrowProfile(strength: .nan, stage: stage).strength, 0)
        }
    }

    func testEveryStageHasAnAchievableFullTurn() {
        for stage in BottleStage.validationSamples {
            let throwProfile = ThrowProfile(strength: stage.comfortableStrength, stage: stage)
            XCTAssertEqual(throwProfile.height(at: throwProfile.flightDuration), 0, accuracy: 1e-9)
            XCTAssertEqual(throwProfile.landingAngle, 2 * .pi, accuracy: 1e-9)
            XCTAssertLessThan(throwProfile.spin(at: throwProfile.flightDuration), throwProfile.initialSpin)
            XCTAssertLessThan(ThrowProfile(strength: stage.comfortableStrength - 0.1, stage: stage).landingAngle, 2 * .pi)
            XCTAssertGreaterThan(ThrowProfile(strength: stage.comfortableStrength + 0.1, stage: stage).landingAngle, 2 * .pi)
        }
    }

    func testLandingRequiresTableContactAndContinuousSettlement() {
        var tracker = LandingTracker()
        for _ in 0..<60 {
            XCTAssertFalse(tracker.update(delta: 0.016, touchingTable: false, angle: 0, speed: 0, spin: 0))
        }
        for _ in 0..<20 {
            XCTAssertFalse(tracker.update(delta: 0.016, touchingTable: true, angle: 2 * .pi, speed: 0.05, spin: 0.1))
        }
        XCTAssertFalse(tracker.update(delta: 0.016, touchingTable: true, angle: .pi, speed: 0, spin: 0))
        for _ in 0..<28 {
            XCTAssertFalse(tracker.update(delta: 0.016, touchingTable: true, angle: 0.01, speed: 0.05, spin: 0.1))
        }
        XCTAssertTrue(tracker.update(delta: 0.016, touchingTable: true, angle: 0.01, speed: 0.05, spin: 0.1))
    }

    func testComfortableStrengthHasAWindowRatherThanOneExactValue() {
        for stage in BottleStage.validationSamples {
            for offset in [-0.002, 0.002] {
                let profile = ThrowProfile(strength: stage.comfortableStrength + offset, stage: stage)
                XCTAssertLessThan(abs(ThrowProfile.uprightError(profile.landingAngle)), stage.maximumLean)
            }
        }
    }

    func testBothTiltAxesAndExactStageBoundary() {
        for stage in BottleStage.validationSamples {
            for angle in [-stage.maximumLean, 0, stage.maximumLean] {
                var tracker = LandingTracker(maximumLean: stage.maximumLean)
                XCTAssertFalse(tracker.update(delta: 0.3, touchingTable: true, angle: angle, speed: 0.05, spin: 0.1))
                XCTAssertTrue(tracker.update(delta: 0.2, touchingTable: true, angle: angle, speed: 0.05, spin: 0.1))
            }
            for angle in [stage.maximumLean + 0.0001, .pi / 2, .pi] {
                var tracker = LandingTracker(maximumLean: stage.maximumLean)
                XCTAssertFalse(tracker.update(delta: 1, touchingTable: true, angle: angle, speed: 0, spin: 0))
            }
            var sideways = LandingTracker(maximumLean: stage.maximumLean)
            XCTAssertFalse(sideways.update(delta: 1, touchingTable: true, angle: 0, speed: 0, spin: 0, roll: stage.maximumLean + 0.001))
            var combined = LandingTracker(maximumLean: stage.maximumLean)
            XCTAssertFalse(combined.update(delta: 1, touchingTable: true, angle: stage.maximumLean * 0.8,
                                          speed: 0, spin: 0, roll: stage.maximumLean * 0.8))
        }
        var moving = LandingTracker()
        XCTAssertFalse(moving.update(delta: 1, touchingTable: true, angle: 0, speed: 1, spin: 1))
    }

    func testGeneratedStagesAreBoundedAndHaveAnAchievableContactWindow() {
        var previousLimit = Double.infinity
        for number in Array(1...300) + [1000, 1_000_000, Int.max] {
            let stage = BottleStage.at(number)
            XCTAssertGreaterThanOrEqual(stage.maximumLean, 1 * .pi / 180 - 1e-10)
            XCTAssertLessThanOrEqual(stage.leanRatio, previousLimit)
            XCTAssertTrue((0.25...0.68).contains(stage.fill))
            previousLimit = stage.leanRatio
            for offset in [-0.002, 0, 0.002] {
                let profile = ThrowProfile(strength: stage.comfortableStrength + offset, stage: stage)
                let error = abs(ThrowProfile.uprightError(profile.landingAngle))
                XCTAssertLessThan(error, stage.maximumLean, "Stage \(number)")
                XCTAssertEqual(0.5 + profile.height(at: profile.contactTime),
                               ThrowProfile.support(at: profile.landingAngle), accuracy: 1e-9)
            }
            for offset in [-0.3, 0.3] {
                let profile = ThrowProfile(strength: stage.comfortableStrength + offset, stage: stage)
                XCTAssertGreaterThan(abs(ThrowProfile.uprightError(profile.landingAngle)), stage.maximumLean)
            }
        }
        for number in 1...20 {
            let early = BottleStage.at(number)
            for offset in [-0.15, 0.15].map({ $0 * early.maximumLean / (20 * .pi / 180) }) {
                XCTAssertLessThan(abs(ThrowProfile.uprightError(ThrowProfile(strength: early.comfortableStrength + offset,
                                                                          stage: early).landingAngle)), early.maximumLean)
            }
        }
        XCTAssertEqual(BottleStage.at(1).liquid, .water)
        XCTAssertEqual(BottleStage.at(6).liquid, .juice)
        XCTAssertEqual(BottleStage.at(11).liquid, .wine)
    }

    func testDifficultyKeepsBeginnerRoomsEasyThenTightensAcrossWorlds() {
        for number in 1...5 { XCTAssertEqual(BottleStage.at(number).maximumLean, 20 * .pi / 180, accuracy: 1e-10) }
        for (number, degrees) in [(8, 18.0), (11, 16), (14, 14), (17, 12), (20, 10)] {
            XCTAssertEqual(BottleStage.at(number).maximumLean, degrees * .pi / 180, accuracy: 1e-10)
        }
        for (number, degrees) in [(21, 8.0), (30, 5), (31, 5), (40, 3), (41, 3), (80, 2), (81, 2), (120, 1), (1000, 1)] {
            XCTAssertEqual(BottleStage.at(number).maximumLean, degrees * .pi / 180, accuracy: 1e-10)
        }
        for number in 22...120 { XCTAssertLessThanOrEqual(BottleStage.at(number).maximumLean, BottleStage.at(number - 1).maximumLean + 1e-10) }
    }

    func testAssistanceStartsAtThirtyPersistsAcrossRetriesAndResetsOnAdvance() throws {
        var round = RoundState(stageNumber: 105)
        let base = round.stage.maximumLean
        for miss in 1...45 {
            XCTAssertTrue(round.launch(strength: 0.1))
            XCTAssertTrue(round.resolve(success: false))
            XCTAssertFalse(round.resolve(success: false))
            round.continueRound()
            XCTAssertEqual(round.failedAttempts, miss)
            XCTAssertEqual(round.stage.maximumLean, base + Double(max(0, miss - 29)) * .pi / 180, accuracy: 1e-10)
        }
        var restored = try JSONDecoder().decode(RoundState.self, from: JSONEncoder().encode(round))
        XCTAssertEqual(restored, round)
        restored.launch(strength: 0.5); restored.resolve(success: true); restored.continueRound()
        XCTAssertEqual(restored.failedAttempts, 0)
        XCTAssertEqual(restored.stage.maximumLean, BottleStage.at(106).maximumLean)
        XCTAssertEqual(BottleStage.at(105, failedAttempts: Int.max).maximumLean, 30 * .pi / 180, accuracy: 1e-10)
    }

    func testAdaptiveHelpTurnsANearMissIntoAValidLandingWithoutChangingTheThrow() {
        let hard = BottleStage.at(105)
        let assisted = BottleStage.at(105, failedAttempts: 45)
        let strength = hard.comfortableStrength + 0.12
        let profile = ThrowProfile(strength: strength, stage: hard)
        let lean = abs(ThrowProfile.uprightError(profile.landingAngle))
        XCTAssertGreaterThan(lean, hard.maximumLean)
        XCTAssertLessThan(lean, assisted.maximumLean)
        XCTAssertEqual(profile.landingAngle, ThrowProfile(strength: strength, stage: assisted).landingAngle)
    }

    private func flick(acceleration: Double, rotation: Double) -> [Double] {
        var detector = FlickDetector()
        var outputs: [Double] = []
        for frame in 0..<120 {
            let active = (40..<52).contains(frame)
            let sample = MotionSample(time: Double(frame) / 100,
                                      upwardAcceleration: active ? acceleration : 0,
                                      rotationSpeed: active ? rotation : 0,
                                      accelerationMagnitude: active ? acceleration : 0.02)
            if let strength = detector.process(sample) { outputs.append(strength) }
        }
        return outputs
    }

    func testFlickEmitsOnceAndStrengthScales() {
        let weak = flick(acceleration: 0.5, rotation: 2)
        let strong = flick(acceleration: 1.5, rotation: 7)
        XCTAssertEqual(weak.count, 1)
        XCTAssertEqual(strong.count, 1)
        XCTAssertGreaterThan(strong[0], weak[0])
        XCTAssertLessThanOrEqual(strong[0], 1)
    }

    func testStillnessAndPlainTranslationDoNotTrigger() {
        XCTAssertTrue(flick(acceleration: 0, rotation: 0).isEmpty)
        XCTAssertTrue(flick(acceleration: 0.7, rotation: 0.1).isEmpty)
        var detector = FlickDetector()
        for frame in 0..<100 {
            XCTAssertNil(detector.process(.init(time: Double(frame) / 100,
                                                upwardAcceleration: 1, rotationSpeed: 4,
                                                accelerationMagnitude: 1)))
        }
    }
}
