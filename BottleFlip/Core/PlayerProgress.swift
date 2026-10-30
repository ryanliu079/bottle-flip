import Foundation

public struct AppearanceColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}

public enum BottleAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, mint, rose, midnight
    public var id: String { rawValue }
    public var title: String {
        switch self { case .classic: "Classic"; case .mint: "Mint"; case .rose: "Rose"; case .midnight: "Midnight" }
    }
    public var price: Int {
        switch self { case .classic: 0; case .mint: 50; case .rose: 100; case .midnight: 150 }
    }
    public var color: AppearanceColor {
        switch self {
        case .classic: .init(0.59, 0.72, 0.82)
        case .mint: .init(0.30, 0.80, 0.60)
        case .rose: .init(0.94, 0.44, 0.58)
        case .midnight: .init(0.26, 0.36, 0.65)
        }
    }
    public var capColor: AppearanceColor {
        switch self {
        case .classic: .init(0.025, 0.14, 0.42)
        case .mint: .init(0.06, 0.37, 0.25)
        case .rose: .init(0.62, 0.12, 0.29)
        case .midnight: .init(0.74, 0.57, 0.22)
        }
    }
}

public enum TableAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case oak, walnut, porcelain, slate
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var price: Int {
        switch self { case .oak: 0; case .walnut: 100; case .porcelain: 150; case .slate: 200 }
    }
    public var color: AppearanceColor {
        switch self {
        case .oak: .init(0.72, 0.54, 0.36)
        case .walnut: .init(0.34, 0.20, 0.12)
        case .porcelain: .init(0.88, 0.88, 0.83)
        case .slate: .init(0.19, 0.24, 0.29)
        }
    }
}

public enum PurchaseResult: Equatable, Sendable { case purchased, equipped, insufficientCoins }

