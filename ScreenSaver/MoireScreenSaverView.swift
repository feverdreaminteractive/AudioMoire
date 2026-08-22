import ScreenSaver
import MetalKit
import QuartzCore

/// Screen-saver host for the same moiré visual as the main app. Embeds an
/// MTKView as a subview and lets it drive its own render loop (isPaused =
/// false) rather than depending on ScreenSaverView's legacy
/// animateOneFrame() pull model — startAnimation()/stopAnimation() just
/// start/stop the MTKView and the system audio tap.
@objc(MoireScreenSaverView)
final class MoireScreenSaverView: ScreenSaverView {
    private var metalView: MTKView?
    private var renderer: MoireRenderer?
    private let analyzer = AudioAnalyzer(sampleRate: 48000)
    private var tapBox: Any?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        setUpMetalView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpMetalView()
    }

    private func setUpMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let view = MTKView(frame: bounds, device: device)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = true // started explicitly in startAnimation()
        addSubview(view)
        metalView = view
        renderer = MoireRenderer(device: device, analyzer: analyzer)
        view.delegate = renderer
    }

    override func startAnimation() {
        super.startAnimation()
        metalView?.isPaused = false

        guard #available(macOS 14.2, *) else { return }
        let tap = SystemAudioTap(analyzer: analyzer)
        tapBox = tap
        do {
            try tap.start()
        } catch {
            print("AudioMoire screen saver: failed to start system audio tap: \(error)")
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        metalView?.isPaused = true
        (tapBox as? SystemAudioTap)?.stop()
        tapBox = nil
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}

/// Same shader/uniform setup as the main app's Renderer (MoireMetalView.swift),
/// duplicated here rather than shared because this target is a raw swiftc-built
/// .saver bundle, not part of the AudioMoire SPM module. Loads Shaders.metal
/// from this bundle's own Resources rather than SPM's Bundle.module.
final class MoireRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let analyzer: AudioAnalyzer
    private let startTime = CACurrentMediaTime()

    private struct Uniforms {
        var time: Float
        var resolution: SIMD2<Float>
        var mouse: SIMD2<Float>
        var colorMagnitude: Float
    }

    init?(device: MTLDevice, analyzer: AudioAnalyzer) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.analyzer = analyzer

        guard let shaderURL = Bundle(for: MoireRenderer.self).url(forResource: "Shaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8),
              let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFn = library.makeFunction(name: "vertexShader"),
              let fragmentFn = library.makeFunction(name: "fragmentShader") else {
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFn
        pipelineDescriptor.fragmentFunction = fragmentFn
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return nil
        }
        self.pipelineState = pipelineState

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

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
