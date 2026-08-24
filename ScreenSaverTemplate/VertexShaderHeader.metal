#include <metal_stdlib>
using namespace metal;

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

// GLSL's mod() is floored (result has the sign of the divisor); Metal's
// fmod() is truncated (result has the sign of the dividend) — several of
// these ported shaders rely on the floored version, so define it explicitly
// rather than risk a silent behavior mismatch from fmod().
float gmod(float x, float y) {
    return x - y * floor(x / y);
}

// Shared across products: tints an otherwise grayscale/limited-palette
// pattern toward a hue-cycling color as loudness (colorMagnitude) rises,
// matching Fever Dream Screen's original moiré shader convention.
float3 hsv2rgb(float3 c) {
    float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}
