import SwiftUI
import SpriteKit
#if SWIFT_PACKAGE
import GameCore
#endif

private enum Palette {
    static let background = Color(red: 0.88, green: 0.91, blue: 0.94)
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.15)
    static let muted = Color(red: 0.37, green: 0.45, blue: 0.43)
    static let teal = JourneyStyle.blue
}

struct GameView: View {
    @State private var model = GameModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SceneryBackground(chapter: model.chapter)
            SpriteView(scene: model.scene, options: [.allowsTransparency])
                .opacity(0.001).allowsHitTesting(false).accessibilityHidden(true)
                .padding(.bottom, 85)
            RealisticSceneView(scene: model.scene)
                .padding(.bottom, 85).allowsHitTesting(false)
                .accessibilityLabel("Bottle with \(Int((model.round.stage.fill * 100).rounded())) percent \(model.round.stage.liquid.title) on the \(model.chapter.title) landing surface")
                .accessibilityValue(model.message)
            LinearGradient(stops: [.init(color: .black.opacity(0.40), location: 0), .init(color: .clear, location: 0.28), .init(color: .clear, location: 0.66), .init(color: .black.opacity(0.60), location: 1)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            if model.result == true && !reduceMotion {
                LandingCelebration().id(model.round.stageNumber).allowsHitTesting(false).accessibilityHidden(true)
            }
            VStack(spacing: 12) {
                hud
                VStack(spacing: 3) {
                    Text(model.chapter.world.title).font(JourneyStyle.font(13))
                    Text(model.chapter.title).font(JourneyStyle.font(24, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    Text("Stage \(model.round.stageNumber)").font(JourneyStyle.font(15, .semibold))
                }
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                .accessibilityElement(children: .combine)
                learningStatus
                Spacer(minLength: 20)
                feedback
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            if model.isPaused { pausePanel }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .sheet(isPresented: $model.showControls) { prototypeControls.preferredColorScheme(.light) }
        .sheet(isPresented: $model.showHelp) { help.preferredColorScheme(.light) }
        .sheet(isPresented: $model.showShop) { AppearanceShop(model: model).preferredColorScheme(.light) }
        #if os(iOS)
        .fullScreenCover(isPresented: $model.showStages) { StagePicker(model: model) }
        #else
        .sheet(isPresented: $model.showStages) { StagePicker(model: model) }
        #endif
        .alert("Save unavailable", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK") { model.saveError = nil }
        } message: { Text(model.saveError ?? "") }
        .task {
            guard model.healthEnabled else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if model.isActive { model.refreshDailyHealth() }
            }
        }
        .onAppear {
            model.activate(true)
            #if DEBUG
            model.beginValidationIfRequested()
            #endif
        }
        .onDisappear { model.activate(false) }
        .onChange(of: scenePhase) { _, phase in model.activate(phase == .active) }
        .onChange(of: model.showControls) { _, _ in model.updateMotion() }
        .onChange(of: model.showHelp) { _, _ in model.updateMotion() }
        .onChange(of: model.showShop) { _, _ in model.updateMotion() }
        .onChange(of: model.showStages) { _, _ in model.updateMotion() }
    }

    private var hud: some View {
        HStack(spacing: 6) {
            Button { model.showStages = true } label: {
                Label("Stages", systemImage: "chevron.left")
                    .font(JourneyStyle.font(14, .semibold)).padding(.horizontal, 12)
                    .frame(minHeight: 44).background(JourneyStyle.panel, in: Capsule())
            }
            .buttonStyle(.plain).disabled(model.isFlying).accessibilityLabel("Open journey map")
            Spacer(minLength: 0)
            JourneyWallet(health: model.player.health, coins: model.player.coins, unlimited: !model.stageUsesHealth)
            Button { model.setPaused(true) } label: {
                Image(systemName: "pause.fill").frame(width: 44, height: 44).background(JourneyStyle.panel, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Pause game")
        }
    }

    private var learningStatus: some View {
        VStack(spacing: 8) {
            if model.isTutorial {
                Text("Tutorial · \(model.round.stageNumber)/20 · Free retries")
                    .font(JourneyStyle.font(12, .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(JourneyStyle.panel, in: Capsule())
                    .accessibilityIdentifier("tutorial-progress")
                if let instruction = model.tutorialInstruction {
                    HStack(alignment: .top, spacing: 6) {
                        Text(instruction).font(JourneyStyle.font(13))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("tutorial-instruction")
                        Button { model.setTutorialHints(false) } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Hide tutorial tips")
                    }
                    .padding(.leading, 14).padding(.vertical, 8).padding(.trailing, 2)
                    .background(JourneyStyle.panel, in: RoundedRectangle(cornerRadius: 16))
                }
            } else if model.precisionChallenge {
                Label("Precision challenge", systemImage: "scope")
                    .font(JourneyStyle.font(12, .semibold)).padding(.horizontal, 14).padding(.vertical, 7)
                    .background(JourneyStyle.panel, in: Capsule())
                    .accessibilityIdentifier("precision-challenge")
            }
        }
    }

    private var feedback: some View {
        VStack(spacing: 9) {
            Text("\(Int((model.round.stage.fill * 100).rounded()))% \(model.round.stage.liquid.title)")
                .font(JourneyStyle.font(14, .semibold)).padding(.horizontal, 16).padding(.vertical, 6)
                .background(JourneyStyle.panel, in: Capsule())
            if model.tutorialGraduation {
                Text("Tutorial complete!").font(JourneyStyle.font(24, .bold))
                    .accessibilityIdentifier("tutorial-complete")
                Text("You've learned the basics. The Garden awaits.\nFirst clear +10")
                    .font(JourneyStyle.font(13)).multilineTextAlignment(.center)
            } else if model.finalClear {
                Text("Journey complete").font(JourneyStyle.font(24, .bold))
                Text("All 120 stages mastered").font(JourneyStyle.font(13))
            } else if model.result == true {
                Text(model.player.lastReward == 10 ? "First clear +10" : "Replay clear +1")
                    .font(JourneyStyle.font(23, .bold)).padding(.horizontal, 20).padding(.vertical, 8)
                    .background(JourneyStyle.panel, in: Capsule())
            } else {
                Text(model.readinessLabel).font(JourneyStyle.font(24, .bold))
                    .foregroundStyle(model.isMotionReady || !model.motionAvailable ? JourneyStyle.cyan : .white)
                    .padding(.horizontal, 22).padding(.vertical, 8)
                    .background(JourneyStyle.panel, in: Capsule())
                    .overlay(Capsule().stroke(JourneyStyle.cyan.opacity(0.8), lineWidth: 1))
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle().fill(index < model.round.attemptsUsed ? .white.opacity(0.25) : JourneyStyle.cyan)
                            .frame(width: 11, height: 11).overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 0.7))
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("\(model.round.attemptsRemaining) attempts remaining")
            }
            if !model.isTutorial && !model.finalClear {
                if model.player.lastStreakMilestone {
                    Text("Five first-try clears! Nicely done.")
                        .font(JourneyStyle.font(13, .semibold)).accessibilityIdentifier("first-try-milestone")
                } else if model.player.firstTryStreak > 0 && !model.player.hasCompleted(model.round.stageNumber) {
                    Text("First-try streak · \(model.player.firstTryStreak)/5")
                        .font(JourneyStyle.font(12)).accessibilityIdentifier("first-try-streak")
                }
            }
            if model.result != nil {
                if model.result == false { Text(model.detail).font(JourneyStyle.font(13)).multilineTextAlignment(.center).lineLimit(2) }
                actionButton(model.actionTitle, action: model.continueRound)
            } else if model.stageUsesHealth && model.player.health == 0 {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let minutes = max(1, Int(ceil(model.player.nextRefill(now: context.date).timeIntervalSince(context.date) / 60)))
                    Text("10 health in \(minutes / 60)h \(minutes % 60)m").font(JourneyStyle.font(14)).monospacedDigit()
                }
            } else {
                if model.motionAvailable || model.isFlying {
                    Label(model.isFlying ? "Watch the bottle land" : "A short wrist flick · keep hold of your phone", systemImage: "hand.draw")
                        .font(JourneyStyle.font(12, .medium)).multilineTextAlignment(.center).frame(minHeight: 30)
                } else {
                    #if DEBUG
                    Button { model.showControls = true } label: {
                        Label("Practice controls", systemImage: "slider.horizontal.3")
                            .font(JourneyStyle.font(12, .medium)).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                    #else
                    Text("Motion input unavailable").font(JourneyStyle.font(12))
                    #endif
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private var pausePanel: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Paused").font(JourneyStyle.font(30, .bold))
                actionButton("Resume") { model.setPaused(false) }
                Toggle("Music", isOn: Binding(get: { model.musicEnabled }, set: model.setMusicEnabled))
                    .tint(JourneyStyle.cyan).accessibilityIdentifier("music-toggle")
                Button("How to play") { model.showHelp = true }
                Button("Collection") { model.showShop = true; model.shopMessage = nil }.disabled(model.isFlying)
                Button("Journey map") { model.setPaused(false); model.showStages = true }.disabled(model.isFlying)
            }
            .font(JourneyStyle.font(17, .semibold)).padding(28).frame(maxWidth: 340)
            .background(JourneyStyle.panel, in: RoundedRectangle(cornerRadius: 24))
        }
    }
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(JourneyStyle.font(17, .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(LinearGradient(colors: [JourneyStyle.cyan, JourneyStyle.blue], startPoint: .top, endPoint: .bottom), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private var prototypeControls: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Practice a throw").font(.custom("Arial", size: 25).weight(.medium))
                Spacer()
                Button("Done") { model.showControls = false }.font(.custom("Arial", size: 12).weight(.semibold))
            }
            Text("These controls let us tune the game without moving a phone. On your iPhone, close this panel and use a wrist flick.")
                .font(.custom("Arial", size: 13)).foregroundStyle(Palette.muted)
            VStack(spacing: 10) {
                HStack {
                    Text("Throw strength")
                    Spacer()
                    Text("\(Int(model.testStrength * 100))%").monospacedDigit()
                }.font(.custom("Arial", size: 13).weight(.medium))
                Slider(value: $model.testStrength, in: 0.05...1).tint(Palette.teal)
                    .accessibilityLabel("Practice throw strength")
                HStack {
                    Text("Gentle")
                    Spacer()
                    Text("Strong")
                }.font(.custom("Arial", size: 10)).foregroundStyle(Palette.muted)
            }
            Picker("Flip direction", selection: $model.testDirection) {
                Text("Toward you").tag(1.0)
                Text("Away from you").tag(-1.0)
            }
            .pickerStyle(.segmented)
            if let strength = model.lastStrength {
                Text("Last throw: \(Int(strength * 100))% strength")
                    .font(.custom("Arial", size: 12)).foregroundStyle(Palette.muted)
            }
            actionButton("Test this throw") { model.launch(strength: model.testStrength, direction: model.testDirection) }
                .disabled(!model.isReady)
                .opacity(model.isReady ? 1 : 0.4)
            Text(model.isTutorial ? "Tutorial practice is free. Your health stays intact." : model.healthEnabled ? "Practice throws use your current stage and daily health." : "Unlimited throws in this test build.")
                .font(.custom("Arial", size: 11)).foregroundStyle(Palette.muted)
        }
        .padding(28)
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        #if os(iOS)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 390, height: 380)
        #endif
    }
    private var help: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("How to flip").font(.custom("Arial", size: 27).weight(.medium))
                Spacer()
                Button("Done") { model.showHelp = false }
            }
            Text("Hold your phone with the screen facing you. Pause briefly, then make a small upward motion with a wrist flick. Keep hold of it throughout.")
            Text("A stronger flick sends the bottle higher and makes it spin faster. Judge the liquid level by looking at the bottle. Different liquids change the feel, and later stages need a more precise landing.")
            Text("Stages 1–20 are your tutorial, with free retries. Stages 1–5 accept a 20° lean; each later tutorial stage asks for a little more precision, reaching 10° at stage 20.")
            Toggle("Tutorial tips", isOn: Binding(get: { model.player.tutorialHintsEnabled }, set: { model.setTutorialHints($0) }))
                .accessibilityIdentifier("tutorial-tips-toggle")
            Text("After the tutorial, clear five new stages in a row on your first throw to tighten the landing tolerance. Precision challenges reduce the allowed lean by at most 20%, with a 1° minimum. Three misses remove the extra challenge on your next retry. Replays do not build the streak.")
            Text(model.healthEnabled ? "A new stage earns 10 coins; a replay earns 1. Successful flips keep your health. After the tutorial, three misses cost one health, then you retry the same stage. Your 10 health refills at local midnight." : "A new stage earns 10 coins; a replay earns 1. Open Stages to choose an unlocked stage. Three misses retry the same stage. This test build has no health limit, so you can keep playing.")
        }
        .font(.custom("Arial", size: 14))
        .foregroundStyle(Palette.ink)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Palette.background)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 390, height: 600)
        #endif
    }
}
