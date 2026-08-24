import ScreenSaver
import MetalKit
import QuartzCore

/// Screen-saver host for the same moiré visual as the main app. Embeds an
/// MTKView as a subview and lets it drive its own render loop (isPaused =
/// false) rather than depending on ScreenSaverView's legacy
/// animateOneFrame() pull model.
///
/// No live audio here: the legacyScreenSaver.appex host that runs .saver
/// plugins on modern macOS is a platform binary, and TCC silently denies
/// any audio-capture permission request made from a platform binary — no
/// prompt ever shows, so a real Core Audio tap can never receive samples
/// in this context (it works fine in the standalone FeverDreamScreen.app,
/// which requests the permission as itself). The `mouse`/`colorMagnitude`
/// shader uniforms are driven by a slow synthetic animation instead, same
/// idea as the web preview's fallback when there's no mic access in-browser
/// (see src/shaders/fever-dream-shader.ts in the portfolio repo).
@objc(MoireScreenSaverView)
final class MoireScreenSaverView: ScreenSaverView {
    private var metalView: MTKView?
    private var renderer: MoireRenderer?

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
        // Pull model, not push: MTKView never drives its own render loop
        // (isPaused stays true permanently — see class doc for why). Every
        // frame is drawn synchronously from animateOneFrame() below, at
        // whatever cadence ScreenSaverView's own internal timer calls it
        // (animationTimeInterval, set below to 30fps — plenty for these
        // patterns, and half the GPU work of the old 60fps self-driven loop).
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        addSubview(view)
        metalView = view
        renderer = MoireRenderer(device: device)
        view.delegate = renderer
    }

    // Deliberately pull, not push: earlier versions let MTKView drive its
    // own render loop via a CVDisplayLink (isPaused = false), then tried
    // bolting on ways to detect from outside when to pause it —
    // NSWindow.occlusionState (never reported .visible in the
    // legacyScreenSaver.appex host that runs .saver plugins on modern
    // macOS), then polling CGWindowListCopyWindowInfo for whether our
    // window was still on-screen (still 130%+ CPU indefinitely after
    // quitting System Settings — the WindowServer kept listing the
    // orphaned preview window as on-screen even after its owning app had
    // already quit, so the "ground truth" being polled was itself wrong).
    // Both failure modes trace to the same root cause: a self-sustaining
    // loop, once started, has no reliable way to learn from outside that
    // it should stop in this host.
    //
    // animateOneFrame() sidesteps most of that class of bug: it draws one
    // frame only when ScreenSaverView's own internal timer calls it, and
    // that timer is what start/stopAnimation() actually control — so
    // there's no *separate* render loop of ours left running to leak.
    //
    // But the host's own internal timer isn't reliably stopped either:
    // quitting System Settings still left animateOneFrame() being called
    // indefinitely (observed: ~15% CPU steady, down from the old 130%+,
    // but not zero). That only happens for isPreview instances — the
    // small gallery thumbnails and the big live preview at the top of the
    // Screen Saver pane, both hosted inside System Settings by
    // legacyScreenSaver.appex, a separate process that isn't told to stop
    // when System Settings quits. The real full-screen/lock-screen saver
    // (isPreview == false) is driven by a different, more reliable host
    // lifecycle and doesn't have this problem, so it's left untouched below.
    //
    // For isPreview instances, skip the draw once the specific app that
    // could have requested this preview is confirmed gone — narrower and
    // safer than the earlier CGWindowListCopyWindowInfo attempts, which
    // polled whether *our own window* was still on-screen and failed
    // because the WindowServer kept listing the orphaned preview window
    // as on-screen even after System Settings had already quit. Checking
    // System Settings' own liveness isn't fooled by that, since it doesn't
    // go through the WindowServer's window-list bookkeeping at all.
    override func animateOneFrame() {
        super.animateOneFrame()
        if isPreview && !NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.apple.systempreferences"
        }) {
            return
        }
        metalView?.draw()
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
    private let startTime = CACurrentMediaTime()

    private struct Uniforms {
        var time: Float
        var resolution: SIMD2<Float>
        var mouse: SIMD2<Float>
        var colorMagnitude: Float
    }

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        guard let shaderURL = Bundle(for: MoireRenderer.self).url(forResource: "Shaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8),
              let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFn = library.makeFunction(name: "vertexShader"),
              let fragmentFn = library.makeFunction(name: "fragmentShaderOpArt") else {
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

        let time = Float(CACurrentMediaTime() - startTime)
        // No live audio in this host (see class doc) — slow synthetic
        // sine waves at different periods stand in for the bass/treble/
        // loudness magnitudes a real tap would otherwise drive.
        var uniforms = Uniforms(
            time: time,
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            mouse: SIMD2<Float>(0.5 + 0.5 * sin(time * 0.13), 0.5 + 0.5 * sin(time * 0.19 + 1.7)),
            colorMagnitude: 0.5 + 0.5 * sin(time * 0.3)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
