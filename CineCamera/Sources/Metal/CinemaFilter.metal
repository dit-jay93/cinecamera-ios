#include <metal_stdlib>
using namespace metal;

constant float3 kLumaWeights = float3(0.2126, 0.7152, 0.0722);

struct FilterPixelUniform {
    float3 transmittance;
    float  intensity;
    float  saturationReduction;
    float  blackLift;
    float2 _pad;
};

struct GaussianUniform {
    int   radius;
    int   horizontal;     // 0 = vertical pass, 1 = horizontal
    float threshold;      // bloom threshold; 0 = whole frame
    float _pad;
};

inline float3 applyFilterPixel(float3 rgb, constant FilterPixelUniform& u) {
    float t = clamp(u.intensity, 0.0, 1.0);
    float3 mixT = mix(float3(1.0), u.transmittance, t);
    float3 out = rgb * mixT;
    float sr = u.saturationReduction * t;
    if (sr > 0.0) {
        float luma = dot(out, kLumaWeights);
        out = mix(float3(luma), out, 1.0 - sr);
    }
    float lift = u.blackLift * t;
    if (lift > 0.0) {
        out = out + lift * (1.0 - out);
    }
    return out;
}

kernel void filterPixelKernel(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant FilterPixelUniform& u          [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 pixel = inTex.read(gid);
    float3 out = applyFilterPixel(pixel.rgb, u);
    outTex.write(float4(out, pixel.a), gid);
}

inline float gaussianWeight(int i, float sigma) {
    return exp(-float(i * i) / (2.0 * sigma * sigma));
}

kernel void gaussianBlurKernel(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant GaussianUniform& u             [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    int r = max(u.radius, 0);
    if (r == 0) {
        outTex.write(inTex.read(gid), gid);
        return;
    }
    float sigma = float(r) / 3.0;
    int W = int(inTex.get_width());
    int H = int(inTex.get_height());
    float3 sum = float3(0.0);
    float wSum = 0.0;
    for (int k = -r; k <= r; ++k) {
        float w = gaussianWeight(k, sigma);
        int sx = int(gid.x);
        int sy = int(gid.y);
        if (u.horizontal != 0) {
            sx = clamp(int(gid.x) + k, 0, W - 1);
        } else {
            sy = clamp(int(gid.y) + k, 0, H - 1);
        }
        float3 pixel = inTex.read(uint2(sx, sy)).rgb;
        if (u.threshold > 0.0) {
            float luma = clamp(dot(pixel, kLumaWeights), 0.0, 1.0);
            float m = max(0.0, luma - u.threshold) / max(1e-3, 1.0 - u.threshold);
            pixel *= m;
        }
        sum += pixel * w;
        wSum += w;
    }
    outTex.write(float4(sum / wSum, 1.0), gid);
}

struct BloomCompositeUniform {
    float gain;
    float3 _pad;
};

kernel void bloomCompositeKernel(
    texture2d<float, access::read>  baseTex  [[texture(0)]],
    texture2d<float, access::read>  bloomTex [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant BloomCompositeUniform& u         [[buffer(0)]],
    uint2 gid                                 [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float4 b = baseTex.read(gid);
    float3 bloom = bloomTex.read(gid).rgb;
    outTex.write(float4(b.rgb + bloom * u.gain, b.a), gid);
}
