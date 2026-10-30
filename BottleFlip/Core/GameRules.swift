import Foundation

/// Tuned game profiles, not measurements or a fluid simulation.
public enum BottleLiquid: String, Codable, CaseIterable, Sendable {
    case water, juice, wine
    public var title: String { rawValue.capitalized }
    public var density: Double {
        switch self { case .water: 1; case .juice: 1.08; case .wine: 0.99 }
    }
    public var damping: Double {
        switch self { case .water: 1; case .juice: 1.18; case .wine: 0.92 }
    }
    public var color: AppearanceColor {
        switch self {
        case .water: .init(0.21, 0.54, 0.72)
        case .juice: .init(0.98, 0.47, 0.06)
        case .wine: .init(0.48, 0.06, 0.16)
        }
    }
}

public struct BottleStage: Equatable, Sendable {
    public let number: Int
    public let fill: Double
    public let liquid: BottleLiquid
    public let comfortableStrength: Double
    public let leanRatio: Double
    public var maximumLean: Double { atan(leanRatio) }
    public var isTutorial: Bool { number <= TutorialGuide.stageCount }
    public var effectiveMass: Double { 0.15 + fill * 0.35 * liquid.density }

    public static func at(_ number: Int, failedAttempts: Int = 0, precisionLevel: Int = 0) -> BottleStage {
        let number = max(1, number)
        let liquid: BottleLiquid = number <= 5 ? .water : number <= 10 ? .juice
            : number <= 15 ? .wine : BottleLiquid.allCases[((number - 16) / 3) % 3]
        // Modular arithmetic keeps generation bounded even at very large stage numbers.
        let fills = [0.30, 0.45, 0.65, 0.38, 0.55, 0.25, 0.60, 0.42, 0.33, 0.52, 0.68, 0.47]
        let fill = fills[(number - 1) % fills.count]
        let comfortable = 0.38 + (fill - 0.25) * 0.65 + (liquid.density - 1) * 0.30
        // Beginner rooms are forgiving; the approved journey then asks for precision.
        let baseDegrees = WorldJourney.leanDegrees(at: number)
        let level = number <= TutorialGuide.stageCount ? 0 : min(2, max(0, precisionLevel))
        let challengeDegrees = max(1, baseDegrees * (1 - Double(level) * 0.1))
        // Starting with the 30th miss, widen by one degree per miss. No side landings.
        let assistanceDegrees = failedAttempts < 30 ? 0 : Double(min(30, failedAttempts - 29))
        let allowedDegrees = min(30, challengeDegrees + assistanceDegrees)
        return .init(number: number, fill: fill, liquid: liquid,
                     comfortableStrength: comfortable, leanRatio: tan(allowedDegrees * .pi / 180))
    }
    /// A bounded sample for developer checks; gameplay generates stages on demand.
    public static let validationSamples = [1, 5, 6, 10, 15, 20, 21, 30, 40, 41, 80, 81, 105, 120].map { at($0) }
        + [at(105, failedAttempts: 30), at(105, failedAttempts: 40), at(105, failedAttempts: 60)]
        + [at(26, precisionLevel: 1), at(31, precisionLevel: 2), at(105, precisionLevel: 2), at(120, precisionLevel: 2)]
}

public enum RoundPhase: Equatable, Codable, Sendable {
    case ready, flying, result(success: Bool)
}

public struct RoundState: Equatable, Codable, Sendable {
    public private(set) var stageNumber: Int
    public private(set) var attemptsUsed = 0
    public private(set) var phase: RoundPhase = .ready
    public private(set) var lastStrength: Double?
    public private(set) var failedAttempts = 0
    public private(set) var precisionLevel = 0
    public var stage: BottleStage { .at(stageNumber, failedAttempts: failedAttempts, precisionLevel: precisionLevel) }
    public var stageIndex: Int { stageNumber - 1 }
    public var attemptsRemaining: Int { 3 - attemptsUsed }

    public init(stageNumber: Int = 1, failedAttempts: Int = 0, precisionLevel: Int = 0) {
        self.stageNumber = max(1, stageNumber)
        self.failedAttempts = max(0, failedAttempts)
        self.precisionLevel = stageNumber <= TutorialGuide.stageCount ? 0 : min(2, max(0, precisionLevel))
    }

