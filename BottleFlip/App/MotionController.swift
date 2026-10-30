import Foundation
#if SWIFT_PACKAGE
import GameCore
#endif
#if os(iOS)
import CoreMotion
#endif

@MainActor
final class MotionController {
    var onThrow: ((Double, Double) -> Void)?
    var onReadiness: ((Bool) -> Void)?
    private var detector = FlickDetector()
    private var timer: Timer?
    private var lastTimestamp: Double?
    private var lastArmed = false
    private var peakPitch = 0.0
    #if os(iOS)
    private let manager = CMMotionManager()
    #endif

    @discardableResult
    func start() -> Bool {
        #if os(iOS)
        guard manager.isDeviceMotionAvailable else { return false }
        guard timer == nil else { return true }
        detector.reset()
        lastTimestamp = nil
        lastArmed = false
        peakPitch = 0
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 100, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        return true
        #else
        return false
        #endif
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        #if os(iOS)
        manager.stopDeviceMotionUpdates()
        #endif
        detector.reset()
        lastTimestamp = nil
        lastArmed = false
        onReadiness?(false)
    }

    #if os(iOS)
    private func sample() {
        guard let data = manager.deviceMotion, data.timestamp != lastTimestamp else { return }
        lastTimestamp = data.timestamp
        let a = data.userAcceleration
        let g = data.gravity
        let r = data.rotationRate
        // Gravity points downward in phone coordinates; its opposite is world-up.
        let upward = -(a.x * g.x + a.y * g.y + a.z * g.z)
        let rotation = abs(r.x)
        if detector.isArmed && upward > 0.12 && abs(r.x) > abs(peakPitch) { peakPitch = r.x }
        let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        let strength = detector.process(.init(time: data.timestamp,
                                               upwardAcceleration: upward,
                                               rotationSpeed: rotation,
                                               accelerationMagnitude: magnitude))
        if lastArmed != detector.isArmed {
            lastArmed = detector.isArmed
            onReadiness?(lastArmed)
        }
        if let strength { onThrow?(strength, peakPitch >= 0 ? 1 : -1) }
    }
    #endif
}
