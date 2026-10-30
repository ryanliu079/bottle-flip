import SwiftUI
#if SWIFT_PACKAGE
import GameCore
#endif

struct StagePicker: View {
    @Bindable var model: GameModel
    @State private var world: JourneyWorld?
    @State private var chapter: JourneyChapter?
    @State private var selectedStage: Int

    init(model: GameModel) {
        self.model = model
        _selectedStage = State(initialValue: model.round.stageNumber)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-chapter-map") {
            _world = State(initialValue: model.chapter.world)
            _chapter = State(initialValue: model.chapter)
        }
        #endif
    }
    private var backdrop: JourneyChapter { chapter ?? world?.preview ?? model.chapter }
    private var frontier: Int { model.player.unlockedStageCount }

    var body: some View {
        ZStack {
            SceneryBackground(chapter: backdrop)
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                header
                if let chapter {
                    VStack(spacing: 3) {
                        Text(chapter.title).font(JourneyStyle.font(22, .bold))
                        Text("Stages \(chapter.rangeLabel)").font(JourneyStyle.font(13))
                        if chapter.stages.upperBound <= TutorialGuide.stageCount {
                            Text("Tutorial · Learn to flip · Free retries").font(JourneyStyle.font(12, .semibold))
                        }
                    }.shadow(color: .black, radius: 4)
                } else if let world {
                    Text(world.title).font(JourneyStyle.font(26, .bold)).shadow(color: .black, radius: 4)
                } else {
                    Text("Your journey").font(JourneyStyle.font(26, .bold)).shadow(color: .black, radius: 4)
                }
                ScrollViewReader { proxy in
                ScrollView {
                    if let chapter {
                        stageMap(chapter)
                        legend
                        laterChapters(chapter)
                    } else if let world {
                        chapterCards(world)
                    } else {
                        worldCards
                    }
                }
                .scrollIndicators(.hidden)
                .task(id: chapter?.id) {
                    guard chapter != nil else { return }
                    await Task.yield()
                    proxy.scrollTo(selectedStage, anchor: .center)
                }
                }
                if chapter != nil { stageSelection } else { resumeButton }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 420, height: 740)
        #endif
    }
    private var header: some View {
        HStack(spacing: 5) {
            Button {
                if chapter != nil { chapter = nil }
                else if world != nil { world = nil }
                else { model.showStages = false }
            } label: {
                Label(chapter != nil ? "Chapters" : world != nil ? "Worlds" : "Back", systemImage: "chevron.left")
                    .font(JourneyStyle.font(13, .semibold)).padding(.horizontal, 10)
                    .frame(minHeight: 44).background(JourneyStyle.panel, in: Capsule())
            }.buttonStyle(.plain).accessibilityLabel(chapter != nil ? "Back to chapters" : world != nil ? "Back to worlds" : "Back to game")
            Spacer(minLength: 0)
            JourneyWallet(health: model.player.health, coins: model.player.coins, unlimited: !model.healthEnabled)
        }
    }
    private var worldCards: some View {
        VStack(spacing: 0) {
            if model.player.campaignComplete {
                Label("All 120 stages complete · replay any chapter", systemImage: "checkmark.seal.fill")
                    .font(JourneyStyle.font(14, .semibold)).padding(14).background(JourneyStyle.panel, in: Capsule()).padding(.bottom, 15)
            }
            ForEach(JourneyWorld.allCases) { item in
                Button { world = item } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Spacer(minLength: 55)
                        HStack {
                            Text(item.title).font(JourneyStyle.font(23, .bold))
                            Spacer()
                            Image(systemName: statusIcon(item.stages)).font(.system(size: 23))
                        }
                        Text("Stages \(item.stages.lowerBound)–\(item.stages.upperBound) · \(completed(item.stages))/40 complete")
                            .font(JourneyStyle.font(13, .semibold))
                        HStack(spacing: 5) {
                            ForEach(item.chapters) { sub in
                                Text(sub.title).font(JourneyStyle.font(10, .semibold)).lineLimit(2).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity).frame(height: 200)
                    .background {
                        SceneryImage(chapter: item.preview).overlay(LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(item.stages.contains(frontier) ? JourneyStyle.cyan : .white.opacity(0.4), lineWidth: item.stages.contains(frontier) ? 3 : 1))
                    .opacity(frontier >= item.stages.lowerBound ? 1 : 0.72)
                }
                .buttonStyle(.plain).disabled(frontier < item.stages.lowerBound)
                .accessibilityLabel("\(item.title), stages \(item.stages.lowerBound) through \(item.stages.upperBound), \(frontier < item.stages.lowerBound ? "locked" : "\(completed(item.stages)) completed")")
                .accessibilityHint("Opens the four subchapters")
                .accessibilityIdentifier("world-\(item.rawValue)")
                if item != .ice {
                    Capsule().fill(item.stages.upperBound < frontier ? JourneyStyle.cyan : .white.opacity(0.55)).frame(width: 3, height: 30).padding(.vertical, 3)
                }
            }
        }.padding(.vertical, 4)
    }
    private func chapterCards(_ world: JourneyWorld) -> some View {
        VStack(spacing: 0) {
            ForEach(world.chapters) { item in
                Button { chapter = item; selectedStage = min(item.stages.upperBound, max(item.stages.lowerBound, model.round.stageNumber)) } label: {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(JourneyStyle.font(22, .bold))
                            if item.stages.upperBound <= TutorialGuide.stageCount {
                                Text("Tutorial · Free retries").font(JourneyStyle.font(12, .semibold)).foregroundStyle(JourneyStyle.cyan)
                            }
                            Text("Stages \(item.rangeLabel) · \(completed(item.stages))/10 complete").font(JourneyStyle.font(13, .semibold))
                        }
                        Spacer()
                        Image(systemName: statusIcon(item.stages)).font(.system(size: 23))
                    }
                    .padding(16).frame(maxWidth: .infinity).frame(height: 150, alignment: .bottom)
                    .background {
                        SceneryImage(chapter: item).overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(item.stages.contains(frontier) ? JourneyStyle.cyan : .white.opacity(0.4), lineWidth: item.stages.contains(frontier) ? 3 : 1))
                }.buttonStyle(.plain).disabled(item.stages.lowerBound > frontier)
                .accessibilityLabel("\(item.title), stages \(item.rangeLabel), \(item.stages.lowerBound > frontier ? "locked" : "\(completed(item.stages)) completed")")
                .accessibilityHint("Opens the ten-stage map")
                .accessibilityIdentifier("chapter-\(item.id)")
                if item.id != world.chapters.last?.id { Capsule().fill(.white.opacity(0.7)).frame(width: 3, height: 25) }
            }
        }.padding(.vertical, 4)
    }
    private func stageMap(_ chapter: JourneyChapter) -> some View {
        GeometryReader { geometry in
            let fractions: [CGFloat] = [0.22, 0.43, 0.75, 0.79, 0.57, 0.24, 0.20, 0.46, 0.78, 0.72]
            let points = fractions.enumerated().map { CGPoint(x: geometry.size.width * $0.element, y: 42 + CGFloat($0.offset) * 65) }
            ZStack {
                ForEach(1..<points.count, id: \.self) { index in
                    let locked = chapter.stages.lowerBound + index > frontier
                    Path { path in
                        let midY = (points[index - 1].y + points[index].y) / 2
                        path.move(to: points[index - 1])
                        path.addCurve(to: points[index], control1: .init(x: points[index - 1].x, y: midY), control2: .init(x: points[index].x, y: midY))
                    }.stroke(locked ? .white.opacity(0.65) : JourneyStyle.cyan.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: locked ? [6, 6] : []))
                }
                ForEach(Array(chapter.stages), id: \.self) { number in
                    let complete = model.player.hasCompleted(number)
                    let locked = number > frontier
                    Button { selectedStage = number } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Text("\(number)").font(JourneyStyle.font(22, .bold)).frame(width: 58, height: 58)
                                .background(number == frontier ? JourneyStyle.blue : complete ? Color(red: 0.04, green: 0.32, blue: 0.25) : JourneyStyle.panel, in: Circle())
                                .overlay(Circle().stroke(number == frontier || number == selectedStage ? JourneyStyle.cyan : .white.opacity(0.8), lineWidth: number == selectedStage ? 4 : 2))
                                .shadow(color: number == frontier ? JourneyStyle.cyan.opacity(0.7) : .black.opacity(0.4), radius: number == frontier ? 12 : 4)
                            if complete || locked {
                                Image(systemName: locked ? "lock.fill" : "checkmark")
                                    .font(.system(size: 11, weight: .bold)).frame(width: 23, height: 23)
                                    .background(locked ? Color.gray.opacity(0.95) : Color.green.opacity(0.9), in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 1))
                            }
                        }
                    }.buttonStyle(.plain).id(number).position(points[number - chapter.stages.lowerBound])
                    .accessibilityLabel("Stage \(number), \(locked ? "locked" : complete ? "completed" : "current frontier")\(number == selectedStage ? ", selected" : "")")
                }
            }
        }.frame(height: 675)
    }
    private var legend: some View {
        HStack(spacing: 15) {
            Label("Completed", systemImage: "checkmark.circle.fill")
            Label("Current", systemImage: "circle")
            Label("Locked", systemImage: "lock.circle")
        }.font(JourneyStyle.font(11, .semibold)).padding(12).frame(maxWidth: .infinity).background(JourneyStyle.panel, in: Capsule())
    }
    private func laterChapters(_ current: JourneyChapter) -> some View {
        HStack(spacing: 8) {
            ForEach(current.world.chapters.filter { $0.stages.lowerBound > current.stages.upperBound }) { item in
                VStack(spacing: 4) {
                    SceneryImage(chapter: item).frame(width: 65, height: 65).clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
                    Text(item.title).font(JourneyStyle.font(11, .semibold)).lineLimit(2)
                    Text(item.rangeLabel).font(JourneyStyle.font(10))
                    if item.stages.lowerBound > frontier { Image(systemName: "lock.fill").font(.system(size: 11)) }
                }.frame(maxWidth: .infinity)
            }
        }.padding(.vertical, 15)
    }
    private var stageSelection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stage \(selectedStage)").font(JourneyStyle.font(21, .bold))
                Text(selectedStage > frontier ? "Clear stage \(selectedStage - 1) to unlock" : model.player.hasCompleted(selectedStage) ? "Replay clear +1 coin" : "First clear +10 coins")
                    .font(JourneyStyle.font(12)).lineLimit(2)
            }
            Spacer()
            Button { model.selectStage(selectedStage) } label: {
                Text("Play").font(JourneyStyle.font(19, .bold)).frame(width: 100, height: 50)
                    .background(JourneyStyle.blue, in: Capsule())
            }.buttonStyle(.plain).disabled(selectedStage > frontier).opacity(selectedStage > frontier ? 0.45 : 1)
            .accessibilityLabel("Play stage \(selectedStage)")
        }.padding(14).background(JourneyStyle.panel, in: RoundedRectangle(cornerRadius: 18))
    }
    private var resumeButton: some View {
        Button { model.selectStage(frontier) } label: {
            Text(model.player.campaignComplete ? "Replay Stage 120" : "Continue · Stage \(frontier)")
                .font(JourneyStyle.font(17, .bold)).frame(maxWidth: .infinity, minHeight: 50)
                .background(JourneyStyle.blue, in: Capsule())
        }.buttonStyle(.plain)
    }
    private func completed(_ range: ClosedRange<Int>) -> Int {
        max(0, min(range.upperBound, model.player.highestCompletedStage) - range.lowerBound + 1)
    }
    private func statusIcon(_ range: ClosedRange<Int>) -> String {
        frontier < range.lowerBound ? "lock.fill" : model.player.highestCompletedStage >= range.upperBound ? "checkmark.circle.fill" : "location.circle.fill"
    }
}
