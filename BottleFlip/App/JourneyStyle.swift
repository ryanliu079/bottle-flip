import SwiftUI
#if SWIFT_PACKAGE
import GameCore
#endif
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum JourneyStyle {
    static let cyan = Color(red: 0.08, green: 0.79, blue: 0.95)
    static let blue = Color(red: 0.02, green: 0.40, blue: 0.93)
    static let panel = Color.black.opacity(0.58)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Arial", size: size).weight(weight)
    }
    static func sceneryURL(_ id: String) -> URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: id + "-v2", withExtension: "png", subdirectory: "Scenery")
            ?? bundle.url(forResource: id, withExtension: "png", subdirectory: "Scenery")
    }
}

struct SceneryImage: View {
    let chapter: JourneyChapter
    var body: some View {
        if let url = JourneyStyle.sceneryURL(chapter.id) {
            #if os(iOS)
            if let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFill() }
            #else
            if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFill() }
            #endif
        } else {
            LinearGradient(colors: [.init(red: 0.18, green: 0.30, blue: 0.40), .init(red: 0.52, green: 0.65, blue: 0.69)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct SceneryBackground: View {
    let chapter: JourneyChapter
    var body: some View {
        GeometryReader { geometry in
            SceneryImage(chapter: chapter).frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct JourneyWallet: View {
    let health: Int
    let coins: Int
    let unlimited: Bool
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                Text(unlimited ? "∞" : "\(health)").monospacedDigit()
            }
            .padding(.horizontal, 10).frame(height: 38).background(JourneyStyle.panel, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(unlimited ? "Unlimited health in this test build" : "\(health) health")
            HStack(spacing: 5) {
                Image(systemName: "circle.circle.fill").foregroundStyle(.yellow)
                Text("\(coins)").monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 10).frame(height: 38).background(JourneyStyle.panel, in: Capsule())
            .accessibilityElement(children: .ignore).accessibilityLabel("\(coins) coins")
        }
        .font(JourneyStyle.font(15, .semibold)).foregroundStyle(.white)
    }
}
