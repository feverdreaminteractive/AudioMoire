import SwiftUI

@main
struct AudioMoireApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottom) {
                MoireMetalView(analyzer: appState.analyzer)
                    .ignoresSafeArea()

                if let error = appState.startError {
                    Text("System audio capture failed to start:\n\(error)")
                        .font(.callout)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding()
                }
            }
            .frame(minWidth: 480, minHeight: 480)
        }
    }
}

/// Owns the audio pipeline for the app's lifetime. AudioAnalyzer is created
/// with an assumed 48kHz sample rate — SystemAudioTap only learns the real
/// tap format once it starts, after this is already constructed. 44.1/48kHz
/// covers virtually all real Mac output devices, and the FFT band ranges
/// are approximate/tune-by-ear anyway, so this isn't re-architected to
/// support a dynamic sample rate for a first pass.
@MainActor
final class AppState: ObservableObject {
    let analyzer = AudioAnalyzer(sampleRate: 48000)
    private var tapBox: Any?
    @Published var startError: String?

    init() {
        guard #available(macOS 14.2, *) else {
            startError = "Requires macOS 14.2 or later (system audio process taps)."
            return
        }
        let tap = SystemAudioTap(analyzer: analyzer)
        tapBox = tap
        do {
            try tap.start()
        } catch {
            let message = "\(error)"
            startError = message
            print("Failed to start system audio tap: \(message)")
        }
    }
}