    private enum CodingKeys: String, CodingKey { case stageNumber, attemptsUsed, phase, lastStrength, failedAttempts, precisionLevel }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stageNumber = try values.decode(Int.self, forKey: .stageNumber)
        attemptsUsed = try values.decode(Int.self, forKey: .attemptsUsed)
        phase = try values.decode(RoundPhase.self, forKey: .phase)
        lastStrength = try values.decodeIfPresent(Double.self, forKey: .lastStrength)
        // Existing installed saves predate adaptive help; preserve their economy/progress.
        failedAttempts = try values.decodeIfPresent(Int.self, forKey: .failedAttempts) ?? 0
        precisionLevel = try values.decodeIfPresent(Int.self, forKey: .precisionLevel) ?? 0
        sanitize()
    }

    @discardableResult
    public mutating func launch(strength: Double) -> Bool {
        guard phase == .ready, attemptsRemaining > 0, strength.isFinite else { return false }
        lastStrength = min(1, max(0, strength))
        attemptsUsed += 1
        phase = .flying
        return true
    }
    @discardableResult
    public mutating func resolve(success: Bool) -> Bool {
        guard phase == .flying else { return false }
        phase = .result(success: success)
        if !success && failedAttempts < Int.max { failedAttempts += 1 }
        return true
    }
    public mutating func continueRound() {
        guard case let .result(success) = phase else { return }
        if success {
            // Int's range is far beyond any playable lifetime; avoid arithmetic overflow.
            if stageNumber < Int.max { stageNumber += 1 }
            attemptsUsed = 0
            failedAttempts = 0
        } else if attemptsRemaining == 0 { attemptsUsed = 0 }
        lastStrength = nil
        phase = .ready
    }
    public mutating func sanitize() {
        stageNumber = max(1, stageNumber)
        failedAttempts = max(0, failedAttempts)
        precisionLevel = stageNumber <= TutorialGuide.stageCount ? 0 : min(2, max(0, precisionLevel))
        attemptsUsed = min(3, max(0, attemptsUsed))
        if phase == .ready && attemptsUsed == 3 { attemptsUsed = 0 }
        if let lastStrength, !lastStrength.isFinite { self.lastStrength = nil }
    }
}

public struct ThrowProfile: Sendable {
    public let strength: Double
    public let fill: Double
    public let initialLift: Double
    public let initialSpin: Double
    public let slowdown: Double
    public static let gravity = 16.0

    public init(strength: Double, stage: BottleStage) {
        self.strength = strength.isFinite ? min(1, max(0, strength)) : 0
        fill = stage.fill
        let massScale = sqrt(stage.effectiveMass / 0.325)
        initialLift = (5.8 + 1.3 * self.strength) / massScale
        slowdown = (1.2 + stage.fill * 1.2) * stage.liquid.damping
        let referenceLift = (5.8 + 1.3 * stage.comfortableStrength) / massScale
        let referenceTime = 2 * referenceLift / Self.gravity
        let referenceIntegral = (1 - exp(-slowdown * referenceTime)) / slowdown
        let referenceSpin = 2 * Double.pi / referenceIntegral
        let difference = self.strength - stage.comfortableStrength
        initialSpin = referenceSpin * (1 + 0.04 * difference + 2.3 * pow(difference, 3))
    }
    public var flightDuration: Double { 2 * initialLift / Self.gravity }
    public var maximumHeight: Double { initialLift * initialLift / (2 * Self.gravity) }
    public func height(at time: Double) -> Double {
        initialLift * time - 0.5 * Self.gravity * time * time
    }
    public func verticalSpeed(at time: Double) -> Double { initialLift - Self.gravity * time }
    public func angle(at time: Double) -> Double {
        initialSpin * (1 - exp(-slowdown * max(0, time))) / slowdown
    }
    public func spin(at time: Double) -> Double { initialSpin * exp(-slowdown * max(0, time)) }
    public var landingAngle: Double { angle(at: contactTime) }
    public static func uprightError(_ angle: Double) -> Double { atan2(sin(angle), cos(angle)) }
    public static func support(at angle: Double) -> Double {
        0.5 * abs(cos(angle)) + 0.15 * abs(sin(angle))
    }
    /// Solve the first descending contact rather than overshooting it by one rendered frame.
    public var contactTime: Double {
        func clearance(_ t: Double) -> Double { 0.5 + height(at: t) - Self.support(at: angle(at: t)) }
        let start = flightDuration / 2
        let end = flightDuration + 0.15
        var previous = start
        for step in 1...128 {
            let next = start + (end - start) * Double(step) / 128
            if clearance(next) <= 0 {
                var low = previous, high = next
                for _ in 0..<40 {
                    let mid = (low + high) / 2
                    if clearance(mid) > 0 { low = mid } else { high = mid }
                }
                return (low + high) / 2
            }
            previous = next
        }
        return end
    }
}

public struct LandingTracker: Sendable {
    private let maximumLean: Double
    private var stableTime = 0.0
    public init(maximumLean: Double = BottleStage.at(1).maximumLean) { self.maximumLean = maximumLean }
    public static func combinedLean(pitch: Double, roll: Double) -> Double {
        acos(min(1, max(-1, cos(pitch) * cos(roll))))
    }
    public mutating func update(delta: Double, touchingTable: Bool, angle: Double,
                                speed: Double, spin: Double, roll: Double = 0) -> Bool {
        let stable = touchingTable && Self.combinedLean(pitch: angle, roll: roll) <= maximumLean + 1e-10
            && abs(speed) < 0.12 && abs(spin) < 0.28
        stableTime = stable ? stableTime + max(0, delta) : 0
        return stableTime >= 0.45
    }
}
