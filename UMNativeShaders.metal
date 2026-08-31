#include <metal_stdlib>
using namespace metal;

// =====================================================================
// UMNativeShaders.metal: Native Metal Shader Engines for Distortion,
// Retro/CRT, Procedural Blending, Nature, Space and Depth Effects
// =====================================================================

struct UMEffectUniforms {
    float2 resolution;
    float time;
    float progress;
    float4 params0; // generic floats (radius, angle, freq, amp)
    float4 params1; // generic floats (strength, mode, speed, scale)
    float4 color0;
    float4 color1;
};

// 1. Distortion: Circular Ripple & Polar Coordinate Warp
fragment float4 um_distort_ripple_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / u.resolution;
    float2 c = float2(0.5, 0.5);
    float2 d = uv - c;
    float r = length(d);
    
    float freq = u.params0.x > 0.0 ? u.params0.x : 15.0;
    float amp = u.params0.y > 0.0 ? u.params0.y : 0.03;
    float wave = sin(r * freq - u.time * 4.0) * amp * (1.0 - smoothstep(0.0, 0.5, r));
    
    float2 warpedUV = uv + normalize(d + float2(0.0001)) * wave;
    return inTex.sample(s, clamp(warpedUV, 0.0, 1.0));
}

// 2. Retro/CRT: Scanlines, Phosphor Mask & Vignette Curvature
fragment float4 um_retro_crt_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / u.resolution;
    // Barrel distortion
    float2 cc = uv - 0.5;
    float dist = dot(cc, cc);
    float2 crtUV = 0.5 + cc * (1.0 + dist * 0.15);
    
    if (crtUV.x < 0.0 || crtUV.x > 1.0 || crtUV.y < 0.0 || crtUV.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    
    float4 col = inTex.sample(s, crtUV);
    // Scanlines
    float scanline = sin(crtUV.y * u.resolution.y * 1.5) * 0.15;
    col.rgb -= scanline;
    // Phosphor tint
    col.rgb *= float3(0.95, 1.05, 0.95);
    return col;
}

// 3. Procedural Blends: Color Burn, Dodge, Multiply, Overlay
fragment float4 um_blend_modes_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / u.resolution;
    float4 base = inTex.sample(s, uv);
    float3 blend = u.color0.rgb;
    int mode = int(u.params0.x);
    
    float3 result = base.rgb;
    if (mode == 0) { // Multiply
        result = base.rgb * blend;
    } else if (mode == 1) { // Color Dodge
        result = base.rgb / (1.0001 - blend);
    } else if (mode == 2) { // Color Burn
        result = 1.0 - (1.0 - base.rgb) / (blend + 0.0001);
    } else if (mode == 3) { // Screen
        result = 1.0 - (1.0 - base.rgb) * (1.0 - blend);
    }
    float opacity = u.params0.y > 0.0 ? u.params0.y : 1.0;
    return float4(mix(base.rgb, clamp(result, 0.0, 1.0), opacity), base.a);
}

// 4. Procedural Block Noise & Grain Generator
fragment float4 um_procedural_blocknoise_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / u.resolution;
    float4 base = inTex.sample(s, uv);
    
    float blockSize = u.params0.x > 0.0 ? u.params0.x : 16.0;
    float2 blockUV = floor(in_pos.xy / blockSize) * blockSize;
    
    float n = fract(sin(dot(blockUV + u.time * 10.0, float2(12.9898, 78.233))) * 43758.5453);
    float strength = u.params0.y > 0.0 ? u.params0.y : 0.2;
    
    return float4(mix(base.rgb, float3(n), strength), base.a);
}

// 5. 3D Depth & Cube Geometry Mesh Projection
fragment float4 um_depth_cube_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / u.resolution) * 2.0 - 1.0;
    uv.x *= u.resolution.x / u.resolution.y;
    
    float3 ro = float3(0.0, 0.0, -2.5);
    float3 rd = normalize(float3(uv, 1.0));
    
    // Rotate cube by uniforms
    float angle = u.time * 1.5 + u.params0.x;
    float ca = cos(angle), sa = sin(angle);
    float3x3 rot = float3x3(
        float3(ca, 0, sa),
        float3(0, 1, 0),
        float3(-sa, 0, ca)
    );
    ro = rot * ro;
    rd = rot * rd;
    
    // Ray-box intersection
    float3 m = 1.0 / rd;
    float3 n = m * ro;
    float3 k = abs(m) * float3(0.6);
    float3 t1 = -n - k;
    float3 t2 = -n + k;
    float tN = max(max(t1.x, t1.y), t1.z);
    float tF = min(min(t2.x, t2.y), t2.z);
    
    if (tN < tF && tF > 0.0) {
        float3 pos = ro + rd * tN;
        float2 faceUV = pos.xy * 0.8 + 0.5;
        float4 texCol = inTex.sample(s, clamp(faceUV, 0.0, 1.0));
        return float4(texCol.rgb * 1.2, 1.0);
    }
    return inTex.sample(s, in_pos.xy / u.resolution);
}
