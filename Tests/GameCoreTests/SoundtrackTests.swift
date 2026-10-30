import XCTest
@testable import GameCore

final class SoundtrackTests: XCTestCase {
    func testAll120StagesMatchApprovedAudioCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("BottleFlip/App/Music")
        struct Entry: Decodable { let file: String; let chapter: String; let firstStage: Int; let lastStage: Int }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: directory.appendingPathComponent("catalog.json")))
        XCTAssertEqual(entries.count, 36)
        for stage in 1...120 {
            let matches = entries.filter { ($0.firstStage...$0.lastStage).contains(stage) }
            XCTAssertEqual(matches.count, 1, "Stage \(stage)")
            let expected = try XCTUnwrap(matches.first)
            let cue = JourneySoundtrack.cue(at: stage)
            XCTAssertEqual(cue.chapterID, expected.chapter)
            XCTAssertEqual(cue.resourceName + ".caf", expected.file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(expected.file).path))
        }
        XCTAssertEqual(Set((1...120).map { JourneySoundtrack.cue(at: $0).resourceName }).count, 36)
    }

    func testLegacyOutOfRangeStagesUseCampaignEdges() {
        XCTAssertEqual(JourneySoundtrack.cue(at: -1), JourneySoundtrack.cue(at: 1))
        XCTAssertEqual(JourneySoundtrack.cue(at: 1000), JourneySoundtrack.cue(at: 120))
    }
}
