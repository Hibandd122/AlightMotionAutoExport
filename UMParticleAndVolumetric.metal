#include <metal_stdlib>
using namespace metal;

// =====================================================================
// UMParticleAndVolumetric.metal: GPU Particle Fields, Tunnels, Gravitational
// Lensing, Space-Time Warps, Volumetric Clouds, and Extrusions
// =====================================================================

struct UMEffectUniforms {
    float2 resolution;
    float time;
    float progress;
    float4 params0; // generic parameters (radius, count, speed, scale)
    float4 params1; // generic parameters (density, intensity, turbulence, fade)
    float4 color0;
    float4 color1;
};

// 1. Black Hole & Gravitational Lensing Shader
fragment float4 um_black_hole_lensing_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / u.resolution) * 2.0 - 1.0;
    uv.x *= u.resolution.x / u.resolution.y;
    
    float r = length(uv);
    float eventHorizon = u.params0.x > 0.0 ? u.params0.x : 0.25;
    
    if (r < eventHorizon) {
        return float4(0.0, 0.0, 0.0, 1.0); // Singularity
    }
    
    // Einstein Ring & Gravitational Deflection
    float deflection = (eventHorizon * eventHorizon) / (r * r);
    float2 deflectedUV = (uv * (1.0 - deflection * 0.4));
    deflectedUV.x /= (u.resolution.x / u.resolution.y);
    deflectedUV = deflectedUV * 0.5 + 0.5;
    
    float4 bg = inTex.sample(s, clamp(deflectedUV, 0.0, 1.0));
    // Accretion disk glow
    float glow = smoothstep(eventHorizon + 0.15, eventHorizon, r) * 1.8;
    float3 diskColor = mix(u.color0.rgb, u.color1.rgb, sin(atan2(uv.y, uv.x) * 3.0 + u.time * 4.0) * 0.5 + 0.5);
    
    return float4(bg.rgb + diskColor * glow, bg.a);
}

// 2. High-Speed Cyber / Warp Tunnels
fragment float4 um_warp_tunnel_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = (in_pos.xy / u.resolution) * 2.0 - 1.0;
    uv.x *= u.resolution.x / u.resolution.y;
    
    float r = length(uv);
    float a = atan2(uv.y, uv.x);
    
    float tunnelU = a / 3.14159265;
    float tunnelV = (1.0 / (r + 0.01)) + u.time * 2.0;
    
    float grid = step(0.1, fract(tunnelU * 8.0)) * step(0.1, fract(tunnelV * 4.0));
    float3 tunnelCol = mix(u.color0.rgb, u.color1.rgb, fract(tunnelV * 0.5));
    float fade = exp(-0.8 * r);
    
    return float4(tunnelCol * grid * (1.0 - fade), 1.0);
}

// 3. Volumetric 3D Cloud Density Shader
fragment float4 um_volumetric_clouds_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / u.resolution;
    float4 bg = inTex.sample(s, uv);
    
    // Layered noise simulation for clouds
    float cloudNoise = sin(uv.x * 6.0 + u.time * 0.2) * cos(uv.y * 6.0 - u.time * 0.15);
    cloudNoise += 0.5 * sin(uv.x * 12.0 - u.time * 0.4) * cos(uv.y * 12.0 + u.time * 0.3);
    cloudNoise = smoothstep(0.1, 0.7, cloudNoise * 0.5 + 0.5);
    
    float density = u.params0.x > 0.0 ? u.params0.x : 0.7;
    float3 cloudCol = mix(float3(0.9, 0.95, 1.0), u.color0.rgb, 0.3);
    
    return float4(mix(bg.rgb, cloudCol, cloudNoise * density), bg.a);
}

// 4. GPU 3D Particle Point Field Generator
fragment float4 um_particle_field_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / u.resolution;
    float4 bg = inTex.sample(s, uv);
    
    float particles = 0.0;
    // 32 deterministic animated particle nodes
    for (int i = 0; i < 32; ++i) {
        float seed = float(i) * 13.37;
        float px = fract(sin(seed) * 43758.5453 + u.time * 0.1);
        float py = fract(cos(seed * 1.5) * 23421.6312 + u.time * 0.15);
        float dist = length(uv - float2(px, py));
        particles += 0.003 / (dist * dist + 0.001);
    }
    
    particles = clamp(particles, 0.0, 1.0);
    float3 pColor = mix(u.color0.rgb, u.color1.rgb, sin(u.time + uv.x) * 0.5 + 0.5);
    return float4(bg.rgb + pColor * particles, bg.a);
}

// 5. 3D Bevel Extrusion & Directional Shading
fragment float4 um_bevel_extrusion_fragment(
    float4 in_pos [[position]],
    constant UMEffectUniforms &u [[buffer(0)]],
    texture2d<float, access::sample> inTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float2 uv = in_pos.xy / u.resolution;
    float2 d = float2(1.0) / u.resolution;
    
    float c = inTex.sample(s, uv).a;
    float cx = inTex.sample(s, uv + float2(d.x, 0)).a - inTex.sample(s, uv - float2(d.x, 0)).a;
    float cy = inTex.sample(s, uv + float2(0, d.y)).a - inTex.sample(s, uv - float2(0, d.y)).a;
    
    float3 normal = normalize(float3(-cx * 4.0, -cy * 4.0, 1.0));
    float3 light = normalize(float3(0.5, 0.8, 1.0));
    float diff = max(dot(normal, light), 0.0);
    
    float4 orig = inTex.sample(s, uv);
    return float4(orig.rgb * (0.4 + 0.6 * diff), orig.a);
}
