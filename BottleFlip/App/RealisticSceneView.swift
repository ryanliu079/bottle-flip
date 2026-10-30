import SwiftUI
import RealityKit
import simd
#if SWIFT_PACKAGE
import GameCore
#endif
#if os(iOS)
import UIKit
private typealias RenderColor = UIColor
#else
import AppKit
private typealias RenderColor = NSColor
#endif

struct BottleRenderPose {
    let centerHeight: Float
    let depth: Float
    let angle: Float
    let fill: Float
    let travelProgress: Float
    let roll: Float
    let isGroundContact: Bool
    let liquid: BottleLiquid
    let stageNumber: Int
    let bottleAppearance: BottleAppearance
    let tableAppearance: TableAppearance
}

@MainActor
final class RealisticSceneRenderer {
    let anchor = AnchorEntity(world: .zero)
    let bottle = Entity()
    private let shell = ModelEntity()
    private let shadow = ModelEntity()
    private let customSurface = ModelEntity()
    private var caps: [ModelEntity] = []
    private var bottleProfile: [(Float, Float)] = []
    private let opticalShader = GlassOptics.shader()
    private var opticalMaterial: CustomMaterial?
    private var chapterTexture: TextureResource?
    private var currentChapter: String?
    private var currentFill: Float = -1
    private var currentLiquid: BottleLiquid?
    private var currentBottle: BottleAppearance?
    private var currentTable: TableAppearance?
    private var renderFrame = SIMD4<Float>(1, 1, 0, 1)
    private var shadowMaterial = UnlitMaterial()
    private let bottleScale: Float = 1.35
    private var bottleSize: Float { 0.270 * bottleScale }

