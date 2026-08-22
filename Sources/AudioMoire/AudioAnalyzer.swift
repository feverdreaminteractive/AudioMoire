import Accelerate
import Foundation

/// Turns a stream of mono audio samples into three smoothed 0...1 magnitude
/// values the moiré shader reads every frame. Not tied to the main actor —
/// `ingest` is called from the Core Audio IOProc thread, and the Metal
/// render loop reads the three magnitudes directly (no SwiftUI/@Published
/// round-trip needed since nothing here drives SwiftUI view state).
final class AudioAnalyzer {
    private let fftSize = 2048
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var ring: [Float]
    private var ringWriteIndex = 0
    private var ringFilled = 0

    private let lock = NSLock()
    private var _horizontal: Float = 0
    private var _vertical: Float = 0
    private var _color: Float = 0

    // Fast rise, slower fall — pulses with the beat instead of chasing raw
    // per-window FFT noise.
    private let attack: Float = 0.55
    private let decay: Float = 0.10

    private let sampleRate: Double
    // Bin index ranges for the "horizontal" (low/bass) and "vertical"
    // (high/treble) bands, computed from sampleRate once we know it.
    private var lowBinRange: Range<Int> = 0..<1
    private var highBinRange: Range<Int> = 0..<1

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.log2n = vDSP_Length(round(log2(Double(fftSize))))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Could not create FFT setup")
        }
        self.fftSetup = setup
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.ring = [Float](repeating: 0, count: fftSize)

        let binHz = sampleRate / Double(fftSize)
        // Bass: ~40-250Hz. Treble: ~2kHz-8kHz. Both clamped into range.
        let lowStart = max(1, Int(40.0 / binHz))
        let lowEnd = max(lowStart + 1, Int(250.0 / binHz))
        let highStart = max(lowEnd, Int(2000.0 / binHz))
        let highEnd = min(fftSize / 2, max(highStart + 1, Int(8000.0 / binHz)))
        self.lowBinRange = lowStart..<lowEnd
        self.highBinRange = highStart..<highEnd
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    var horizontalMagnitude: Float { lock.lock(); defer { lock.unlock() }; return _horizontal }
    var verticalMagnitude: Float { lock.lock(); defer { lock.unlock() }; return _vertical }
    var colorMagnitude: Float { lock.lock(); defer { lock.unlock() }; return _color }

    /// Feed freshly captured mono samples. Buffers into a ring and runs one
    /// FFT analysis pass whenever enough new samples have accumulated.
    func ingest(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        // Overall loudness (RMS) is cheap and doesn't need the FFT window.
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        for s in samples {
            ring[ringWriteIndex] = s
            ringWriteIndex = (ringWriteIndex + 1) % fftSize
            ringFilled = min(ringFilled + 1, fftSize)
        }

        guard ringFilled >= fftSize else {
            publish(colorTarget: rms)
            return
        }

        analyzeFFT(rmsTarget: rms)
    }

    private func analyzeFFT(rmsTarget: Float) {
        // Unwrap the ring buffer into linear order starting at the oldest sample.
        var linear = [Float](repeating: 0, count: fftSize)
        let tailCount = fftSize - ringWriteIndex
        ring.withUnsafeBufferPointer { src in
            linear.withUnsafeMutableBufferPointer { dst in
                if tailCount > 0 {
                    dst.baseAddress!.update(from: src.baseAddress! + ringWriteIndex, count: tailCount)
                }
                if ringWriteIndex > 0 {
                    (dst.baseAddress! + tailCount).update(from: src.baseAddress!, count: ringWriteIndex)
                }
            }
        }

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(linear, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var lowSum: Float = 0
        for i in lowBinRange { lowSum += magnitudes[i] }
        var highSum: Float = 0
        for i in highBinRange { highSum += magnitudes[i] }

        let lowAvg = lowSum / Float(max(1, lowBinRange.count))
        let highAvg = highSum / Float(max(1, highBinRange.count))

        // sqrt to move from a power-like magnitude toward a perceptually
        // gentler curve, then a fixed scale so typical music levels land
        // roughly in 0...1. Not calibrated against anything rigorous — meant
        // to be tuned by ear once this is actually running against music.
        let horizontalTarget = clamp01(sqrt(lowAvg) * 0.02)
        let verticalTarget = clamp01(sqrt(highAvg) * 0.02)

        publish(horizontalTarget: horizontalTarget, verticalTarget: verticalTarget, colorTarget: rmsTarget * 4.0)
    }

    private func publish(horizontalTarget: Float? = nil, verticalTarget: Float? = nil, colorTarget: Float) {
        lock.lock()
        if let h = horizontalTarget { _horizontal = smooth(current: _horizontal, target: h) }
        if let v = verticalTarget { _vertical = smooth(current: _vertical, target: v) }
        _color = smooth(current: _color, target: clamp01(colorTarget))
        lock.unlock()
    }

    private func smooth(current: Float, target: Float) -> Float {
        let rate = target > current ? attack : decay
        return current + (target - current) * rate
    }

    private func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }
}