/// One save contains the round and economy so an accepted result cannot be paid twice on reload.
public struct PlayerProgress: Equatable, Codable, Sendable {
    public private(set) var round: RoundState
    public private(set) var coins = 0
    public private(set) var health = 10
    public private(set) var lastHealthRefill: Date
    public private(set) var ownedBottles: Set<BottleAppearance> = [.classic]
    public private(set) var ownedTables: Set<TableAppearance> = [.oak]
    public private(set) var bottleAppearance: BottleAppearance = .classic
    public private(set) var tableAppearance: TableAppearance = .oak
    public private(set) var highestCompletedStage = 0
    public private(set) var lastReward = 0
    public private(set) var tutorialHintsEnabled = true
    public private(set) var firstTryStreak = 0
    public private(set) var precisionLevel = 0
    public private(set) var lastStreakMilestone = false
    private var stageMisses: [Int: Int] = [:]
    private var stagePrecision: [Int: Int] = [:]
    public var unlockedStageCount: Int { min(WorldJourney.stageCount, highestCompletedStage < Int.max ? highestCompletedStage + 1 : Int.max) }
    public var campaignComplete: Bool { highestCompletedStage >= WorldJourney.stageCount }
    public func hasCompleted(_ number: Int) -> Bool { number >= 1 && number <= highestCompletedStage }
    public init(now: Date = Date(), stageNumber: Int = 1) {
        round = .init(stageNumber: stageNumber)
        lastHealthRefill = now
        highestCompletedStage = max(0, round.stageNumber - 1)
    }
    private enum CodingKeys: String, CodingKey {
        case round, coins, health, lastHealthRefill, ownedBottles, ownedTables, bottleAppearance, tableAppearance
        case highestCompletedStage, lastReward, stageMisses, tutorialHintsEnabled
        case firstTryStreak, precisionLevel, lastStreakMilestone, stagePrecision
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        round = try values.decode(RoundState.self, forKey: .round)
        coins = try values.decode(Int.self, forKey: .coins)
        health = try values.decode(Int.self, forKey: .health)
        lastHealthRefill = try values.decode(Date.self, forKey: .lastHealthRefill)
        ownedBottles = try values.decode(Set<BottleAppearance>.self, forKey: .ownedBottles)
        ownedTables = try values.decode(Set<TableAppearance>.self, forKey: .ownedTables)
        bottleAppearance = try values.decode(BottleAppearance.self, forKey: .bottleAppearance)
        tableAppearance = try values.decode(TableAppearance.self, forKey: .tableAppearance)
        let savedSuccess = round.phase == .result(success: true)
        let legacyHighest = savedSuccess ? round.stageNumber : max(0, round.stageNumber - 1)
        highestCompletedStage = max(0, try values.decodeIfPresent(Int.self, forKey: .highestCompletedStage) ?? legacyHighest)
        lastReward = try values.decodeIfPresent(Int.self, forKey: .lastReward) ?? (savedSuccess ? 10 : 0)
        stageMisses = try values.decodeIfPresent([Int: Int].self, forKey: .stageMisses) ?? [:]
        tutorialHintsEnabled = try values.decodeIfPresent(Bool.self, forKey: .tutorialHintsEnabled) ?? true
        firstTryStreak = min(4, max(0, try values.decodeIfPresent(Int.self, forKey: .firstTryStreak) ?? 0))
        precisionLevel = min(2, max(0, try values.decodeIfPresent(Int.self, forKey: .precisionLevel) ?? 0))
        lastStreakMilestone = try values.decodeIfPresent(Bool.self, forKey: .lastStreakMilestone) ?? false
        stagePrecision = try values.decodeIfPresent([Int: Int].self, forKey: .stagePrecision) ?? [:]
        if !savedSuccess && round.failedAttempts > 0 { stageMisses[round.stageNumber] = round.failedAttempts }
    }
    public mutating func setTutorialHints(_ enabled: Bool) { tutorialHintsEnabled = enabled }
    public var canPlay: Bool { canPlay(usesHealth: true) }
    public func canPlay(usesHealth: Bool) -> Bool {
        (!usesHealth || round.stage.isTutorial || health > 0) && round.phase == .ready
    }
    public func nextRefill(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(86400)
    }
    @discardableResult
    public mutating func refreshHealth(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard now >= lastHealthRefill,
              calendar.startOfDay(for: now) > calendar.startOfDay(for: lastHealthRefill) else { return false }
        health = 10
        lastHealthRefill = now
        return true
    }
    @discardableResult
    public mutating func launch(strength: Double, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent, usesHealth: Bool = true) -> Bool {
        if usesHealth { refreshHealth(now: now, calendar: calendar) }
        guard canPlay(usesHealth: usesHealth) else { return false }
        return round.launch(strength: strength)
    }
    @discardableResult
    public mutating func resolve(success: Bool, usesHealth: Bool = true) -> Bool {
        guard round.resolve(success: success) else { return false }
        lastReward = 0
        lastStreakMilestone = false
        let isNewChallenge = !round.stage.isTutorial && !hasCompleted(round.stageNumber)
        if success {
            if isNewChallenge {
                if round.attemptsUsed == 1 && round.failedAttempts == 0 {
                    firstTryStreak += 1
                    if firstTryStreak == 5 {
                        precisionLevel = min(2, precisionLevel + 1)
                        firstTryStreak = 0
                        lastStreakMilestone = true
                    }
                } else { firstTryStreak = 0 }
            }
            lastReward = hasCompleted(round.stageNumber) ? 1 : 10
            coins = coins <= Int.max - lastReward ? coins + lastReward : Int.max
            highestCompletedStage = max(highestCompletedStage, round.stageNumber)
            stageMisses.removeValue(forKey: round.stageNumber)
            stagePrecision.removeValue(forKey: round.stageNumber)
        } else {
            stageMisses[round.stageNumber] = round.failedAttempts
            if isNewChallenge {
                firstTryStreak = 0
                if round.attemptsRemaining == 0 {
                    // Apply relief when preparing the retry, never alter an in-progress throw.
                    precisionLevel = 0
                    stagePrecision[round.stageNumber] = 0
                }
            }
            if usesHealth && !round.stage.isTutorial && round.attemptsRemaining == 0 { health = max(0, health - 1) }
        }
        return true
    }
    public mutating func continueRound() {
        guard case .result = round.phase else { return }
        let success = round.phase == .result(success: true)
        let retry = !success && round.attemptsRemaining == 0
        round.continueRound()
        if success || retry {
            let next = min(WorldJourney.stageCount, round.stageNumber)
            prepareRound(at: next)
        }
        lastReward = 0
        lastStreakMilestone = false
    }
    private mutating func prepareRound(at number: Int) {
        let level = number > TutorialGuide.stageCount && !hasCompleted(number)
            ? (stagePrecision[number] ?? precisionLevel) : 0
        stagePrecision[number] = level
        round = .init(stageNumber: number, failedAttempts: stageMisses[number] ?? 0, precisionLevel: level)
    }
    @discardableResult
    public mutating func selectStage(_ number: Int) -> Bool {
        guard round.phase != .flying, number >= 1, number <= unlockedStageCount else { return false }
        // Choosing the current stage must not reset its partially used attempts.
        if number == round.stageNumber {
            if round.phase == .ready { return true }
            if round.phase == .result(success: false) {
                continueRound()
                return true
            }
        }
        // Leaving a partially played stage must preserve its challenge on return.
        if stagePrecision[round.stageNumber] == nil && round.phase != .result(success: true) {
            stagePrecision[round.stageNumber] = round.precisionLevel
        }
        prepareRound(at: number)
        lastReward = 0
        lastStreakMilestone = false
        return true
    }
    public mutating func restoreInterruptedRound(usesHealth: Bool = true) {
        round.sanitize()
        coins = max(0, coins); health = min(10, max(0, health))
        ownedBottles.insert(.classic); ownedTables.insert(.oak)
        if !ownedBottles.contains(bottleAppearance) { bottleAppearance = .classic }
        if !ownedTables.contains(tableAppearance) { tableAppearance = .oak }
        if round.phase == .flying { resolve(success: false, usesHealth: usesHealth) }
        // Keep legacy lifetime completion, wallet and ownership; bring the playable round into this campaign.
        if round.stageNumber > WorldJourney.stageCount {
            round = .init(stageNumber: WorldJourney.stageCount, failedAttempts: stageMisses[WorldJourney.stageCount] ?? 0)
            lastReward = 0
        }
    }
    @discardableResult
    public mutating func select(_ appearance: BottleAppearance) -> PurchaseResult {
        if ownedBottles.contains(appearance) { bottleAppearance = appearance; return .equipped }
        guard coins >= appearance.price else { return .insufficientCoins }
        coins -= appearance.price
        ownedBottles.insert(appearance); bottleAppearance = appearance
        return .purchased
    }
    @discardableResult
    public mutating func select(_ appearance: TableAppearance) -> PurchaseResult {
        if ownedTables.contains(appearance) { tableAppearance = appearance; return .equipped }
        guard coins >= appearance.price else { return .insufficientCoins }
        coins -= appearance.price
        ownedTables.insert(appearance); tableAppearance = appearance
        return .purchased
    }
}
