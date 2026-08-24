// Ported from ~/Downloads/aim/chevrons.qtz's embedded GLSL. The original
// had a commented-out cursor-rotation stub — revived here, driven by bass
// (mouse.x) instead of the cursor; treble (mouse.y) speeds the sweep.
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);

    float3 color = float3(3.0, 1.0, 1.0);
    float width = 50.0;

    float x = fragCoord.x - u.resolution.x / 2.5;
    float y = fragCoord.y - u.resolution.y / 2.5;

    float rotAngle = u.mouse.x * 2.0 * 3.14159265;
    float xr = x * cos(rotAngle) - y * sin(rotAngle);
    float yr = x * sin(rotAngle) + y * cos(rotAngle);

    float s = yr < 0.0 ? 1.0 : -1.0;
    float angle = 3.14159265 / 4.0;
    float xp = xr * cos(angle * s) - yr * sin(angle * s) - u.time * (550.0 + u.mouse.y * 300.0);

    if (gmod(xp, width) - width / 2.0 > 0.0) {
        color = float3(1.0, 0.0, 5.0);
    }

    float3 hueColor = hsv2rgb(float3(fract(u.time * 0.05 + u.colorMagnitude * 0.6), 0.85, 1.0));
    float3 finalColor = mix(color, hueColor * 3.0, clamp(u.colorMagnitude, 0.0, 1.0) * 0.6);

    return float4(finalColor, 1.0);
}
