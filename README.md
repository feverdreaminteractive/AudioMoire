# AudioMoire

A native macOS visualizer reacting to whatever's playing out of your
speakers — captured via Core Audio's process-tap API (macOS 14.2+, no
virtual audio driver needed), rendered as a moiré interference pattern in
Metal.

The pattern itself is a port of the fragment shader embedded in
`~/Downloads/aim/Moire1.qtz` (an old Quartz Composer patch): two circular
sine-wave fields, one fixed at screen center and one movable, summed
together. The "spokes" in the reference `moire-final.gif` are the moiré
beat between the two fields, not literally drawn lines.

## Audio → visual mapping

- **Horizontal** (screen-x of the moving field) ← smoothed low/bass band energy (~40-250Hz)
- **Vertical** (screen-y of the moving field) ← smoothed high/treble band energy (~2-8kHz)
- **Color** (grayscale → hue-cycling color) ← smoothed overall loudness (RMS)

Each has a fast-attack/slow-decay envelope so it pulses with the music
rather than flickering with raw per-frame FFT noise.

## Running it

```
./build-app.sh          # debug build
./build-app.sh release  # release build
open .build/arm64-apple-macosx/release/AudioMoire.app
```

First launch will prompt for the system audio-recording permission — grant
it, or the visual will just sit static (check `startError` shown at the
bottom of the window). If it's ever denied, reset via:

```
tccutil reset AudioCapture com.audiomoire.app
```

## Tuning

Everything audio-reactive is deliberately simple and meant to be tuned by
ear against real music, not against any rigorous calibration:

- Band split points and the `* 0.02` scale factors: `AudioAnalyzer.swift`, `init`/`analyzeFFT`
- Attack/decay envelope speed: `AudioAnalyzer.swift`, `attack`/`decay`
- Color palette / how strongly loudness pushes toward color: `Shaders.metal`, `fragmentShader`
- Ring/spoke density (`* 30.0` in both `sin()` calls): `Shaders.metal`

## Known rough edges

- The Core Audio process-tap + aggregate-device path (`SystemAudioTap.swift`)
  is built directly from the CoreAudio.framework headers — it compiles
  cleanly, but this specific API surface is new (macOS 14.2) and sparsely
  documented, so runtime behavior (does the tap actually deliver audio, is
  the aggregate device dictionary shape exactly right) has only been
  verified by launching the app, not by confirming real audio flows through
  it end to end.
- `AudioAnalyzer` assumes a 48kHz sample rate at construction time, before
  the real tap format is known — fine for band-split accuracy since this is
  tune-by-ear anyway, but worth knowing if you see something plainly wrong.
