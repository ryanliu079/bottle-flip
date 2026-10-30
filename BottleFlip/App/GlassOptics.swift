import RealityKit
import Metal
import Foundation

enum GlassOptics {
    static func shader() -> CustomMaterial.SurfaceShader? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: "BottleGlass-macos", withExtension: "metallib", subdirectory: "Shaders"),
              let library = try? device.makeLibrary(URL: url) else { return nil }
        #else
        guard let library = device.makeDefaultLibrary() else { return nil }
        #endif
        return .init(named: "bottleGlass", in: library)
    }
}
