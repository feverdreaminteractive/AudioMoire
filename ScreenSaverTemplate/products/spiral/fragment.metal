// Ported from ~/Downloads/aim/spiral.qtz's embedded GLSL (identical to
// PsychCir2.qtz's first shader — that one's skipped as a duplicate). Bass
// (mouse.x) rotates the spiral phase, treble (mouse.y) speeds it up.
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);

    float2 position = (2.0 * fragCoord - u.resolution) / u.resolution.x;

    float r = length(position);
    float a = atan2(position.y, position.x) + u.mouse.x * 3.14159265;

    float3 baseColor = float3(3.0, 0.0, 1.0);
    float t = 0.5 * (1.0 + cos(a + 40.0 * r * (1.0 + sin(a * 20.0) * 0.1) - u.time * (3.0 + u.mouse.y * 2.0)) * (5.0 / (r + 7.5)));
    t = t < 0.8 ? 0.0 : 1.0;

    float3 gray = baseColor * t;
    float3 hueColor = hsv2rgb(float3(fract(u.time * 0.05 + u.colorMagnitude * 0.6), 0.85, t));
    float3 color = mix(gray, hueColor, clamp(u.colorMagnitude, 0.0, 1.0));

    return float4(color * 0.5, 1.0);
}
