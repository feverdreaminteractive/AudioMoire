import SwiftUI
import MetalKit
import QuartzCore

struct MoireMetalView: NSViewRepresentable {
    let analyzer: AudioAnalyzer

    func makeCoordinator() -> Renderer {
        Renderer(analyzer: analyzer)
    }

    func makeNSView(context: Context) -> AudioMoireMTKView {
        let view = AudioMoireMTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        view.renderer = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        return view
    }

    func updateNSView(_ nsView: AudioMoireMTKView, context: Context) {}
}

/// Adds spacebar-to-switch-pattern on top of a plain MTKView.
final class AudioMoireMTKView: MTKView {
    weak var renderer: Renderer?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            renderer?.nextPattern()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineStates: [MTLRenderPipelineState]
    private let analyzer: AudioAnalyzer
    private let startTime = CACurrentMediaTime()
    private var patternIndex = 0

    private struct Uniforms {
        var time: Float
        var resolution: SIMD2<Float>
        var mouse: SIMD2<Float>
        var colorMagnitude: Float
    }

    func nextPattern() {
        patternIndex = (patternIndex + 1) % pipelineStates.count
    }

    init(analyzer: AudioAnalyzer) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this Mac")
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create a Metal command queue")
        }
        self.commandQueue = queue
        self.analyzer = analyzer

        // SPM copies Shaders.metal into the resource bundle as plain source
        // rather than pre-compiling it to a .metallib in this configuration,
        // so compile it at runtime instead — simpler than fighting SPM's
        // Metal build-rule detection, and just as fast in practice for a
        // couple of small shader files.
        guard let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            fatalError("Could not find Shaders.metal in the resource bundle")
        }
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            fatalError("Could not compile Shaders.metal")
        }
        guard let vertexFn = library.makeFunction(name: "vertexShader") else {
            fatalError("Could not find vertexShader in the Metal library")
        }

        func makePipeline(fragmentFunctionName: String) -> MTLRenderPipelineState {
            guard let fragmentFn = library.makeFunction(name: fragmentFunctionName) else {
                fatalError("Could not find \(fragmentFunctionName) in the Metal library")
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                fatalError("Could not build the render pipeline for \(fragmentFunctionName): \(error)")
            }
        }

        self.pipelineStates = [
            makePipeline(fragmentFunctionName: "fragmentShader"),
            makePipeline(fragmentFunctionName: "fragmentShaderOpArt"),
        ]

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        var uniforms = Uniforms(
            time: Float(CACurrentMediaTime() - startTime),
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            mouse: SIMD2<Float>(analyzer.horizontalMagnitude, analyzer.verticalMagnitude),
            colorMagnitude: analyzer.colorMagnitude
        )

        encoder.setRenderPipelineState(pipelineStates[patternIndex])
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
