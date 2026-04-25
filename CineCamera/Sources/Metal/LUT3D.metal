#include <metal_stdlib>
using namespace metal;

struct LUTUniform {
    float size;        // grid resolution, e.g. 33 or 65
    float amount;      // 0..1 mix between original and LUT
    uint  useTetra;    // 0 = trilinear (hardware sampler), 1 = tetrahedral (manual)
    float _pad;
};

constexpr sampler kLutSampler(filter::linear,
                              address::clamp_to_edge,
                              coord::normalized);

// Convert a normalized [0,1] coordinate so the grid endpoints land exactly on
// the first/last texel centers (avoids the half-texel offset bias).
inline float3 lutCoord(float3 rgb, float size) {
    float3 clamped = clamp(rgb, 0.0, 1.0);
    return (clamped * (size - 1.0) + 0.5) / size;
}

// Tetrahedral interpolation using 6-tet decomposition.
inline float3 tetrahedralLookup(texture3d<float, access::read> lut,
                                float3 rgb,
                                float size) {
    float3 clamped = clamp(rgb, 0.0, 1.0);
    float3 scaled = clamped * (size - 1.0);
    float3 base = floor(scaled);
    float3 f = scaled - base;
    int3 i0 = int3(min(base, float3(size - 2.0)));
    int3 i1 = i0 + int3(1, 1, 1);

    float a = f.x; float b = f.y; float c = f.z;

    float3 p000 = lut.read(uint3(i0.x, i0.y, i0.z)).rgb;
    float3 p111 = lut.read(uint3(i1.x, i1.y, i1.z)).rgb;

    if (a > b && b > c) {
        float3 p100 = lut.read(uint3(i1.x, i0.y, i0.z)).rgb;
        float3 p110 = lut.read(uint3(i1.x, i1.y, i0.z)).rgb;
        return (1.0 - a) * p000 + (a - b) * p100 + (b - c) * p110 + c * p111;
    } else if (a > c && c >= b) {
        float3 p100 = lut.read(uint3(i1.x, i0.y, i0.z)).rgb;
        float3 p101 = lut.read(uint3(i1.x, i0.y, i1.z)).rgb;
        return (1.0 - a) * p000 + (a - c) * p100 + (c - b) * p101 + b * p111;
    } else if (c > a && a >= b) {
        float3 p001 = lut.read(uint3(i0.x, i0.y, i1.z)).rgb;
        float3 p101 = lut.read(uint3(i1.x, i0.y, i1.z)).rgb;
        return (1.0 - c) * p000 + (c - a) * p001 + (a - b) * p101 + b * p111;
    } else if (b >= a && a > c) {
        float3 p010 = lut.read(uint3(i0.x, i1.y, i0.z)).rgb;
        float3 p110 = lut.read(uint3(i1.x, i1.y, i0.z)).rgb;
        return (1.0 - b) * p000 + (b - a) * p010 + (a - c) * p110 + c * p111;
    } else if (b >= c && c >= a) {
        float3 p010 = lut.read(uint3(i0.x, i1.y, i0.z)).rgb;
        float3 p011 = lut.read(uint3(i0.x, i1.y, i1.z)).rgb;
        return (1.0 - b) * p000 + (b - c) * p010 + (c - a) * p011 + a * p111;
    } else {
        float3 p001 = lut.read(uint3(i0.x, i0.y, i1.z)).rgb;
        float3 p011 = lut.read(uint3(i0.x, i1.y, i1.z)).rgb;
        return (1.0 - c) * p000 + (c - b) * p001 + (b - a) * p011 + a * p111;
    }
}

kernel void lut3DApplyKernel(
    texture2d<float, access::read>   inTex     [[texture(0)]],
    texture2d<float, access::write>  outTex    [[texture(1)]],
    texture3d<float, access::sample> lutLinear [[texture(2)]],
    texture3d<float, access::read>   lutRead   [[texture(3)]],
    constant LUTUniform& u                     [[buffer(0)]],
    uint2 gid                                  [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 pixel = inTex.read(gid);
    float3 graded;
    if (u.useTetra == 0u) {
        float3 coord = lutCoord(pixel.rgb, u.size);
        graded = lutLinear.sample(kLutSampler, coord).rgb;
    } else {
        graded = tetrahedralLookup(lutRead, pixel.rgb, u.size);
    }
    float t = clamp(u.amount, 0.0, 1.0);
    float3 mixed = mix(pixel.rgb, graded, t);
    outTex.write(float4(mixed, pixel.a), gid);
}
