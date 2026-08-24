// Ported from ~/Downloads/aim/hypnosquare.qtz's embedded GLSL. Bass
// (mouse.x) adds to the fixed rotation angle, treble (mouse.y) speeds the
// sweep, loudness (colorMagnitude) tints the stark white lines toward a
// hue-cycling color.
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);

    float2 p = 2.0 * (fragCoord / u.resolution) - 1.0;
    p.x *= u.resolution.x / u.resolution.y;

    float ang = 100.25 * 3.14159265 + u.mouse.x * 3.14159265;
    float2x2 rot = float2x2(cos(ang), -sin(ang), sin(ang), cos(ang));
    p = rot * p;

    float d = -u.time * (1.5 + u.mouse.y * 1.5) + abs(p.x) + abs(p.y);
    d = gmod(d + 10.10, 0.2) - 0.1;

    // Multiplicative mask (not an additive mix) — a mix() here would
    // brighten the black background itself as colorMagnitude rises, since
    // it's mostly zero; masking keeps it black and only tints the lines.
    float onLine = abs(d) < 0.05 ? 1.0 : 0.0;
    float3 hueColor = hsv2rgb(float3(fract(u.time * 0.05 + u.colorMagnitude * 0.6), 0.85, 1.0));
    float3 tinted = mix(float3(10.0), hueColor * 10.0, clamp(u.colorMagnitude, 0.0, 1.0));
    float3 color = onLine * tinted;

    return float4(color, 1.0);
}
