// Ported from ~/Downloads/aim/PsychCir2.qtz's second embedded GLSL shader
// (its first is a duplicate of spiral.qtz, skipped — see the spiral
// product). GLSL's normalize() accepts a scalar (returns its sign); Metal's
// normalize() is vector-only, so scalar normalize() calls become sign().
// Bass (mouse.x) warps the origin, treble (mouse.y) speeds the whole thing,
// loudness (colorMagnitude) blends in an extra hue layer on top of the
// original's own Hue()-driven flicker.
float3 hueBloom(float hue) {
    float3 rgb = fract(hue + float3(0.0, 2.0 / 3.0, 1.0 / 3.0));
    rgb = abs(rgb * 2.0 - 1.0);
    return clamp(rgb * 3.0 - 1.0, 0.0, 1.0);
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);

    float2 p = (fragCoord * 2.0 - u.resolution) / min(u.resolution.x, u.resolution.y);
    float t = u.time * (1.0 + u.mouse.y * 0.5);

    float2 warp = float2(p.x + sin(t) + u.mouse.x * 0.3, p.y + sin(t * 0.25));
    float len = length(warp);

    float3 destColor = float3(0.0);
    destColor += sign(sin(0.1 / len * 1.0 + t * 10.0));
    destColor *= hueBloom(sin(t)) * float3(abs(sin(t * 50.0)));

    destColor += sign(sin(0.1 / len * 125.0 + t * 10.0));
    destColor += sign(sin(0.01 / len * 125.0 + t * 10.0));
    destColor -= (0.25 / len);

    destColor *= hueBloom(sin(t)) * float3(abs(sin(t * 25.0)));

    float3 hueOverlay = hsv2rgb(float3(fract(u.time * 0.05 + u.colorMagnitude * 0.6), 0.85, 1.0));
    destColor = mix(destColor, destColor * hueOverlay * 2.0, clamp(u.colorMagnitude, 0.0, 1.0) * 0.5);

    float scanline = gmod(fragCoord.y, 2.0);
    return float4(destColor * scanline, 1.0);
}
