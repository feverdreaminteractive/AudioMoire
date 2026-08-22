import CoreAudio
import AudioToolbox
import Foundation

/// Captures system-wide output audio ("what's playing out of the speakers")
/// via the Core Audio process-tap API (macOS 14.2+) — no virtual audio
/// driver needed. Prompts the user for the system audio-recording
/// permission the first time it runs.
///
/// This is genuinely one of the newer, sparsely-documented corners of Core
/// Audio — it's built directly from the CoreAudio.framework headers
/// (CATapDescription.h / AudioHardwareTapping.h / AudioHardware.h), and
/// compiles cleanly, but actually creating the tap + aggregate device and
/// receiving real callbacks can only be verified by running the app.
@available(macOS 14.2, *)
final class SystemAudioTap {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private let analyzer: AudioAnalyzer

    /// Sample rate of the tap's audio format, once known. Falls back to a
    /// sane default until then.
    private(set) var sampleRate: Double = 48000

    init(analyzer: AudioAnalyzer) {
        self.analyzer = analyzer
    }

    enum TapError: Error, CustomStringConvertible {
        case osStatus(String, OSStatus)
        var description: String {
            switch self {
            case .osStatus(let op, let status): return "\(op) failed: OSStatus \(status)"
            }
        }
    }

    func start() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let createStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard createStatus == noErr else {
            throw TapError.osStatus("AudioHardwareCreateProcessTap", createStatus)
        }
        tapID = newTapID

        let tapUID = try getStringProperty(objectID: tapID, selector: kAudioTapPropertyUID)

        if let format = try? getAudioStreamBasicDescription(objectID: tapID, selector: kAudioTapPropertyFormat) {
            sampleRate = format.mSampleRate
        }

        let aggregateUID = "com.audiomoire.tap-aggregate.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioMoire Tap Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]
            ]
        ]

        var newAggregateID: AudioObjectID = kAudioObjectUnknown
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard aggregateStatus == noErr else {
            throw TapError.osStatus("AudioHardwareCreateAggregateDevice", aggregateStatus)
        }
        aggregateDeviceID = newAggregateID

        var procID: AudioDeviceIOProcID?
        let analyzer = self.analyzer
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateDeviceID,
            nil
        ) { _, inInputData, _, _, _ in
            let samples = Self.monoMixdown(from: inInputData)
            if !samples.isEmpty {
                analyzer.ingest(samples)
            }
        }
        guard ioStatus == noErr, let procID else {
            throw TapError.osStatus("AudioDeviceCreateIOProcIDWithBlock", ioStatus)
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard startStatus == noErr else {
            throw TapError.osStatus("AudioDeviceStart", startStatus)
        }
    }

    func stop() {
        if let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    deinit {
        stop()
    }

    // MARK: - Property helpers

    private func getStringProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard status == noErr else { throw TapError.osStatus("AudioObjectGetPropertyDataSize(string)", status) }

        var cfString: CFString = "" as CFString
        status = withUnsafeMutablePointer(to: &cfString) { ptr -> OSStatus in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { throw TapError.osStatus("AudioObjectGetPropertyData(string)", status) }
        return cfString as String
    }

    private func getAudioStreamBasicDescription(objectID: AudioObjectID, selector: AudioObjectPropertySelector) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { throw TapError.osStatus("AudioObjectGetPropertyData(format)", status) }
        return asbd
    }

    // MARK: - Buffer conversion

    /// Mixes whatever channel layout the tap hands us down to mono Float32.
    /// Handles either several mono AudioBuffers or one interleaved
    /// multi-channel buffer.
    private static func monoMixdown(from bufferListPtr: UnsafePointer<AudioBufferList>) -> [Float] {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPtr))
        guard bufferList.count > 0 else { return [] }

        if bufferList.count > 1 {
            // Several mono/discrete buffers — average across them.
            var mixed: [Float]?
            for buffer in bufferList {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
                if mixed == nil {
                    mixed = Array(samples)
                } else {
                    for i in 0..<min(mixed!.count, samples.count) {
                        mixed![i] += samples[i]
                    }
                }
            }
            guard var result = mixed else { return [] }
            let scale = 1.0 / Float(bufferList.count)
            for i in 0..<result.count { result[i] *= scale }
            return result
        }

        // Single buffer, possibly interleaved multi-channel.
        let buffer = bufferList[0]
        guard let data = buffer.mData else { return [] }
        let channelCount = max(1, Int(buffer.mNumberChannels))
        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let frameCount = totalSamples / channelCount
        let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: totalSamples)

        if channelCount == 1 {
            return Array(samples)
        }

        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += samples[frame * channelCount + ch]
            }
            mono[frame] = sum / Float(channelCount)
        }
        return mono
    }
}
