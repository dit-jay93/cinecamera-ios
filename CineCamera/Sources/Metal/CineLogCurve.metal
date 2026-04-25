#include <metal_stdlib>
using namespace metal;

constant float CINE_V1_A = 5.555556;
constant float CINE_V1_B = 0.052272;
constant float CINE_V1_C = 0.247190;
constant float CINE_V1_D = 0.385537;
constant float CINE_V1_E = 5.367655;
constant float CINE_V1_F = 0.092809;
constant float CINE_V1_CUT = 0.010591;

constant float CINE_V2_A = 6.5;
constant float CINE_V2_B = 0.055;
constant float CINE_V2_C = 0.235;
constant float CINE_V2_D = 0.39;
constant float CINE_V2_CUT = 0.01;
constant float CINE_V2_KNEE = 0.95;

inline float cineLogV1Encode(float x) {
    if (x >= CINE_V1_CUT) {
        return CINE_V1_C * log10(CINE_V1_A * x + CINE_V1_B) + CINE_V1_D;
    }
    return CINE_V1_E * x + CINE_V1_F;
}

inline float cineLogV1Decode(float y) {
    float cutY = CINE_V1_E * CINE_V1_CUT + CINE_V1_F;
    if (y >= cutY) {
        return (pow(10.0, (y - CINE_V1_D) / CINE_V1_C) - CINE_V1_B) / CINE_V1_A;
    }
    return (y - CINE_V1_F) / CINE_V1_E;
}

inline float cineLogV2Encode(float x) {
    float e = (CINE_V2_C * CINE_V2_A) / ((CINE_V2_A * CINE_V2_CUT + CINE_V2_B) * log(10.0));
    float f = (CINE_V2_C * log10(CINE_V2_A * CINE_V2_CUT + CINE_V2_B) + CINE_V2_D) - e * CINE_V2_CUT;
    if (x >= CINE_V2_CUT) {
        float core = CINE_V2_C * log10(CINE_V2_A * max(x, -CINE_V2_B / CINE_V2_A + 1e-7) + CINE_V2_B) + CINE_V2_D;
        if (core <= CINE_V2_KNEE) return core;
        float over = core - CINE_V2_KNEE;
        return CINE_V2_KNEE + (1.0 - CINE_V2_KNEE) * (1.0 - exp(-over / (1.0 - CINE_V2_KNEE)));
    }
    return e * x + f;
}

kernel void cineLogEncodeKernel(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant uint& variant [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 c = inTex.read(gid);
    float3 rgb;
    if (variant == 0u) {
        rgb = float3(cineLogV1Encode(c.r), cineLogV1Encode(c.g), cineLogV1Encode(c.b));
    } else {
        rgb = float3(cineLogV2Encode(c.r), cineLogV2Encode(c.g), cineLogV2Encode(c.b));
    }
    outTex.write(float4(rgb, c.a), gid);
}
