import SpriteKit
#if SWIFT_PACKAGE
import GameCore
#endif

struct BottleTableContact {
    enum Part { case base, edge, body, cap }
    let part: Part
    let energy: Double
    let fill: Double
    let first: Bool
}
#if os(iOS)
import UIKit
private typealias SceneColor = UIColor
#else
import AppKit
private typealias SceneColor = NSColor
#endif

@MainActor
final class BottleScene: SKScene, @preconcurrency SKPhysicsContactDelegate {
    var onResult: ((Bool, String) -> Void)?
    var onImpact: ((Double) -> Void)?
    var onTableContact: ((BottleTableContact) -> Void)?
    var onRender: ((BottleRenderPose) -> Void)?
    var throwDirection: Double = 1
    var bottleAppearance: BottleAppearance = .classic
    var tableAppearance: TableAppearance = .oak
    private var landingFlightTime = 0.0
    func publishRenderPose() {
        guard bottleHeight > 0 else { return }
        onRender?(.init(centerHeight: Float((bottle.position.y - tableTop) / bottleHeight),
                        depth: Float((bottle.position.x - size.width / 2) / bottleHeight * throwDirection),
                        angle: Float(-bottle.zRotation * throwDirection), fill: Float(stage.fill),
                        travelProgress: isLanding || resolved ? 1 : Float(profile.map { min(1, flightTime / $0.flightDuration) } ?? 0),
                        roll: Float(settleRoll), isGroundContact: touchedTable, liquid: stage.liquid, stageNumber: stage.number,
                        bottleAppearance: bottleAppearance, tableAppearance: tableAppearance))
    }
    private var stage = BottleStage.at(1)
    private var bottle = SKNode()
    private var water = SKShapeNode()
    private var shadow = SKShapeNode()
    private var tableTop = 55.0
    private var bottleHeight = 90.0
    private var profile: ThrowProfile?
    private var flightTime = 0.0
    private var settlingTime = 0.0
    private var previousTime: TimeInterval?
    private var tracker = LandingTracker()
    private var isLanding = false
    private var resolved = false
    private var touchedTable = false
    private var supportedLanding = false
    private var settleRoll = 0.0
    private var supportedSpin = 0.0
    private var lastContactTime = 0.0
    private var previousLean = 0.0
    private var bodyContactSent = false
    private var impactError = 0.0
    private var waveTime = 0.0
    private var frameDelta = 1.0 / 60
    private var deferredStrength: Double?
    #if DEBUG
    var validationSnapshot: [String: Double] {
        ["angle": bottle.zRotation, "impactError": impactError,
         "x": bottle.position.x, "y": bottle.position.y,
         "tableTop": tableTop, "height": bottleHeight,
         "speed": hypot(bottle.physicsBody?.velocity.dx ?? 0, bottle.physicsBody?.velocity.dy ?? 0) / bottleHeight,
         "spin": Double(bottle.physicsBody?.angularVelocity ?? 0),
         "touched": touchedTable ? 1 : 0, "settlingTime": settlingTime,
         "roll": settleRoll, "bodyContact": bodyContactSent ? 1 : 0,
         "sceneWidth": size.width, "sceneHeight": size.height,
         "maximumLean": stage.maximumLean, "supported": supportedLanding ? 1 : 0,
         "combinedLean": LandingTracker.combinedLean(pitch: bottle.zRotation, roll: settleRoll)]
    }
    #endif
    private let ink = SceneColor(red: 0.12, green: 0.23, blue: 0.23, alpha: 1)
    private let aqua = SceneColor(red: 0.28, green: 0.69, blue: 0.70, alpha: 0.8)

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SceneColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1)
        physicsWorld.contactDelegate = self
    }
    override convenience init() { self.init(size: CGSize(width: 390, height: 370)) }
    required init?(coder: NSCoder) { fatalError("Use init(size:)") }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        rebuild()
    }
    override func didChangeSize(_ oldSize: CGSize) {
        // SwiftUI may resize a scene during presentation. Keep a live throw intact.
        if profile == nil { rebuild() }
    }
    func configure(stage: BottleStage) {
        self.stage = stage
        profile = nil
        deferredStrength = nil
        rebuild()
    }
    private func rebuild() {
        guard size.width > 0, size.height > 0 else { return }
        removeAllChildren()
        previousTime = nil
        flightTime = 0; settlingTime = 0; waveTime = 0
        tracker = .init(maximumLean: stage.maximumLean); resolved = false; isLanding = false; touchedTable = false
        supportedLanding = false; settleRoll = 0; supportedSpin = 0
        bodyContactSent = false; previousLean = 0; lastContactTime = 0
        bottleHeight = min(104, size.height * 0.225)
        tableTop = size.height * 0.17
        physicsWorld.gravity = CGVector(dx: 0, dy: -ThrowProfile.gravity * bottleHeight)

        let width = size.width
        let tablePath = CGMutablePath()
        tablePath.move(to: CGPoint(x: 27, y: tableTop))
        tablePath.addLine(to: CGPoint(x: width - 27, y: tableTop))
        tablePath.addLine(to: CGPoint(x: width - 9, y: tableTop - 22))
        tablePath.addLine(to: CGPoint(x: 9, y: tableTop - 22))
        tablePath.closeSubpath()
        let top = SKShapeNode(path: tablePath)
        top.fillColor = SceneColor(red: 0.86, green: 0.69, blue: 0.50, alpha: 1)
        top.strokeColor = SceneColor(red: 0.62, green: 0.44, blue: 0.29, alpha: 1)
        top.lineWidth = 2
        top.zPosition = 1
        addChild(top)
        let front = SKShapeNode(rect: CGRect(x: 10, y: tableTop - 29, width: width - 20, height: 7), cornerRadius: 2)
        front.fillColor = SceneColor(red: 0.65, green: 0.47, blue: 0.33, alpha: 1)
        front.strokeColor = .clear
        addChild(front)
        for x in [45.0, width - 55.0] {
            let leg = SKShapeNode(rect: CGRect(x: x, y: 0, width: 10, height: tableTop - 25), cornerRadius: 3)
            leg.fillColor = SceneColor(red: 0.65, green: 0.47, blue: 0.33, alpha: 1)
            leg.strokeColor = .clear
            addChild(leg)
        }
        let surface = SKNode()
        surface.position = CGPoint(x: width / 2, y: tableTop - 4)
        surface.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width - 52, height: 8))
        surface.physicsBody?.isDynamic = false
        surface.physicsBody?.friction = 0.9
        surface.physicsBody?.restitution = 0
        surface.physicsBody?.categoryBitMask = 2
        addChild(surface)

        shadow = SKShapeNode(ellipseOf: CGSize(width: bottleHeight * 0.7, height: 9))
        shadow.fillColor = ink.withAlphaComponent(0.12)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: width / 2, y: tableTop - 8)
        shadow.zPosition = 2
        addChild(shadow)
        createBottle()
        publishRenderPose()
        if let strength = deferredStrength { deferredStrength = nil; launch(strength: strength, stage: stage) }
    }

    private func bottlePath() -> CGPath {
        let h = bottleHeight, w = h * 0.40
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -w * 0.30, y: -h * 0.5))
        path.addQuadCurve(to: CGPoint(x: -w * 0.5, y: -h * 0.38), control: CGPoint(x: -w * 0.5, y: -h * 0.5))
        path.addLine(to: CGPoint(x: -w * 0.5, y: h * 0.17))
        path.addCurve(to: CGPoint(x: -w * 0.23, y: h * 0.38), control1: CGPoint(x: -w * 0.5, y: h * 0.27), control2: CGPoint(x: -w * 0.23, y: h * 0.27))
        path.addLine(to: CGPoint(x: -w * 0.23, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.23, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.23, y: h * 0.38))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.17), control1: CGPoint(x: w * 0.23, y: h * 0.27), control2: CGPoint(x: w * 0.5, y: h * 0.27))
        path.addLine(to: CGPoint(x: w * 0.5, y: -h * 0.38))
        path.addQuadCurve(to: CGPoint(x: w * 0.30, y: -h * 0.5), control: CGPoint(x: w * 0.5, y: -h * 0.5))
        path.closeSubpath()
        return path
    }
    private func createBottle() {
        bottle = SKNode()
        bottle.position = CGPoint(x: size.width / 2, y: tableTop + bottleHeight / 2 + 0.5)
        bottle.zPosition = 4
        let path = bottlePath()
        let shell = SKShapeNode(path: path)
        shell.fillColor = SceneColor.white.withAlphaComponent(0.67)
        shell.strokeColor = .clear
        bottle.addChild(shell)
        let mask = SKShapeNode(path: path)
        mask.fillColor = .white; mask.strokeColor = .white
        let crop = SKCropNode()
        crop.maskNode = mask
        water = SKShapeNode()
        water.fillColor = aqua
        water.strokeColor = .clear
        crop.addChild(water)
        bottle.addChild(crop)
        let outline = SKShapeNode(path: path)
        outline.fillColor = .clear; outline.strokeColor = ink
        outline.lineWidth = 2.6
        bottle.addChild(outline)
        let cap = SKShapeNode(rect: CGRect(x: -bottleHeight * 0.12, y: bottleHeight * 0.43,
                                         width: bottleHeight * 0.24, height: bottleHeight * 0.065), cornerRadius: 2.4)
        cap.fillColor = ink; cap.strokeColor = .clear
        bottle.addChild(cap)
        let highlight = SKShapeNode(rect: CGRect(x: -bottleHeight * 0.135, y: -bottleHeight * 0.29,
                                                width: 3.5, height: bottleHeight * 0.40), cornerRadius: 1.7)
        highlight.fillColor = SceneColor.white.withAlphaComponent(0.85)
        highlight.strokeColor = .clear
        bottle.addChild(highlight)
        for y in [-0.24, -0.08, 0.08] {
            let ridgePath = CGMutablePath()
            ridgePath.move(to: CGPoint(x: -bottleHeight * 0.17, y: bottleHeight * y))
            ridgePath.addQuadCurve(to: CGPoint(x: bottleHeight * 0.17, y: bottleHeight * y),
                                   control: CGPoint(x: 0, y: bottleHeight * (y - 0.025)))
            let ridge = SKShapeNode(path: ridgePath)
            ridge.strokeColor = ink.withAlphaComponent(0.13); ridge.lineWidth = 1
            bottle.addChild(ridge)
        }
        addChild(bottle)
        updateWater()
    }
    private func updateWater() {
        let h = bottleHeight, w = h * 0.44
        let level = -h * 0.48 + h * 0.86 * stage.fill
        let wave = (profile == nil ? 1.2 : 3.5) / stage.liquid.damping
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -w, y: -h))
        path.addLine(to: CGPoint(x: -w, y: level))
        for index in 0...16 {
            let x = -w + 2 * w * Double(index) / 16
            let tilt = sin(bottle.zRotation) * x * 0.45
            path.addLine(to: CGPoint(x: x, y: level + sin(Double(index) * 0.42 + waveTime * 6) * wave + tilt))
        }
        path.addLine(to: CGPoint(x: w, y: -h))
        path.closeSubpath()
        water.path = path
    }

    func launch(strength: Double, stage: BottleStage) {
        guard profile == nil else { return }
        self.stage = stage
        guard bottle.parent != nil else { deferredStrength = strength; return }
        profile = ThrowProfile(strength: strength, stage: stage)
        landingFlightTime = profile?.contactTime ?? 0
        flightTime = 0; settlingTime = 0; previousTime = nil
        isLanding = false; resolved = false; touchedTable = false; supportedLanding = false; tracker = .init(maximumLean: stage.maximumLean)
        settleRoll = 0; supportedSpin = 0; bodyContactSent = false
        lastContactTime = 0; previousLean = 0
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = min(1.0 / 30, max(0, currentTime - (previousTime ?? currentTime)))
        frameDelta = delta
        previousTime = currentTime
        waveTime += delta
        updateWater()
        guard let profile, !resolved else { return }
        if !isLanding {
            flightTime = min(landingFlightTime, flightTime + delta)
            let angle = -profile.angle(at: flightTime)
            let lift = profile.height(at: flightTime) * bottleHeight
            bottle.zRotation = angle
            bottle.position.y = tableTop + bottleHeight / 2 + lift + 0.5
            let support = bottleHeight / 2 * abs(cos(angle)) + bottleHeight * 0.15 * abs(sin(angle))
            shadow.alpha = max(0.2, 1 - lift / (bottleHeight * 3))
            shadow.xScale = 1 + lift / (bottleHeight * 4)
            if flightTime >= landingFlightTime {
                beginLanding(profile: profile, support: support)
            }
        } else {
            settlingTime += delta
            if supportedLanding {
                // A damped rock in depth and sideways keeps the outcome in suspense
                // while avoiding numerical tipping from the narrow PET contact body.
                let t = settlingTime, frequency = 13.5, damping = 3.6 * stage.liquid.damping
                let amplitude = (0.10 + stage.fill * 0.10) / stage.liquid.damping
                let envelope = exp(-damping * t)
                let pitch = impactError * cos(frequency * t) + amplitude * sin(frequency * t)
                bottle.zRotation = pitch * envelope
                settleRoll = 0.075 * sin(17 * t) * envelope
                let pitchSpeed = (-impactError * frequency * sin(frequency * t)
                    + amplitude * frequency * cos(frequency * t) - damping * pitch) * envelope
                let rollSpeed = 0.075 * (17 * cos(17 * t) - damping * sin(17 * t)) * envelope
                supportedSpin = hypot(pitchSpeed, rollSpeed)
                let vertical = cos(bottle.zRotation) * cos(settleRoll)
                let support = bottleHeight * (0.5 * abs(vertical) + 0.15 * sqrt(max(0, 1 - vertical * vertical)))
                bottle.position.y = tableTop + support + 0.4
                if previousLean * bottle.zRotation < 0 && supportedSpin > 0.20
                    && t - lastContactTime > 0.13 {
                    onTableContact?(.init(part: .edge, energy: min(0.55, supportedSpin * 0.3), fill: stage.fill, first: false))
                    lastContactTime = t
                }
                previousLean = bottle.zRotation
            }
            shadow.alpha = 1; shadow.xScale = 1
            if settlingTime > 2.5 || bottle.position.y < -bottleHeight || bottle.position.x < 0 || bottle.position.x > size.width {
                resolve(success: false)
            }
        }
    }

    private func beginLanding(profile: ThrowProfile, support: Double) {
        isLanding = true
        bottle.position.y = tableTop + support + 0.8
        impactError = ThrowProfile.uprightError(bottle.zRotation)
        bottle.zRotation = impactError
        let body = SKPhysicsBody(rectangleOf: CGSize(width: bottleHeight * 0.30, height: bottleHeight))
        body.mass = stage.effectiveMass
        body.friction = 0.9
        body.restitution = 0
        body.linearDamping = 2.8 * stage.liquid.damping
        body.angularDamping = 4 * stage.liquid.damping
        body.categoryBitMask = 1
        body.collisionBitMask = 2
        body.contactTestBitMask = 2
        body.velocity = CGVector(dx: 0, dy: profile.verticalSpeed(at: flightTime) * bottleHeight * 0.06)
        // Simplified water impact damping. A soft upright landing still has to settle.
        body.angularVelocity = abs(impactError) > stage.maximumLean
            ? (impactError > 0 ? 1.8 : -1.8) : -profile.spin(at: flightTime) * 0.035
        bottle.physicsBody = body
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if (contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask) == 3 && !touchedTable {
            touchedTable = true
            previousLean = impactError
            let angle = abs(impactError)
            let part: BottleTableContact.Part = angle < 0.35 ? .base : angle > .pi - 0.35 ? .cap
                : abs(angle - .pi / 2) < 0.30 ? .body : .edge
            bodyContactSent = part == .body
            onTableContact?(.init(part: part, energy: 0.85 + (profile?.strength ?? 0.5) * 0.15,
                                 fill: stage.fill, first: true))
            if abs(impactError) <= stage.maximumLean {
                supportedLanding = true
                bottle.physicsBody?.isDynamic = false
                bottle.physicsBody?.velocity = .zero
                bottle.physicsBody?.angularVelocity = 0
            }
            onImpact?(profile?.strength ?? 0.5)
        }
    }
    func finishInterruptedThrow() {
        guard !resolved, profile != nil else { return }
        bottle.physicsBody?.isDynamic = false
        bottle.zRotation = .pi / 2
        bottle.position = CGPoint(x: size.width / 2, y: tableTop + bottleHeight * 0.15 + 0.4)
        touchedTable = true
        resolve(success: false)
        publishRenderPose()
    }
    override func didSimulatePhysics() {
        defer { publishRenderPose() }
        guard isLanding, !resolved, let body = bottle.physicsBody else { return }
        // Water absorbs the impact; eliminate upward collision jitter after contact.
        if touchedTable && body.velocity.dy > 0 { body.velocity.dy = 0 }
        let support = bottleHeight / 2 * abs(cos(bottle.zRotation))
            + bottleHeight * 0.15 * abs(sin(bottle.zRotation))
        // Enforce the tabletop plane after contact. This prevents thin-surface solver
        // penetration from launching a rotating bottle through the table at impact.
        if touchedTable && bottle.position.x >= 27 && bottle.position.x <= size.width - 27 {
            let floor = tableTop + support + 0.4
            if bottle.position.y < floor {
                bottle.position.y = floor
                body.velocity.dy = 0
                body.velocity.dx *= 0.5
                body.angularVelocity = min(3, max(-3, body.angularVelocity))
            }
        }
        let atSurface = touchedTable && abs(bottle.position.y - support - tableTop) < 5
        if atSurface && !supportedLanding && !bodyContactSent && settlingTime > 0.08
            && abs(abs(ThrowProfile.uprightError(bottle.zRotation)) - .pi / 2) < 0.32 {
            bodyContactSent = true
            onTableContact?(.init(part: .body, energy: 0.95, fill: stage.fill, first: false))
        }
        if atSurface {
            body.velocity.dx *= 0.90
            let error = ThrowProfile.uprightError(bottle.zRotation)
            if abs(impactError) > stage.maximumLean && abs(error) < 1.4 {
                // An off-centre impact tips around its contacting edge. Keep that
                // outward torque when the penetration correction absorbs collision impulses.
                body.angularVelocity = error > 0 ? max(1.4, body.angularVelocity) : min(-1.4, body.angularVelocity)
            } else {
                body.angularVelocity *= 0.85
            }
        }
        let speed = hypot(body.velocity.dx, body.velocity.dy) / bottleHeight
        let spin = supportedLanding ? supportedSpin : Double(body.angularVelocity)
        if supportedLanding && tracker.update(delta: frameDelta,
                          touchingTable: atSurface, angle: bottle.zRotation,
                          speed: speed, spin: spin, roll: settleRoll) {
            resolve(success: true)
        } else if settlingTime > 0.6 && abs(ThrowProfile.uprightError(bottle.zRotation)) > 0.85 && speed < 0.5 {
            resolve(success: false)
        }
    }
    private func resolve(success: Bool) {
        guard !resolved else { return }
        resolved = true
        // Freeze the settled result until the player chooses the next attempt.
        #if DEBUG
        print("Landing state before freeze: \(validationSnapshot)")
        #endif
        bottle.physicsBody?.isDynamic = false
        let hint: String
        if abs(impactError) < 0.24 {
            hint = impactError < 0 ? "Close! A slightly stronger flick." : "Close! A slightly gentler flick."
        }
        else if (profile?.landingAngle ?? 0) < 2 * .pi { hint = "A little more flick next time." }
        else { hint = "A little less flick next time." }
        onResult?(success, hint)
    }
}
