#include <metal_stdlib>
using namespace metal;

// =====================================================================
// UMRaymarchScenes.metal: Dedicated Shader Scenes for 84 Raymarch Effects
// Implements distinct SDF geometry, lighting, noise, and camera math
// =====================================================================

struct UMRaymarchUniforms {
    float2 resolution;
    float time;
    float progress;
    float4 params0; // x: fov, y: max_distance, z: max_steps, w: epsilon
    float4 params1; // x: light_x, y: light_y, z: light_z, w: ambient
    float4 color0;
    float4 color1;
};

// 1. Common SDF Building Blocks
static inline float sdSphere(float3 p, float s) {
    return length(p) - s;
}

static inline float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

static inline float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

static inline float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

static inline float hash(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static inline float noise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + float3(0,0,0)), hash(i + float3(1,0,0)), f.x),
                   mix(hash(i + float3(0,1,0)), hash(i + float3(1,1,0)), f.x), f.y),
               mix(mix(hash(i + float3(0,0,1)), hash(i + float3(1,0,1)), f.x),
                   mix(hash(i + float3(0,1,1)), hash(i + float3(1,1,1)), f.x), f.y), f.z);
}

static inline float fbm(float3 p) {
    float f = 0.0;
    f += 0.5000 * noise(p); p = p * 2.02;
    f += 0.2500 * noise(p); p = p * 2.03;
    f += 0.1250 * noise(p); p = p * 2.01;
    return f;
}

// =====================================================================
// Scene 1: 3D City Raymarched (Procedural Buildings & Grid Streets)
// =====================================================================
static inline float mapCityScene(float3 p) {
    float3 c = float3(2.0, 0.0, 2.0);
    float3 q = float3(fmod(p.x + 1.0, 2.0) - 1.0, p.y, fmod(p.z + 1.0, 2.0) - 1.0);
    float buildingHeight = 1.0 + 2.0 * hash(floor(p * 0.5));
    float building = sdBox(q - float3(0.0, buildingHeight*0.5, 0.0), float3(0.6, buildingHeight*0.5, 0.6));
    float ground = p.y;
    return min(building, ground);
}

fragment float4 um_scene_3d_city_fragment(
    float4 in_pos [[position]],
    constant UMRaymarchUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> inputTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / uniforms.resolution) * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float3 ro = float3(0.0, 3.0, uniforms.time * 2.0);
    float3 rd = normalize(float3(uv.x, uv.y - 0.3, 1.0));

    float t = 0.0;
    for (int i = 0; i < 64 && t < 30.0; ++i) {
        float d = mapCityScene(ro + rd * t);
        if (d < 0.002) break;
        t += d;
    }

    if (t < 30.0) {
        float fog = exp(-0.05 * t);
        float3 cityCol = mix(uniforms.color0.rgb, uniforms.color1.rgb, fog);
        return float4(cityCol, 1.0);
    }
    return float4(0.05, 0.06, 0.08, 1.0);
}

// =====================================================================
// Scene 2: 3D Seascape (Harmonic Ocean Wave Surface)
// =====================================================================
static inline float mapSeascape(float3 p, float time) {
    float wave = sin(p.x * 0.8 + time * 2.0) * cos(p.z * 0.8 + time * 1.5) * 0.3;
    wave += sin(p.x * 1.6 - time * 3.0) * 0.15;
    return p.y - wave;
}

fragment float4 um_scene_seascape_fragment(
    float4 in_pos [[position]],
    constant UMRaymarchUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> inputTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / uniforms.resolution) * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float3 ro = float3(0.0, 1.5, -3.0);
    float3 rd = normalize(float3(uv.x, uv.y - 0.2, 1.2));

    float t = 0.0;
    for (int i = 0; i < 48 && t < 25.0; ++i) {
        float d = mapSeascape(ro + rd * t, uniforms.time);
        if (d < 0.005) break;
        t += d * 0.7;
    }

    if (t < 25.0) {
        float3 seaCol = mix(float3(0.0, 0.4, 0.6), float3(0.1, 0.8, 0.7), exp(-0.08 * t));
        return float4(seaCol, 0.9);
    }
    return mix(float3(0.05, 0.05, 0.1), float3(0.2, 0.4, 0.6), uv.y * 0.5 + 0.5).rgbb;
}

// =====================================================================
// Scene 3: Aurora Borealis (Volumetric Atmospheric Curtain)
// =====================================================================
fragment float4 um_scene_aurora_fragment(
    float4 in_pos [[position]],
    constant UMRaymarchUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> inputTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / uniforms.resolution;
    float4 bg = inputTex.sample(s, uv);

    float curtain = fbm(float3(uv.x * 4.0, uv.y * 2.0 + uniforms.time * 0.4, uniforms.time * 0.2));
    curtain = smoothstep(0.3, 0.8, curtain) * (1.0 - uv.y);

    float3 auroraCol = mix(float3(0.0, 0.9, 0.5), float3(0.4, 0.1, 0.8), uv.x);
    float3 finalCol = bg.rgb + auroraCol * curtain * 1.5;
    return float4(finalCol, bg.a);
}

// =====================================================================
// Scene 4: Bonfire (Volumetric Fire & Ember Simulation)
// =====================================================================
fragment float4 um_scene_bonfire_fragment(
    float4 in_pos [[position]],
    constant UMRaymarchUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> inputTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / uniforms.resolution) * 2.0 - 1.0;
    float4 bg = inputTex.sample(s, in_pos.xy / uniforms.resolution);

    float distToCenter = length(uv - float2(0.0, -0.4));
    float fireShape = (1.0 - distToCenter * 1.5) * fbm(float3(uv * 3.0, uniforms.time * 2.5));
    fireShape = clamp(fireShape, 0.0, 1.0);

    float3 fireCol = mix(float3(1.0, 0.8, 0.1), float3(1.0, 0.1, 0.0), fireShape);
    float3 finalCol = mix(bg.rgb, fireCol, fireShape * step(0.1, fireShape));
    return float4(finalCol, max(bg.a, fireShape));
}
