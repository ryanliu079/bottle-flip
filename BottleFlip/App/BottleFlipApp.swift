import SwiftUI

@main
struct BottleFlipApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                #if os(macOS)
                .frame(minWidth: 360, idealWidth: 390, maxWidth: 500,
                       minHeight: 700, idealHeight: 800)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 390, height: 800)
        .windowResizability(.contentSize)
        #endif
    }
}