    init(scene: BottleScene) {
        createLighting()
        createContactSurface()
        createBottle()
        bottle.scale = SIMD3(repeating: bottleScale)
        anchor.addChild(bottle)
        scene.onRender = { [weak self] pose in self?.update(pose) }
        scene.publishRenderPose()
    }
    func resize(_ size: CGSize, top: CGFloat, fraction: CGFloat, scale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        renderFrame = [Float(size.width * scale), Float(size.height * scale), Float(top), Float(fraction)]
        if var material = opticalMaterial {
            material.custom.value = renderFrame
            opticalMaterial = material
            shell.model?.materials = [material]
        }
    }
    func attach(to view: ARView) {
        view.environment.background = .color(.clear)
        #if os(iOS)
        view.renderOptions.insert(.disableMotionBlur)
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        view.scene.addAnchor(anchor)
    }
    private func createLighting() {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 43
        camera.look(at: [0, 0.34, 0], from: [0, 0.64, 1.55], relativeTo: nil)
        anchor.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 1800
        key.light.color = RenderColor(red: 1, green: 0.94, blue: 0.85, alpha: 1)
        key.look(at: [0, 0, 0], from: [-0.5, 1.0, 0.6], relativeTo: nil)
        anchor.addChild(key)
        let fill = PointLight()
        fill.light.intensity = 110
        fill.light.attenuationRadius = 3
        fill.position = [0.5, 0.8, 0.8]
        anchor.addChild(fill)
    }
    private func createContactSurface() {
        // Chapter art contains the actual furniture/masonry. A live soft shadow
        // follows the same support plane as the bottle instead of a pasted slab.
        if let image = Self.contactShadow(), let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) {
            shadowMaterial.color = .init(tint: .white, texture: .init(texture))
        }
        shadowMaterial.blending = .transparent(opacity: .init(scale: 0.85))
        shadow.model = ModelComponent(mesh: .generatePlane(width: 0.26, depth: 0.22), materials: [shadowMaterial])
        shadow.position.y = 0.0008
        anchor.addChild(shadow)
        // Purchased finishes remain available as optional substantial overlays.
        customSurface.model = ModelComponent(mesh: .generateBox(size: [1.4, 0.12, 0.82], cornerRadius: 0.009), materials: [PhysicallyBasedMaterial()])
        customSurface.position = [0, -0.06, 0.10]
        customSurface.isEnabled = false
        anchor.addChild(customSurface)
    }
    private func createBottle() {
        var profile: [(Float, Float)] = [(-0.124, 0), (-0.128, 0.020), (-0.135, 0.033), (-0.130, 0.043), (-0.119, 0.047)]
        // Rounded moulded ribs carry changing reflections, without painted rings.
        for step in 0...144 {
            let y = -0.117 + Float(step) / 144 * 0.180
            let radius = 0.047 + 0.0015 * cos((y + 0.117) / 0.025 * 2 * .pi)
            profile.append((y, radius))
        }
        profile += [(0.068, 0.047), (0.074, 0.046), (0.080, 0.042), (0.088, 0.035),
                    (0.095, 0.026), (0.101, 0.020), (0.105, 0.017), (0.115, 0.017), (0.119, 0.017), (0.119, 0)]
        bottleProfile = profile
        var fallback = PhysicallyBasedMaterial()
        fallback.baseColor = .init(tint: .white)
        fallback.roughness = 0.035; fallback.specular = 1.0; fallback.clearcoat = 1.0
        fallback.blending = .transparent(opacity: .init(scale: 0.13))
        fallback.faceCulling = .back
        shell.model = ModelComponent(mesh: Self.revolvedMesh(profile, petaloid: true), materials: [fallback])
        bottle.addChild(shell)
        var cap = PhysicallyBasedMaterial()
        cap.baseColor = .init(tint: RenderColor(red: 0.025, green: 0.27, blue: 0.95, alpha: 1))
        cap.roughness = 0.30; cap.clearcoat = 0.18
        let capProfile: [(Float, Float)] = [(-0.009, 0), (-0.009, 0.0185), (-0.007, 0.020), (0.006, 0.020), (0.009, 0.018), (0.009, 0)]
        let lid = ModelEntity(mesh: Self.revolvedMesh(capProfile), materials: [cap])
        lid.position.y = 0.126
        bottle.addChild(lid); caps.append(lid)
        let capGripMesh = MeshResource.generateBox(size: [0.0007, 0.009, 0.0008], cornerRadius: 0.0002)
        for index in 0..<48 {
            let angle = Float(index) / 48 * 2 * .pi
            let rib = ModelEntity(mesh: capGripMesh, materials: [cap])
            rib.position = [sin(angle) * 0.020, 0.126, cos(angle) * 0.020]
            rib.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            bottle.addChild(rib); caps.append(rib)
        }
        let seal = ModelEntity(mesh: Self.revolvedMesh([(-0.0015, 0.017), (0.0015, 0.017)]), materials: [cap])
        seal.position.y = 0.113
        bottle.addChild(seal); caps.append(seal)
    }
    private func update(_ pose: BottleRenderPose) {
        let progress = min(1, max(0, pose.travelProgress))
        let travel = progress * progress * (3 - 2 * progress)
        let chapter = WorldJourney.chapter(at: pose.stageNumber)
        let floorLevel: Float = chapter.id == "kitchen" ? 0.11 : 0
        let depth = 0.21 - 0.06 * travel + pose.depth * 0.22
        let rotation = simd_quatf(angle: pose.roll, axis: [0, 0, 1]) * simd_quatf(angle: pose.angle, axis: [1, 0, 0])
        var height = pose.centerHeight <= 0.5 ? pose.centerHeight * bottleSize : bottleSize * 0.5 + (pose.centerHeight - 0.5) * 0.25
        if pose.isGroundContact {
            // Match the actual curved mesh to the plane, rather than its rectangular
            // physics proxy, including a side-on miss and the supported landing rock.
            let vertical = rotation.act(SIMD3<Float>(0, 1, 0)).y
            let radial = sqrt(max(0, 1 - vertical * vertical))
            let bodyFloor = bottleProfile.map { $0.0 * vertical - $0.1 * radial }.min() ?? -0.135
            let capFloor = min(0.117 * vertical, 0.135 * vertical) - 0.0208 * radial
            height = -min(bodyFloor, capFloor) * bottleScale + 0.0008
        }
        bottle.position = [0, height + floorLevel, depth]
        bottle.orientation = rotation
        if currentChapter != chapter.id || currentFill != pose.fill || currentLiquid != pose.liquid || currentBottle != pose.bottleAppearance {
            if currentChapter != chapter.id, let url = JourneyStyle.sceneryURL(chapter.id) {
                chapterTexture = try? TextureResource.load(contentsOf: url, options: .init(semantic: .color))
            }
            currentChapter = chapter.id; currentFill = pose.fill; currentLiquid = pose.liquid; currentBottle = pose.bottleAppearance
            if let shader = opticalShader, let texture = chapterTexture,
               var material = try? CustomMaterial(surfaceShader: shader, lightingModel: .unlit) {
                material.custom.texture = .init(texture); material.custom.value = renderFrame
                material.roughness = .init(floatLiteral: pose.fill)
                material.metallic = .init(floatLiteral: pose.liquid == .water ? 0 : pose.liquid == .juice ? 0.5 : 1)
                material.clearcoat = .init(floatLiteral: floorLevel)
                material.baseColor = .init(tint: pose.bottleAppearance == .classic ? .white : Self.tint(pose.bottleAppearance.color))
                material.faceCulling = .back
                opticalMaterial = material; shell.model?.materials = [material]
            }
            let tint = pose.bottleAppearance == .classic ? RenderColor(red: 0.025, green: 0.27, blue: 0.95, alpha: 1) : Self.tint(pose.bottleAppearance.capColor)
            for entity in caps {
                guard var material = entity.model?.materials.first as? PhysicallyBasedMaterial else { continue }
                material.baseColor = .init(tint: tint); entity.model?.materials = [material]
            }
        }
        if currentTable != pose.tableAppearance {
            currentTable = pose.tableAppearance
            customSurface.isEnabled = pose.tableAppearance != .oak
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: Self.tint(pose.tableAppearance.color))
            material.roughness = pose.tableAppearance == .porcelain ? 0.18 : 0.62
            material.clearcoat = pose.tableAppearance == .porcelain ? 0.5 : 0.08
            customSurface.model?.materials = [material]
        }
        shadow.position = [0, floorLevel + 0.0008, depth + 0.015]
        customSurface.position.y = floorLevel - 0.06
        let gap = max(0, pose.centerHeight - 0.5)
        shadow.scale = [1 + gap * 0.4, 1, 1 + gap * 0.4]
        shadowMaterial.blending = .transparent(opacity: .init(scale: 0.85 / (1 + gap * 10)))
        shadow.model?.materials = [shadowMaterial]
    }
    private static func tint(_ color: AppearanceColor) -> RenderColor {
        RenderColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
    private static func revolvedMesh(_ profile: [(Float, Float)], petaloid: Bool = false) -> MeshResource {
        let segments = 96
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for row in profile.indices {
            let (y, radius) = profile[row]
            let before = profile[max(0, row - 1)], after = profile[min(profile.count - 1, row + 1)]
            let dy = after.0 - before.0, dr = after.1 - before.1
            for segment in 0...segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let moulded = petaloid && row > 1 && row < 5
                let lobe: Float = moulded ? 0.002 * cos(angle * 5) : 0
                let radialSlope: Float = moulded ? -0.010 * sin(angle * 5) / max(radius, 0.001) : 0
                let raisedValley: Float = moulded ? 0.002 * (1 - cos(angle * 5)) : 0
                positions.append([cos(angle) * (radius + lobe), y + raisedValley, sin(angle) * (radius + lobe)])
                let normal = SIMD3((cos(angle) + sin(angle) * radialSlope) * dy, -dr,
                                   (sin(angle) - cos(angle) * radialSlope) * dy)
                normals.append(simd_length_squared(normal) > 1e-10 ? simd_normalize(normal) : SIMD3(0, 1, 0))
            }
        }
        for row in 0..<(profile.count - 1) {
            for segment in 0..<segments {
                let a = UInt32(row * (segments + 1) + segment), b = a + 1, c = a + UInt32(segments + 1), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        var descriptor = MeshDescriptor(name: "Rounded ribbed PET bottle")
        descriptor.positions = .init(positions); descriptor.normals = .init(normals); descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: 0.04)
    }
    private static func contactShadow() -> CGImage? {
        guard let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 0, alpha: 0.9), CGColor(gray: 0, alpha: 0.4), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 0.55, 1]) else { return nil }
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        return context.makeImage()
    }
}

