import XCTest

final class NavigationTests: XCTestCase {
    private func journey() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.ryanliu.bottleflip.prototype")
        app.launchArguments = ["--preview-stage", "43", "--preview-map"]
        app.launch()
        XCTAssertTrue(app.buttons["world-everyday"].waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWorldAndChapterImagesOpenMapsAndReplayEarlierStage() {
        let app = journey()
        capture(app, "world-map")
        // This empty upper image area used to miss taps with a plain button.
        app.buttons["world-everyday"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        for chapter in ["bedroom", "kitchen", "garden", "city"] {
            XCTAssertTrue(app.buttons["chapter-\(chapter)"].waitForExistence(timeout: 5))
        }
        capture(app, "everyday-chapters")
        app.buttons["chapter-bedroom"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stage 1,")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if first.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(first.isHittable)
        first.tap()
        capture(app, "bedroom-stage-map")
        app.buttons["Play stage 1"].tap()
        XCTAssertTrue(app.buttons["Open journey map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stage 1"].exists)
        capture(app, "replayed-bedroom")
    }

    func testWaterImageNavigationPreservesLockedChapters() {
        let app = journey()
        app.buttons["world-water"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["chapter-fountain"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chapter-canal"].isEnabled)
        app.buttons["chapter-fountain"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["Play stage 43"].waitForExistence(timeout: 5))
        app.buttons["Back to chapters"].tap()
        XCTAssertTrue(app.buttons["chapter-fountain"].waitForExistence(timeout: 5))
        app.buttons["Back to worlds"].tap()
        XCTAssertTrue(app.buttons["world-everyday"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["world-ice"].isEnabled)
    }

    func testTutorialIntroducesTwentyStagesAndTipsCanBeHiddenAndReopened() {
        let app = XCUIApplication(bundleIdentifier: "com.ryanliu.bottleflip.prototype")
        app.launchArguments = ["--preview-stage", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["tutorial-progress"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["tutorial-instruction"].label.contains("20 tutorial stages"))
        capture(app, "tutorial-introduction")
        app.buttons["Hide tutorial tips"].tap()
        XCTAssertFalse(app.staticTexts["tutorial-instruction"].exists)
        XCTAssertTrue(app.staticTexts["tutorial-progress"].exists)
        app.buttons["Pause game"].tap()
        app.buttons["How to play"].tap()
        let tips = app.switches["tutorial-tips-toggle"]
        XCTAssertTrue(tips.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if tips.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tips.tap()
        app.scrollViews.firstMatch.swipeDown()
        // On a compact phone, the native downward gesture can dismiss the sheet itself.
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.staticTexts["tutorial-instruction"].waitForExistence(timeout: 5))
    }

    func testTutorialGraduatesIntoGardenAndPrecisionBeginsOnlyAfterStreak() {
        let app = XCUIApplication(bundleIdentifier: "com.ryanliu.bottleflip.prototype")
        app.launchArguments = ["--preview-stage", "20"]
        app.launch()
        XCTAssertTrue(app.staticTexts["tutorial-progress"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["precision-challenge"].exists)
        app.buttons["Practice controls"].tap()
        app.buttons["Test this throw"].tap()
        XCTAssertTrue(app.staticTexts["tutorial-complete"].waitForExistence(timeout: 10))
        capture(app, "tutorial-graduation")
        app.buttons["Explore the Garden"].tap()
        XCTAssertFalse(app.staticTexts["tutorial-progress"].exists)
        XCTAssertFalse(app.staticTexts["precision-challenge"].exists)
        capture(app, "garden-first-stage")
        app.terminate()
        app.launchArguments = ["--preview-stage", "26"]
        app.launch()
        XCTAssertTrue(app.staticTexts["precision-challenge"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["tutorial-progress"].exists)
        capture(app, "garden-precision-challenge")
    }
}
