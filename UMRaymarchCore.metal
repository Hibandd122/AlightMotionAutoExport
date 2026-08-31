#include <metal_stdlib>
using namespace metal;

// =====================================================================
// UMRaymarchCore.metal: Universal Procedural Raymarching Shader Engine
// Architecture: Bounded steps, dynamic quality level, SDF primitives
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

// 1. Common Math & SDF Primitives
float sdSphere(float3 p, float s) {
    return length(p) - s;
}

float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdCylinder(float3 p, float3 c) {
    return length(p.xz - c.xy) - c.z;
}

// 2. Smooth Minimum & Maxima
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3. 3D Noise & Fractal Brownian Motion
float hash(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + float3(0,0,0)), hash(i + float3(1,0,0)), f.x),
                   mix(hash(i + float3(0,1,0)), hash(i + float3(1,1,0)), f.x), f.y),
               mix(mix(hash(i + float3(0,0,1)), hash(i + float3(1,0,1)), f.x),
                   mix(hash(i + float3(0,1,1)), hash(i + float3(1,1,1)), f.x), f.y), f.z);
}

float fbm(float3 p) {
    float f = 0.0;
    f += 0.5000 * noise(p); p = p * 2.02;
    f += 0.2500 * noise(p); p = p * 2.03;
    f += 0.1250 * noise(p); p = p * 2.01;
    return f;
}

// 4. Raymarch Core Function with Bounded Iteration Loop
fragment float4 um_raymarch_procedural_fragment(
    float4 in_pos [[position]],
    constant UMRaymarchUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> inputTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / uniforms.resolution) * 2.0 - 1.0;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;

    float3 ro = float3(0.0, 0.0, -3.0);
    float3 rd = normalize(float3(uv, 1.0));

    float max_dist = uniforms.params0.y > 0.0 ? uniforms.params0.y : 20.0;
    int max_steps = int(uniforms.params0.z > 0.0 ? uniforms.params0.z : 64.0);
    float eps = uniforms.params0.w > 0.0 ? uniforms.params0.w : 0.001;

    float t = 0.0;
    float d = 0.0;

    for (int i = 0; i < max_steps && t < max_dist; ++i) {
        float3 p = ro + rd * t;
        // Evaluate dynamic scene SDF
        d = smin(sdSphere(p, 1.0 + 0.1 * sin(uniforms.time * 2.0)), sdBox(p, float3(0.8)), 0.2);
        if (d < eps) break;
        t += d;
    }

    if (t < max_dist) {
        float3 p = ro + rd * t;
        float3 norm = normalize(float3(
            sdSphere(p + float3(eps, 0, 0), 1.0) - sdSphere(p - float3(eps, 0, 0), 1.0),
            sdSphere(p + float3(0, eps, 0), 1.0) - sdSphere(p - float3(0, eps, 0), 1.0),
            sdSphere(p + float3(0, 0, eps), 1.0) - sdSphere(p - float3(0, 0, eps), 1.0)
        ));

        float3 lightDir = normalize(uniforms.params1.xyz);
        float diff = max(dot(norm, lightDir), 0.0);
        float3 col = mix(uniforms.color0.rgb, uniforms.color1.rgb, diff);
        return float4(col, 1.0);
    }

    // Blend with underlying canvas texture
    float2 texUV = in_pos.xy / uniforms.resolution;
    float4 origCol = inputTex.sample(s, texUV);
    return origCol;
}
