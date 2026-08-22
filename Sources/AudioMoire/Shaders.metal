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
    return float4(rgb, 1.0);
}
