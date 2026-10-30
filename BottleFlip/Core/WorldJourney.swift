import Foundation

public enum JourneyWorld: String, CaseIterable, Identifiable, Sendable {
    case everyday, water, ice
    public var id: String { rawValue }
    public var title: String {
        switch self { case .everyday: "Everyday World"; case .water: "Water Kingdom"; case .ice: "Ice Kingdom" }
    }
    public var stages: ClosedRange<Int> {
        switch self { case .everyday: 1...40; case .water: 41...80; case .ice: 81...120 }
    }
    public var chapters: [JourneyChapter] { WorldJourney.chapters.filter { $0.world == self } }
    public var preview: JourneyChapter { chapters[0] }
}

public enum LandingSurface: Sendable { case oak, limestone, marble, ice }

public struct JourneyChapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let world: JourneyWorld
    public let stages: ClosedRange<Int>
    public let surface: LandingSurface
    public var rangeLabel: String { "\(stages.lowerBound)–\(stages.upperBound)" }
}

public enum WorldJourney {
    public static let stageCount = 120
    public static let chapters: [JourneyChapter] = [
        .init(id: "bedroom", title: "Bedroom", world: .everyday, stages: 1...10, surface: .oak),
        .init(id: "kitchen", title: "Kitchen", world: .everyday, stages: 11...20, surface: .marble),
        .init(id: "garden", title: "Garden", world: .everyday, stages: 21...30, surface: .limestone),
        .init(id: "city", title: "City", world: .everyday, stages: 31...40, surface: .limestone),
        .init(id: "fountain", title: "Fountain Courtyard", world: .water, stages: 41...50, surface: .limestone),
        .init(id: "canal", title: "Canal Village", world: .water, stages: 51...60, surface: .limestone),
        .init(id: "coral", title: "Coral Gardens", world: .water, stages: 61...70, surface: .limestone),
        .init(id: "tide", title: "Tide Palace", world: .water, stages: 71...80, surface: .marble),
        .init(id: "snow", title: "Snow Village", world: .ice, stages: 81...90, surface: .oak),
        .init(id: "lake", title: "Frozen Lake", world: .ice, stages: 91...100, surface: .ice),
        .init(id: "crystal", title: "Crystal Caverns", world: .ice, stages: 101...110, surface: .ice),
        .init(id: "aurora", title: "Aurora Palace", world: .ice, stages: 111...120, surface: .ice)
    ]
    public static func chapter(at stage: Int) -> JourneyChapter {
        chapters[(min(stageCount, max(1, stage)) - 1) / 10]
    }
    public static func leanDegrees(at stage: Int) -> Double {
        let stage = min(stageCount, max(1, stage))
        func ramp(_ start: Int, _ end: Int, _ from: Double, _ to: Double) -> Double {
            from + (to - from) * Double(stage - start) / Double(end - start)
        }
        switch stage {
        case 1...5: return 20
        case 6...20: return ramp(5, 20, 20, 10)
        case 21...30: return ramp(21, 30, 8, 5)
        case 31...40: return ramp(31, 40, 5, 3)
        case 41...80: return ramp(41, 80, 3, 2)
        default: return ramp(81, 120, 2, 1)
        }
    }
}

/// Short coaching stays in the playfield; the player can hide it without skipping stages.
public enum TutorialGuide {
    public static let stageCount = 20
    public static func instruction(at stage: Int) -> String {
        switch stage {
        case 1:
            return "These 20 tutorial stages guide you through the game. Hold still until Ready, then make a small upward wrist flick. Keep hold of your phone."
        case 2...5:
            return "Wait for Ready, then flick gently upward. Let the bottle land before trying again."
        case 6...10:
            return "Try the juice bottle. A stronger flick adds height and spin. Make small adjustments as landings become more precise."
        case 11...15:
            return "Now try wine. Watch the fill level and adjust your flick to the bottle's feel. Aim to land upright."
        default:
            return "Put it together: watch the fill, make a controlled flick, and aim upright. You're nearly ready for the Garden."
        }
    }
}
