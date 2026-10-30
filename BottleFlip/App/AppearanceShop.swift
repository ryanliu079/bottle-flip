import SwiftUI
#if SWIFT_PACKAGE
import GameCore
#endif

private extension AppearanceColor {
    var swatch: Color { Color(red: red, green: green, blue: blue) }
}

struct AppearanceShop: View {
    @Bindable var model: GameModel
    @State private var category = 0
    private let teal = Color(red: 0.17, green: 0.49, blue: 0.47)
    private let ink = Color(red: 0.10, green: 0.12, blue: 0.15)
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make it yours").font(.custom("Arial", size: 25).weight(.bold))
                    Text("New stage: 10 coins. Replay: 1 coin.")
                        .font(.custom("Arial", size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { model.showShop = false }
                    .font(.custom("Arial", size: 13).weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            HStack {
                Label("\(model.player.coins) coins", systemImage: "circle.circle.fill")
                    .font(.custom("Arial", size: 15).weight(.semibold))
                    .foregroundStyle(Color(red: 0.62, green: 0.43, blue: 0.08))
                Spacer()
                Text("Keep every unlock")
                    .font(.custom("Arial", size: 11)).foregroundStyle(.secondary)
            }
            Picker("Appearance category", selection: $category) {
                Text("Bottles").tag(0)
                Text("Tables").tag(1)
            }.pickerStyle(.segmented)
            ScrollView {
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    if category == 0 {
                        ForEach(BottleAppearance.allCases) { appearance in
                            card(title: appearance.title, price: appearance.price,
                                 owned: model.player.ownedBottles.contains(appearance),
                                 equipped: model.player.bottleAppearance == appearance,
                                 action: { model.select(appearance) }) {
                                BottleSwatch(color: appearance.color.swatch, cap: appearance.capColor.swatch)
                            }
                        }
                    } else {
                        ForEach(TableAppearance.allCases) { appearance in
                            card(title: appearance.title, price: appearance.price,
                                 owned: model.player.ownedTables.contains(appearance),
                                 equipped: model.player.tableAppearance == appearance,
                                 action: { model.select(appearance) }) {
                                TableSwatch(color: appearance.color.swatch, grain: appearance == .oak || appearance == .walnut)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            if let message = model.shopMessage {
                Text(message).font(.custom("Arial", size: 12)).foregroundStyle(teal)
                    .accessibilityLabel(message)
            }
            Text("Appearances keep the same bottle shape and table grip.")
                .font(.custom("Arial", size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .foregroundStyle(ink)
        .background(Color(red: 0.88, green: 0.91, blue: 0.94))
        .tint(teal)
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 390, height: 600)
        #endif
    }
    private func card<Preview: View>(title: String, price: Int, owned: Bool, equipped: Bool,
                                     action: @escaping () -> Void, @ViewBuilder preview: () -> Preview) -> some View {
        VStack(spacing: 10) {
            preview().frame(height: 86).accessibilityHidden(true)
            Text(title).font(.custom("Arial", size: 15).weight(.semibold))
            Text(equipped ? "Your current look" : owned ? "In your collection" : "\(price) coins")
                .font(.custom("Arial", size: 11)).foregroundStyle(.secondary)
            Button(action: action) {
                Text(equipped ? "Equipped" : owned ? "Equip" : "Buy · \(price)")
                    .font(.custom("Arial", size: 12).weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .foregroundStyle(equipped ? teal : .white)
                    .background(equipped ? teal.opacity(0.12) : teal, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(equipped || (!owned && model.player.coins < price))
            .opacity(!owned && model.player.coins < price ? 0.45 : 1)
            .accessibilityLabel(equipped ? "\(title), equipped" : owned ? "Equip \(title)" : "Buy \(title) for \(price) coins")
            if !owned && model.player.coins < price {
                Text("\(price - model.player.coins) more to unlock")
                    .font(.custom("Arial", size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 215, alignment: .top)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(equipped ? teal.opacity(0.55) : .clear, lineWidth: 1.5))
    }
}

private struct BottleSwatch: View {
    let color: Color
    let cap: Color
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: .init(x: 17, y: 12))
                path.addLine(to: .init(x: 17, y: 22))
                path.addQuadCurve(to: .init(x: 6, y: 34), control: .init(x: 6, y: 27))
                path.addLine(to: .init(x: 6, y: 75))
                path.addQuadCurve(to: .init(x: 13, y: 82), control: .init(x: 6, y: 82))
                path.addLine(to: .init(x: 35, y: 82))
                path.addQuadCurve(to: .init(x: 42, y: 75), control: .init(x: 42, y: 82))
                path.addLine(to: .init(x: 42, y: 34))
                path.addQuadCurve(to: .init(x: 31, y: 22), control: .init(x: 42, y: 27))
                path.addLine(to: .init(x: 31, y: 12)); path.closeSubpath()
            }
            .fill(color.opacity(0.65))
            VStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { _ in Capsule().fill(cap.opacity(0.30)).frame(width: 34, height: 2) }
            }.offset(y: 14)
            RoundedRectangle(cornerRadius: 2).fill(cap).frame(width: 19, height: 10).offset(y: -32)
            Capsule().fill(.white.opacity(0.65)).frame(width: 3, height: 36).offset(x: -12, y: 10)
        }.frame(width: 48, height: 86)
    }
}

private struct TableSwatch: View {
    let color: Color
    let grain: Bool
    var body: some View {
        ZStack {
            HStack(spacing: 64) {
                Rectangle().fill(color.opacity(0.80)).frame(width: 9, height: 46)
                Rectangle().fill(color.opacity(0.80)).frame(width: 9, height: 46)
            }.offset(y: 20)
            RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 120, height: 34).offset(y: -3)
            if grain {
                VStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { _ in Capsule().fill(.black.opacity(0.12)).frame(width: 104, height: 1) }
                }.offset(y: -3)
            }
        }.frame(width: 124, height: 86)
    }
}
