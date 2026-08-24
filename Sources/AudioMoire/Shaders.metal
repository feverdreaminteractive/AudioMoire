#include <metal_stdlib>
using namespace metal;

// Port of the fragment shader embedded in ~/Downloads/aim/Moire1.qtz (a
// Quartz Composer patch): two circular sine-wave fields, one centered at
// the screen origin and one at a movable point, summed together. The
// radial "spoke" look comes from the moiré beat between the two fields,
// not from literally drawing spokes. Here `mouse` is driven by
// audio-derived horizontal/vertical magnitude instead of the cursor, and
// colorMagnitude pushes the original grayscale toward a hue-cycling
// palette as the audio gets louder.

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID];
    return out;
}

struct Uniforms {
    float time;
    float2 resolution;
    float2 mouse;          // horizontal/vertical audio magnitude, each ~0...1
    float colorMagnitude;  // overall loudness, ~0...1
};

float3 hsv2rgb(float3 c) {
    float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);
    float minDim = min(u.resolution.x, u.resolution.y);

    float2 p = (fragCoord * 2.0 - u.resolution) / minDim;
    float2 m = float2((u.mouse.x * 2.0 - 1.0) * (u.resolution.x / u.resolution.y),
                       u.mouse.y * 2.0 - 1.0);

    float t = sin(length(m - p) * 30.0 + u.time * 5.0);
    t += sin(length(p) * 30.0 + u.time * 5.0);
    t *= 0.5; // roughly back to -1...1

    float3 gray = float3(clamp(t * 0.5 + 0.5, 0.0, 1.0));
    float hue = fract(u.time * 0.05 + u.colorMagnitude * 0.6);
    float3 hueColor = hsv2rgb(float3(hue, 0.85, clamp(abs(t) * (0.6 + u.colorMagnitude), 0.0, 1.0)));

    float3 rgb = mix(gray, hueColor, clamp(u.colorMagnitude, 0.0, 1.0));

    // TEMPORARY diagnostic: an unmissable invert flash on any nonzero
    // loudness, to settle whether real audio data is reaching the shader
    // at all vs. just being too subtle at the tuned scale. Remove once
    // confirmed either way.
    if (u.colorMagnitude > 0.03 || u.mouse.x > 0.03 || u.mouse.y > 0.03) {
        rgb = 1.0 - rgb;
    }

    return float4(rgb, 1.0);
}

// Port of the fragment shader embedded in ~/Downloads/aim/OpArtSeries1-5.qtz:
// a domain-warped ripple whose look is entirely driven by five phase
// parameters (A-E), each used as an offset inside nested cos/sin warps. The
// original patch animated these with slow LFOs; here they derive from time
// plus the same audio magnitudes as the moiré pattern (mouse.x = bass,
// mouse.y = treble, colorMagnitude = loudness) so it's continuously alive
// even at silence, and visibly reshapes with the music.
float3 opArtHsv(float h, float s, float v) {
    float3 k = float3(3.0, 2.0, 1.0) / 3.0;
    float3 p = abs(fract(h + k) * 6.0 - 3.0) - 1.0;
    return mix(float3(1.0), clamp(p, 0.0, 1.0), s) * v;
}

fragment float4 fragmentShaderOpArt(VertexOut in [[stage_in]],
                                     constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);

    float A = u.time * 0.30 + u.mouse.x * 6.0;
    float B = u.time * 0.21 + u.mouse.y * 6.0;
    float C = u.time * 0.17 + u.mouse.x * 3.0;
    float D = u.time * 0.13 + u.mouse.y * 3.0;
    float E = u.time * 0.11 + u.colorMagnitude * 4.0;

    float2 uv = 2.0 * fragCoord / u.resolution - 1.0;
    uv.x *= 1.18;
    uv.y *= 1.05;

    uv *= length(uv * 0.23);
    uv += cos(uv.x * 24.0 + A) * sin(u.time + uv.y * 32.0 + B);
    uv += cos(u.time + uv.x * 16.0 + C) * sin(u.time + uv.x * 4.0 + D);
    uv *= sin(length(uv) * 2.0 + E);

    float r = length(uv);
    float hueShift = u.colorMagnitude * 0.3;

    float3 rgb = (1.0 - float3(exp(r) - 1.1)) * opArtHsv(0.4 + hueShift + r * 0.8, 1.0, 1.0);
    return float4(rgb, 1.0);
}
