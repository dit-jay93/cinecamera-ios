#include <metal_stdlib>
using namespace metal;

// Layout matches CDLUniformBuffer in CDLEngine.swift.
// 3 zones * (4 channels[Y,R,G,B] * 3 floats[S,O,P] + 1 saturation) = 39 floats.
struct CDLZoneUniform {
    float ySlope, yOffset, yPower;
    float rSlope, rOffset, rPower;
    float gSlope, gOffset, gPower;
    float bSlope, bOffset, bPower;
    float saturation;
};

struct CDLUniform {
    CDLZoneUniform shadows;
    CDLZoneUniform midtones;
    CDLZoneUniform highlights;
};

constant float3 kLumaWeights = float3(0.2126, 0.7152, 0.0722);

inline float smoothstepBand(float a, float b, float x) {
    float denom = b - a;
    if (denom == 0.0) return x < a ? 0.0 : 1.0;
    float t = clamp((x - a) / denom, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

inline float3 zoneSlope(CDLZoneUniform z) {
    return float3(z.ySlope * z.rSlope, z.ySlope * z.gSlope, z.ySlope * z.bSlope);
}

inline float3 zoneOffset(CDLZoneUniform z) {
    return float3(z.yOffset + z.rOffset, z.yOffset + z.gOffset, z.yOffset + z.bOffset);
}

inline float3 zonePower(CDLZoneUniform z) {
    return float3(z.yPower * z.rPower, z.yPower * z.gPower, z.yPower * z.bPower);
}

inline float3 applyCDL(float3 rgb, constant CDLUniform& u) {
    float luma = dot(max(rgb, 0.0), kLumaWeights);
    float ws = smoothstepBand(0.5, 0.0, luma);
    float wh = smoothstepBand(0.5, 1.0, luma);
    float wm = max(0.0, 1.0 - ws - wh);

    float3 slope  = zoneSlope(u.shadows)  * ws + zoneSlope(u.midtones)  * wm + zoneSlope(u.highlights)  * wh;
    float3 offset = zoneOffset(u.shadows) * ws + zoneOffset(u.midtones) * wm + zoneOffset(u.highlights) * wh;
    float3 power  = zonePower(u.shadows)  * ws + zonePower(u.midtones)  * wm + zonePower(u.highlights)  * wh;
    float sat = u.shadows.saturation * ws + u.midtones.saturation * wm + u.highlights.saturation * wh;

    float3 lifted = max(rgb * slope + offset, 0.0);
    float3 safePower = max(power, 1e-6);
    float3 graded = pow(lifted, safePower);

    float newLuma = dot(graded, kLumaWeights);
    float3 mono = float3(newLuma);
    return mono + sat * (graded - mono);
}

kernel void cdlApplyKernel(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant CDLUniform& u                  [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 pixel = inTex.read(gid);
    float3 graded = applyCDL(pixel.rgb, u);
    outTex.write(float4(graded, pixel.a), gid);
}
