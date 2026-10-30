#if DEBUG
import Foundation
#if SWIFT_PACKAGE
import GameCore
#endif

/// Exercises actual SpriteKit landings in a rendered scene. Enabled only by a launch argument.
@MainActor
final class SceneValidation {
    private let scene: BottleScene
    private var cases: [(BottleStage, Double, Bool)] = []
    private var rows: [[String: Any]] = []
    private var current: (BottleStage, Double, Bool)?
    private var timeout: Task<Void, Never>?
    private let reportURL: URL
    private var originalHandler: ((Bool, String) -> Void)?
    private var originalImpact: ((Double) -> Void)?
    private var impacts = 0

    init(scene: BottleScene) {
        self.scene = scene
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        reportURL = directory.appendingPathComponent("landing-validation.json")
        for stage in BottleStage.validationSamples {
            cases.append((stage, stage.comfortableStrength - 0.30, false))
            cases.append((stage, stage.comfortableStrength - stage.maximumLean * 0.20, true))
            cases.append((stage, stage.comfortableStrength, true))
            cases.append((stage, stage.comfortableStrength + stage.maximumLean * 0.20, true))
            cases.append((stage, stage.comfortableStrength + 0.30, false))
        }
    }
    func start() {
        originalHandler = scene.onResult
        originalImpact = scene.onImpact
        scene.onImpact = { [weak self] strength in
            self?.impacts += 1
            self?.originalImpact?(strength)
        }
        scene.onResult = { [weak self] success, _ in self?.record(success: success) }
        advance()
    }
    private func advance() {
        guard !cases.isEmpty else {
            scene.onResult = originalHandler
            scene.onImpact = originalImpact
            save(complete: true)
            return
        }
        current = cases.removeFirst()
        guard let current else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            // Reset outside SpriteKit's physics callback, after the old step has completed.
            scene.configure(stage: current.0)
            impacts = 0
            scene.launch(strength: current.1, stage: current.0)
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.record(success: nil)
            }
        }
    }
    private func record(success: Bool?) {
        guard let current else { return }
        self.current = nil
        timeout?.cancel()
        let snapshot = scene.validationSnapshot
        let onTable = (snapshot["y"] ?? -1) >= (snapshot["tableTop"] ?? 0)
            && (snapshot["touched"] ?? 0) == 1
        rows.append(["stage": current.0.number, "fill": current.0.fill, "maximumLean": current.0.maximumLean,
                     "strength": current.1, "expected": current.2,
                     "actual": success.map { $0 as Any } ?? "timeout",
                     "impactCount": impacts,
                     "passed": success == current.2 && onTable && impacts == 1
                        && (!current.2 || (snapshot["combinedLean"] ?? 1) <= current.0.maximumLean + 1e-8), "scene": snapshot])
        save(complete: false)
        advance()
    }
    private func save(complete: Bool) {
        let report: [String: Any] = ["complete": complete, "cases": rows,
                                   "passed": rows.allSatisfy { $0["passed"] as? Bool == true }]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: reportURL, options: .atomic)
        } catch { print("Scene validation report failed: \(error)") }
    }
}
#endif
