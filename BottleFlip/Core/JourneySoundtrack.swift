import Foundation

/// Matches the approved revision 2 stage map; each chapter develops through three arrangements.
public struct JourneySoundtrack: Equatable, Sendable {
    public let chapterID: String
    public let resourceName: String

    public static func cue(at stage: Int) -> Self {
        let stage = min(WorldJourney.stageCount, max(1, stage))
        let chapter = WorldJourney.chapter(at: stage)
        let localStage = stage - chapter.stages.lowerBound + 1
        let settleEnd = chapter.id == "bedroom" ? 5 : chapter.id == "kitchen" ? 4 : 3
        let flowEnd = chapter.id == "bedroom" ? 8 : 7
        let arrangement = localStage <= settleEnd ? "a_settle" : localStage <= flowEnd ? "b_flow" : "c_bloom"
        let range = String(format: "%03d-%03d", chapter.stages.lowerBound, chapter.stages.upperBound)
        return .init(chapterID: chapter.id, resourceName: "\(range)_\(chapter.id)_\(arrangement)_v2")
    }
}
