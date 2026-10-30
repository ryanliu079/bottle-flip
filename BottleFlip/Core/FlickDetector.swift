import Foundation

public struct MotionSample: Sendable {
    public let time: Double
    public let upwardAcceleration: Double // g, gravity removed
    public let rotationSpeed: Double // magnitude, radians / second
    public let accelerationMagnitude: Double
    public init(time: Double, upwardAcceleration: Double, rotationSpeed: Double,
                accelerationMagnitude: Double) {
        self.time = time
        self.upwardAcceleration = upwardAcceleration
        self.rotationSpeed = rotationSpeed
        self.accelerationMagnitude = accelerationMagnitude
    }
}

/// A throw requires stillness, an upward flick, and a return below the gesture threshold.
/// No physical device velocity is inferred by long-term acceleration integration.
public struct FlickDetector: Sendable {
    public private(set) var isArmed = false
    private var previousTime: Double?
    private var stillTime = 0.0
    private var gestureStart: Double?
    private var quietTime = 0.0
    private var peakAcceleration = 0.0
    private var peakRotation = 0.0
    private var upwardImpulse = 0.0

    public init() {}
    public mutating func reset() { self = .init() }

    public mutating func process(_ sample: MotionSample) -> Double? {
        guard sample.time.isFinite, sample.upwardAcceleration.isFinite,
              sample.rotationSpeed.isFinite, sample.accelerationMagnitude.isFinite else {
            reset(); return nil
        }
        if let previousTime, sample.time <= previousTime { return nil }
        let delta = min(0.04, max(0, sample.time - (previousTime ?? sample.time)))
        if let previousTime, sample.time - previousTime > 0.2 { reset() }
        previousTime = sample.time

        if !isArmed {
            if sample.accelerationMagnitude < 0.12 && sample.rotationSpeed < 0.5 {
                stillTime += delta
                if stillTime >= 0.3 { isArmed = true }
            } else { stillTime = 0 }
            return nil
        }

        if gestureStart == nil {
            guard sample.upwardAcceleration > 0.28,
                  sample.rotationSpeed > 0.65 else { return nil }
            gestureStart = sample.time
        }

        peakAcceleration = max(peakAcceleration, sample.upwardAcceleration)
        peakRotation = max(peakRotation, sample.rotationSpeed)
        upwardImpulse += max(0, sample.upwardAcceleration) * delta
        let elapsed = sample.time - (gestureStart ?? sample.time)
        if sample.upwardAcceleration < 0.12 { quietTime += delta } else { quietTime = 0 }
        guard quietTime >= 0.055 || elapsed >= 0.5 else { return nil }
        let valid = elapsed >= 0.055 && peakAcceleration >= 0.35
            && peakRotation >= 0.8 && upwardImpulse >= 0.018
        // Initial sensitivity values, deliberately bounded and subject to device calibration.
        let score = 0.6 * peakAcceleration / 1.8
            + 0.3 * peakRotation / 9.0 + 0.1 * upwardImpulse / 0.20
        reset()
        return valid ? min(1, max(0.05, score)) : nil
    }
}
