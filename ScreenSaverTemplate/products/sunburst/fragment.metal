// Ported from ~/Downloads/aim/sunburst.qtz's embedded GLSL. fract2/rand3d
// are ported faithfully including their quirk of reading fragCoord.x
// directly regardless of the argument passed in — that's the original
// behavior, not a porting bug. Bass (mouse.x) adds to the fixed rotation,
// treble (mouse.y) speeds the time-driven color cycling.
float fract2_sun(float x, float2 fragCoord) {
    return (fract(fragCoord.x / 2.0) < 0.5) ? fract(x) : 1.0 - fract(fragCoord.x);
}

float rand3d_sun(float3 a, float2 fragCoord) {
    return fract2_sun(a.z + cos(a.x * a.y * 1424.0) * 12345.2, fragCoord);
}

float3 p_sun(float a, float r, float g, float b, float rp, float gp, float bp) {
    return float3(pow(a, rp) * r, pow(a, gp) * g, pow(a, bp) * b);
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]]) {
    float2 fragCoord = float2((in.uv.x * 0.5 + 0.5) * u.resolution.x,
                               (in.uv.y * 0.5 + 0.5) * u.resolution.y);

    float2 position = fragCoord - u.resolution / 2.0;
    float rotAngle = 3.14159265 / 4.0 + u.mouse.x * 1.0;
    float2x2 rot = float2x2(cos(rotAngle), sin(rotAngle), -sin(rotAngle), cos(rotAngle));
    position = rot * position;

    float2 atanPart = atan(position / 600.0) / (position * 3.14159265);
    float thirdComponent = cos(u.time * (1.0 + u.mouse.y * 0.5) / 3.14159265) / (length(floor(position / 7.0)) * 0.023);
    float colorVal = rand3d_sun(float3(atanPart, thirdComponent), fragCoord);

    float3 baseColor = p_sun(colorVal, 2.0, 1.5, 1.0, length(position) * 0.002, 2.5, length(position) * 0.01);

    float3 hueColor = hsv2rgb(float3(fract(u.time * 0.05 + u.colorMagnitude * 0.6), 0.85, clamp(colorVal, 0.0, 1.0)));
    float3 color = mix(baseColor, hueColor, clamp(u.colorMagnitude, 0.0, 1.0) * 0.7);

    return float4(color, 1.0);
}
