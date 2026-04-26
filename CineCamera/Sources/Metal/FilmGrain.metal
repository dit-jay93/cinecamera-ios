#include <metal_stdlib>
using namespace metal;

struct GrainUniform {
    float3 channelGain;
    float  size;
    float  intensity;          // already pre-scaled by ISO + intensityMultiplier on CPU
    float  shadowBias;
    uint   monochrome;         // 0 / 1
    uint   frame;
    uint   seed;
    float2 _pad;
};

constant float3 kLumaWeights = float3(0.2126, 0.7152, 0.0722);

inline uint mix32(uint a, uint b) {
    uint x = a ^ b;
    x = x * 0x9E3779B1u;
    x ^= x >> 16;
    return x;
}

inline float hashNoise(int x, int y, int z, uint seed) {
    uint h = seed;
    h = mix32(h, uint(x));
    h = mix32(h, uint(y));
    h = mix32(h, uint(z));
    h ^= h >> 16;
    h = h * 0x7feb352du;
    h ^= h >> 15;
    h = h * 0x846ca68bu;
    h ^= h >> 16;
    float unit = float(h) / 4294967295.0;
    return unit * 2.0 - 1.0;
}

inline float3 sampleGrain(int2 pos, constant GrainUniform& u) {
    float sz = max(u.size, 1e-3);
    int cellX = int(floor(float(pos.x) / sz));
    int cellY = int(floor(float(pos.y) / sz));
    int frame3 = int(u.frame) * 3;
    if (u.monochrome != 0u) {
        float n = hashNoise(cellX, cellY, frame3, u.seed);
        return float3(n) * u.channelGain;
    }
    float r = hashNoise(cellX, cellY, frame3 + 0, u.seed);
    float g = hashNoise(cellX, cellY, frame3 + 1, u.seed);
    float b = hashNoise(cellX, cellY, frame3 + 2, u.seed);
    return float3(r, g, b) * u.channelGain;
}

kernel void filmGrainKernel(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant GrainUniform& u                [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 pixel = inTex.read(gid);
    float luma = clamp(dot(max(pixel.rgb, 0.0), kLumaWeights), 0.0, 1.0);
    float mask = pow(max(0.0, 1.0 - luma), u.shadowBias);
    float3 grain = sampleGrain(int2(gid), u);
    float3 result = pixel.rgb + grain * (u.intensity * mask);
    outTex.write(float4(result, pixel.a), gid);
}
