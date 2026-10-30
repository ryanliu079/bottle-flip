import SwiftUI
import Observation
#if SWIFT_PACKAGE
import GameCore
#endif
#if os(iOS)
import UIKit
#endif

@MainActor @Observable
final class GameModel {
    private(set) var player: PlayerProgress
    var round: RoundState { player.round }
    /// Development builds allow uninterrupted play without changing the saved health balance.
    var healthEnabled: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
    var message = "Flip the bottle."
    var detail = "Land on the base within three tries."
    var lastStrength: Double?
    var isActive = true
    var isMotionReady = false
    var motionAvailable = false
    var testStrength = 0.42
    var testDirection = 1.0
    var showControls = false
    var showHelp = false
    var showShop = false
    var showStages = false
    var isPaused = false
    private(set) var musicEnabled = UserDefaults.standard.object(forKey: "musicEnabled") as? Bool ?? true
    var chapter: JourneyChapter { WorldJourney.chapter(at: round.stageNumber) }
    var finalClear: Bool { result == true && round.stageNumber == WorldJourney.stageCount }
    var isTutorial: Bool { round.stage.isTutorial }
    var stageUsesHealth: Bool { healthEnabled && !isTutorial }
    var tutorialGraduation: Bool { result == true && round.stageNumber == 20 && player.lastReward == 10 }
    var tutorialInstruction: String? {
        guard isTutorial, player.tutorialHintsEnabled, result != true, !isFlying else { return nil }
        // Teach the first gestures, then let players practise independently between new lessons.
        guard round.stageNumber <= 5 || [6, 11, 16].contains(round.stageNumber) || round.failedAttempts > 0 else { return nil }
        return TutorialGuide.instruction(at: round.stageNumber)
    }
    var precisionChallenge: Bool {
        round.stage.maximumLean + 1e-10 < BottleStage.at(round.stageNumber, failedAttempts: round.failedAttempts).maximumLean
    }
    var shopMessage: String?
    var saveError: String?
    let scene = BottleScene()
    let motion = MotionController()
    private let landingFeedback = LandingFeedback()
    private let soundtrack = SoundtrackPlayer()
    private var landingWatchdog: Task<Void, Never>?
    private let store: ProgressStore?
    private var savingAllowed = true
    private var isAutomatedRun: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--validate-landings")
            || ProcessInfo.processInfo.arguments.contains("--validate-rounds")
            || ProcessInfo.processInfo.arguments.contains("--validate-music")
            || ProcessInfo.processInfo.arguments.contains("--preview-throw")
        #else
        return false
        #endif
    }
    #if DEBUG
    private var validation: SceneValidation?
    private var roundValidation: RoundValidation?
    private var musicValidation: SoundtrackValidation?
    var musicSnapshot: [String: Any] { soundtrack.snapshot }
    func seekMusicNearLoopEnd() { soundtrack.seekNearLoopEnd() }
    var impactFeedbackCounts: (impacts: Int, sounds: Int, recorded: Bool) {
        (landingFeedback.impactCount, landingFeedback.playbackCount, landingFeedback.recordedSoundsReady)
    }
    var physicalFeedbackCounts: (contacts: Int, body: Int, patterns: Int, celebrations: Int, bodySounds: Int, supported: Bool) {
        let values = landingFeedback.contactCounts
        return (values.contacts, values.body, values.patterns, landingFeedback.celebrationCount,
                landingFeedback.bodyPlaybackCount, values.supported)
    }
    func resetValidation(stageNumber: Int = 1) {
        guard isAutomatedRun else { return }
        player = .init(stageNumber: stageNumber)
        lastStrength = nil
        configureScene()
        updateLabels()
    }
    func beginValidationIfRequested() {
        if musicValidation == nil, ProcessInfo.processInfo.arguments.contains("--validate-music") {
            musicValidation = SoundtrackValidation(model: self)
            musicValidation?.start()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-throw") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, self.result == nil else { return }
                self.launch(strength: self.round.stage.comfortableStrength)
            }
            return
        }
        if roundValidation == nil, ProcessInfo.processInfo.arguments.contains("--validate-rounds") {
            motion.stop()
            roundValidation = RoundValidation(model: self)
            roundValidation?.start()
            return
        }
        guard validation == nil, ProcessInfo.processInfo.arguments.contains("--validate-landings") else { return }
        motion.stop()
        validation = SceneValidation(scene: scene)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.validation?.start()
        }
    }
    #endif

    var isReady: Bool {
        #if DEBUG
        if validation != nil { return false }
        #endif
        return player.canPlay(usesHealth: healthEnabled) && isActive && !isPaused && !showShop && !showHelp && !showStages
    }
    var isFlying: Bool { round.phase == .flying }
    var result: Bool? {
        if case let .result(success) = round.phase { return success }
        return nil
    }
    var actionTitle: String {
        if finalClear { return "View journey" }
        if tutorialGraduation { return "Explore the Garden" }
        if result == true { return "Next stage" }
        return round.attemptsRemaining == 0 ? "Retry stage" : "Try again"
    }
    var readinessLabel: String {
        #if DEBUG
        if validation != nil { return "Testing landings" }
        #endif
        if !isActive || isPaused { return "Paused" }
        if isFlying { return "In the air" }
        if let result { return result ? "Landed!" : "Try again" }
        if stageUsesHealth && player.health == 0 { return "Rest for today" }
        if !motionAvailable { return "Ready to flick" }
        return isMotionReady ? "Ready to flick" : "Hold steady"
    }
    var statusInstruction: String {
        #if DEBUG
        if validation != nil { return "Automatic checks are running." }
        #endif
        if isFlying { return "Watch the bottle land." }
        if result == true { return "Another stage, another challenge." }
        if stageUsesHealth && player.health == 0 { return "Your health refills at midnight." }
        if result != nil { return "Adjust your flick and try again." }
        if !motionAvailable { return "Use the practice controls below." }
        return isMotionReady ? "Make a small upward wrist flick." : "Keep your phone still for a moment."
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        var temporary = false
        #if DEBUG
        temporary = arguments.contains("--validate-landings") || arguments.contains("--validate-rounds") || arguments.contains("--validate-music")
            || arguments.contains("--preview-shop") || arguments.contains("--preview-empty")
            || arguments.contains("--preview-wine") || arguments.contains("--preview-stage")
            || arguments.contains("--preview-map") || arguments.contains("--preview-chapter-map") || arguments.contains("--preview-throw")
        #endif
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = temporary ? nil : ProgressStore(url: directory.appendingPathComponent("BottleFlip/player-v1.json"))
        player = .init()
        do { if let saved = try store?.load() { player = saved } }
        catch {
            // Preserve an unreadable or newer save instead of silently overwriting purchases.
            savingAllowed = false
            saveError = "Your saved game could not be opened. The original save has been kept."
        }
        player.restoreInterruptedRound(usesHealth: healthEnabled)
        if healthEnabled { player.refreshHealth(now: Date()) }
        #if DEBUG
        if arguments.contains("--preview-shop") {
            for _ in 0..<15 {
                player.launch(strength: 0.5); player.resolve(success: true); player.continueRound()
            }
            showShop = true
        }
        if arguments.contains("--preview-wine") {
            player = .init(stageNumber: 11)
            for _ in 0..<30 {
                player.launch(strength: 0.5); player.resolve(success: true); player.continueRound()
            }
            player.select(BottleAppearance.rose); player.select(TableAppearance.walnut)
        }
        if arguments.contains("--preview-empty") {
            for _ in 0..<30 {
                player.launch(strength: 0.5); player.resolve(success: false); player.continueRound()
            }
        }
        if let index = arguments.firstIndex(of: "--preview-stage"), arguments.indices.contains(index + 1), let number = Int(arguments[index + 1]) {
            player = .init()
            for _ in 1..<min(121, max(1, number)) {
                player.launch(strength: 0.5, usesHealth: false)
                player.resolve(success: true, usesHealth: false)
                player.continueRound()
            }
        }
        if arguments.contains("--preview-map") || arguments.contains("--preview-chapter-map") { showStages = true }
        #endif
        scene.onResult = { [weak self] success, hint in self?.finish(success: success, hint: hint) }
        scene.onImpact = { [weak self] strength in self?.landingFeedback.impact(strength: strength) }
        scene.onTableContact = { [weak self] contact in self?.landingFeedback.contact(contact) }
        motion.onThrow = { [weak self] strength, direction in self?.launch(strength: strength, direction: direction) }
        motion.onReadiness = { [weak self] ready in self?.isMotionReady = ready }
        configureScene()
        updateLabels()
        save()
    }
    private func save() {
        guard savingAllowed else { return }
        do { try store?.save(player) }
        catch { saveError = "Your latest progress could not be saved. Please make room on your device and try again." }
    }
    func refreshDailyHealth() {
        guard healthEnabled else { return }
        if player.refreshHealth(now: Date()) {
            save()
            updateLabels()
            updateMotion()
        }
    }
    private func configureScene() {
        soundtrack.select(stage: round.stageNumber)
        scene.bottleAppearance = player.bottleAppearance
        scene.tableAppearance = player.tableAppearance
        scene.configure(stage: round.stage)
        testStrength = round.stage.comfortableStrength
        scene.publishRenderPose()
    }
    private var rewardText: String { "+\(player.lastReward) \(player.lastReward == 1 ? "coin" : "coins")" }
    private func updateLabels() {
        if let result {
            message = result ? "Congratulations!" : "Try another flip"
            if isTutorial {
                detail = result ? rewardText : round.attemptsRemaining == 0
                    ? "Keep practising. Tutorial retries are free." : "Adjust your flick and try again."
            } else if healthEnabled {
                detail = result ? "\(rewardText) · Health kept" : round.attemptsRemaining == 0
                    ? "Stage missed. −1 health." : "Adjust your flick. Health stays until all three misses."
            } else {
                detail = result ? rewardText : round.attemptsRemaining == 0
                    ? "Try this stage again. Unlimited testing." : "Adjust your flick and try again."
            }
        } else if stageUsesHealth && player.health == 0 {
            message = "A fresh start tomorrow"
            detail = "Your coins and stage are saved."
        } else {
            message = "Flip the bottle."
            detail = "Land on the base within three tries."
        }
    }
    func setTutorialHints(_ enabled: Bool) {
        player.setTutorialHints(enabled)
        save()
    }
    func setMusicEnabled(_ enabled: Bool) {
        musicEnabled = enabled
        if store != nil { UserDefaults.standard.set(enabled, forKey: "musicEnabled") }
        updateSoundtrack()
    }
    private func updateSoundtrack() {
        soundtrack.setActive(isActive && !isPaused && musicEnabled)
    }
    func activate(_ active: Bool) {
        isActive = active
        scene.isPaused = !active || isPaused
        updateSoundtrack()
        if active { refreshDailyHealth() } else { landingFeedback.pause(); save() }
        updateMotion()
    }
    func setPaused(_ paused: Bool) {
        isPaused = paused
        scene.isPaused = paused || !isActive
        updateSoundtrack()
        if paused { landingFeedback.pause() }
        updateMotion()
    }
    func updateMotion() {
        if isReady && !showControls && !isAutomatedRun {
            motionAvailable = motion.start()
        } else { motion.stop(); isMotionReady = false }
    }
    func launch(strength: Double, direction: Double = 1) {
        #if DEBUG
        guard validation == nil else { return }
        #endif
        refreshDailyHealth()
        guard isReady, player.launch(strength: strength, usesHealth: healthEnabled) else { return }
        save()
        motion.stop()
        isMotionReady = false
        lastStrength = round.lastStrength
        showControls = false
        message = "Flipping…"
        detail = "Wait for the bottle to land."
        scene.throwDirection = direction
        landingFeedback.prepare()
        landingFeedback.beganThrow(strength: round.lastStrength ?? 0)
        scene.launch(strength: round.lastStrength ?? 0, stage: round.stage)
        landingWatchdog?.cancel()
        landingWatchdog = Task { @MainActor [weak self] in
            var activeTime = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.isFlying else { return }
                if self.isActive && !self.isPaused { activeTime += 0.1 }
                if activeTime >= 4.5 { self.scene.finishInterruptedThrow(); return }
            }
        }
    }
    private func finish(success: Bool, hint: String) {
        refreshDailyHealth()
        guard player.resolve(success: success, usesHealth: healthEnabled) else { return }
        save()
        landingWatchdog?.cancel()
        landingWatchdog = nil
        updateLabels()
        if !success && round.attemptsRemaining > 0 { detail = hint }
        if success { soundtrack.duckForCelebration(); landingFeedback.celebrate() }
    }
    func continueRound() {
        guard result != nil else { return }
        refreshDailyHealth()
        let completedCampaign = finalClear
        player.continueRound()
        if completedCampaign { showStages = true }
        save()
        configureScene()
        lastStrength = nil
        updateLabels()
        updateMotion()
    }
    func selectStage(_ number: Int) {
        guard !isFlying, player.selectStage(number) else { return }
        showStages = false
        lastStrength = nil
        save()
        configureScene()
        updateLabels()
        updateMotion()
    }
    func select(_ appearance: BottleAppearance) {
        guard !isFlying else { return }
        let result = player.select(appearance)
        shopMessage = result == .insufficientCoins ? "Earn more coins to unlock \(appearance.title)." : "\(appearance.title) equipped."
        save()
        scene.bottleAppearance = player.bottleAppearance
        scene.publishRenderPose()
    }
    func select(_ appearance: TableAppearance) {
        guard !isFlying else { return }
        let result = player.select(appearance)
        shopMessage = result == .insufficientCoins ? "Earn more coins to unlock \(appearance.title)." : "\(appearance.title) equipped."
        save()
        scene.tableAppearance = player.tableAppearance
        scene.publishRenderPose()
    }
}
