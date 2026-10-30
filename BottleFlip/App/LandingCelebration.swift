import SwiftUI

struct LandingCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var finished = false
    private let colours: [Color] = [.orange, .yellow, .cyan, .mint, .pink]

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished)) { context in
                Canvas { canvas, size in
                    let elapsed = context.date.timeIntervalSince(started)
                    for burst in 0..<3 {
                        let age = elapsed - Double(burst) * 0.18
                        guard age >= 0, age < 1.6 else { continue }
                        let centre = CGPoint(x: size.width * [0.23, 0.76, 0.5][burst],
                                             y: size.height * [0.38, 0.29, 0.16][burst])
                        let fade = min(1, max(0, (1.6 - age) / 0.7))
                        for particle in 0..<32 {
                            let angle = Double(particle) / 32 * 2 * .pi
                            let speed = 70 + Double((particle * 17 + burst * 11) % 55)
                            let radius = speed * age * (1 - age * 0.23)
                            let point = CGPoint(x: centre.x + cos(angle) * radius,
                                                y: centre.y + sin(angle) * radius + 24 * age * age)
                            let colour = colours[(particle + burst) % colours.count].opacity(fade)
                            var trail = Path()
                            trail.move(to: CGPoint(x: point.x - cos(angle) * 7, y: point.y - sin(angle) * 7))
                            trail.addLine(to: point)
                            canvas.stroke(trail, with: .color(colour), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            canvas.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(colour))
                        }
                    }
                }
            }
            .task {
                started = Date()
                try? await Task.sleep(for: .seconds(2.1))
                finished = true
            }
        }
    }
}
