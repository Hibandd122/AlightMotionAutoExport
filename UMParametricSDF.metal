#include <metal_stdlib>
using namespace metal;

// =====================================================================
// UMParametricSDF.metal: Parametric 3D Shapes, Curves, Toroids, Gems,
// Coins, Chains, Capsules, and Mathematical Raymarch Curves
// =====================================================================

struct UMEffectUniforms {
    float2 resolution;
    float time;
    float progress;
    float4 params0; // generic parameters (radius, length, bevel, scale)
    float4 params1; // generic parameters (rot_x, rot_y, rot_z, gloss)
    float4 color0;
    float4 color1;
};

// 1. Parametric SDF Primitives
static inline float sdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

static inline float sdCylinderP(float3 p, float2 h) {
    float2 d = abs(float2(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

static inline float sdOctahedron(float3 p, float s) {
    p = abs(p);
    return (p.x + p.y + p.z - s) * 0.57735027;
}

static inline float sdTorusP(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// 2. Parametric 3D Gem / Polyhedral Crystal Shader
fragment float4 um_sdf_gem_crystal_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / u.resolution) * 2.0 - 1.0;
    uv.x *= u.resolution.x / u.resolution.y;
    
    float3 ro = float3(0.0, 0.0, -2.5);
    float3 rd = normalize(float3(uv, 1.0));
    
    float angle = u.time * 1.5;
    float ca = cos(angle), sa = sin(angle);
    float3x3 rot = float3x3(float3(ca, 0, sa), float3(0, 1, 0), float3(-sa, 0, ca));
    ro = rot * ro;
    rd = rot * rd;
    
    float t = 0.0;
    for (int i = 0; i < 48 && t < 10.0; ++i) {
        float d = sdOctahedron(ro + rd * t, 0.8);
        if (d < 0.002) break;
        t += d;
    }
    
    if (t < 10.0) {
        float3 p = ro + rd * t;
        float3 norm = normalize(float3(
            sdOctahedron(p + float3(0.001, 0, 0), 0.8) - sdOctahedron(p - float3(0.001, 0, 0), 0.8),
            sdOctahedron(p + float3(0, 0.001, 0), 0.8) - sdOctahedron(p - float3(0, 0.001, 0), 0.8),
            sdOctahedron(p + float3(0, 0, 0.001), 0.8) - sdOctahedron(p - float3(0, 0, 0.001), 0.8)
        ));
        float diff = max(dot(norm, normalize(float3(0.5, 0.8, 1.0))), 0.0);
        float spec = pow(max(dot(reflect(rd, norm), normalize(float3(0.5, 0.8, 1.0))), 0.0), 16.0);
        float3 gemCol = mix(u.color0.rgb, u.color1.rgb, diff) + float3(spec);
        return float4(gemCol, 1.0);
    }
    return inTex.sample(s, in_pos.xy / u.resolution);
}

// 3. Parametric 3D Coin / Cylinder Disc Shader
fragment float4 um_sdf_coin_disc_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / u.resolution) * 2.0 - 1.0;
    uv.x *= u.resolution.x / u.resolution.y;
    
    float3 ro = float3(0.0, 0.0, -2.5);
    float3 rd = normalize(float3(uv, 1.0));
    
    float angle = u.time * 2.0;
    float ca = cos(angle), sa = sin(angle);
    float3x3 rot = float3x3(float3(1, 0, 0), float3(0, ca, -sa), float3(0, sa, ca));
    ro = rot * ro;
    rd = rot * rd;
    
    float t = 0.0;
    for (int i = 0; i < 48 && t < 10.0; ++i) {
        float d = sdCylinderP(ro + rd * t, float2(0.7, 0.08));
        if (d < 0.002) break;
        t += d;
    }
    
    if (t < 10.0) {
        float3 goldCol = mix(float3(1.0, 0.8, 0.2), float3(0.8, 0.5, 0.1), (ro + rd * t).y + 0.5);
        return float4(goldCol, 1.0);
    }
    return inTex.sample(s, in_pos.xy / u.resolution);
}

// 4. Parametric Capsule / Chain Link Shader
fragment float4 um_sdf_capsule_chain_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / u.resolution) * 2.0 - 1.0;
    uv.x *= u.resolution.x / u.resolution.y;
    
    float3 ro = float3(0.0, 0.0, -2.5);
    float3 rd = normalize(float3(uv, 1.0));
    
    float t = 0.0;
    for (int i = 0; i < 48 && t < 10.0; ++i) {
        float d = sdCapsule(ro + rd * t, float3(0, -0.5, 0), float3(0, 0.5, 0), 0.25);
        if (d < 0.002) break;
        t += d;
    }
    
    if (t < 10.0) {
        float3 metalCol = mix(float3(0.7, 0.75, 0.8), float3(0.3, 0.35, 0.4), (ro + rd * t).y);
        return float4(metalCol, 1.0);
    }
    return inTex.sample(s, in_pos.xy / u.resolution);
}