#if os(iOS)
private final class FullWidthSceneARView: ARView {
    var didResize: ((CGSize, CGFloat, CGFloat, CGFloat) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window else { return }
        let rect = convert(bounds, to: window)
        didResize?(bounds.size, rect.minY / window.bounds.height, rect.height / window.bounds.height, contentScaleFactor)
    }
}
struct RealisticSceneView: UIViewRepresentable {
    let scene: BottleScene
    func makeCoordinator() -> RealisticSceneRenderer { .init(scene: scene) }
    func makeUIView(context: Context) -> ARView {
        let view = FullWidthSceneARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.didResize = { [weak renderer = context.coordinator] size, top, fraction, scale in renderer?.resize(size, top: top, fraction: fraction, scale: scale) }
        context.coordinator.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
#else
private final class FullWidthSceneARView: ARView {
    var didResize: ((CGSize, CGFloat, CGFloat, CGFloat) -> Void)?
    override func layout() {
        super.layout()
        guard let content = window?.contentView else { return }
        let rect = convert(bounds, to: content)
        didResize?(bounds.size, (content.bounds.height - rect.maxY) / content.bounds.height, rect.height / content.bounds.height, window?.backingScaleFactor ?? 1)
    }
}
struct RealisticSceneView: NSViewRepresentable {
    let scene: BottleScene
    func makeCoordinator() -> RealisticSceneRenderer { .init(scene: scene) }
    func makeNSView(context: Context) -> ARView {
        let view = FullWidthSceneARView(frame: .zero)
        view.didResize = { [weak renderer = context.coordinator] size, top, fraction, scale in renderer?.resize(size, top: top, fraction: fraction, scale: scale) }
        context.coordinator.attach(to: view)
        return view
    }
    func updateNSView(_ nsView: ARView, context: Context) {}
}
#endif
