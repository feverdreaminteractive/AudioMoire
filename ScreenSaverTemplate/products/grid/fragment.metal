// Ported from ~/Downloads/aim/moire2.qtz's embedded GLSL. Bass (mouse.x)
// widens the grid, treble (mouse.y) speeds the vertical sweep, loudness
// (colorMagnitude) tints the grayscale pulse toward a hue-cycling color.
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);

    float2 uv = fragCoord / u.resolution;
    uv += (uv - 0.5) * (1.0 - 1.0 / length(uv - 0.5));

    float2 position = uv * float2(u.resolution.x / u.resolution.y, 1.0);

    float n = 40.0 + u.mouse.x * 20.0;
    float x = fract(position.x * n) - 0.5;
    float y = fract(position.y * n) - 0.5;

    float2 s = float2(x * x, y * y);
    float c = s.x * s.y * (200.0 + 500.0 * ((1.0 + sin(u.time * 1.5)) * 0.5) + 0.75);
    c = clamp(c, 0.0, 1.0);
    c *= sin(position.y * 16.0 + u.time * (2.5 + u.mouse.y * 2.0)) * cos(position.x * 16.0 + u.time);

    float3 gray = float3(c);
    float3 hueColor = hsv2rgb(float3(fract(u.time * 0.05 + u.colorMagnitude * 0.6), 0.85, clamp(c, 0.0, 1.0)));
    float3 color = mix(gray, hueColor, clamp(u.colorMagnitude, 0.0, 1.0));

    return float4(color, 1.0);
}
