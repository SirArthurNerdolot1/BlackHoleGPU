#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// Physics constants - matching the scientific implementation
constant float G = 1.0;
constant float M = 1.0;
constant float c = 1.0;
constant float TEMP_RANGE = 39000.0; // 1000K~40000K

// Disk parameters for realistic accretion disk
constant float diskHeight = 0.3;
constant float diskDensityV = 1.0;
constant float diskDensityH = 2.0;
constant float diskNoiseScale = 1.0;
constant float diskSpeed = 0.5;
constant int diskNoiseLOD = 6;

// Ray marching parameters
constant float steps = 0.1;
constant int iteration = 512;

// Integration methods
constant int VERLET = 0;
constant int RK4 = 1;

// Settings structure for scientific controls
struct BlackHoleSettings {
    int integration;
    int accretionDiskOrbit;
    bool disk;
    bool dopplerEffect;
    bool gravitationalRedshift;
    bool beaming;
    bool realisticTemperature;
    float accretionTemp;
};

// Simplex 3D Noise - Scientific Implementation
float4 permute(float4 x) { 
    return fmod(((x * 34.0) + 1.0) * x, 289.0); 
}

float4 taylorInvSqrt(float4 r) { 
    return 1.79284291400159 - 0.85373472095314 * r; 
}

float snoise(float3 v) {
    constant float2 C = float2(1.0/6.0, 1.0/3.0);
    constant float4 D = float4(0.0, 0.5, 1.0, 2.0);

    // First corner
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);

    // Other corners
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);

    float3 x1 = x0 - i1 + 1.0 * C.xxx;
    float3 x2 = x0 - i2 + 2.0 * C.xxx;
    float3 x3 = x0 - 1.0 + 3.0 * C.xxx;

    // Permutations
    i = fmod(i, 289.0);
    float4 p = permute(permute(permute(
        i.z + float4(0.0, i1.z, i2.z, 1.0)) +
        i.y + float4(0.0, i1.y, i2.y, 1.0)) +
        i.x + float4(0.0, i1.x, i2.x, 1.0));

    // Gradients
    float n_ = 1.0/7.0;
    float3 ns = n_ * D.wyz - D.xzx;

    float4 j = p - 49.0 * floor(p * ns.z * ns.z);

    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);

    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);

    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);

    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));

    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);

    // Normalize gradients
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    // Mix final noise value
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float3 toSpherical(float3 pos) {
    float rho = sqrt(pos.x * pos.x + pos.y * pos.y + pos.z * pos.z);
    float theta = atan2(pos.z, pos.x);
    float phi = asin(pos.y / rho);
    return float3(rho, theta, phi);
}

// Blackbody radiation calculation - Scientific Implementation
float4 getBlackBodyColor(float temp) {
    temp = clamp(temp, 1000.0, 40000.0);
    
    // Realistic blackbody color based on temperature
    if (temp < 3500.0) {
        // Red-orange for cooler temperatures
        float t = (temp - 1000.0) / 2500.0;
        return float4(1.0, 0.3 + 0.5 * t, 0.1 * t, 1.0);
    } else if (temp < 7000.0) {
        // Orange-yellow
        float t = (temp - 3500.0) / 3500.0;
        return float4(1.0, 0.8 + 0.2 * t, 0.6 * t, 1.0);
    } else {
        // White-blue for hotter temperatures
        float t = (temp - 7000.0) / 33000.0;
        return float4(1.0 - 0.2 * t, 1.0 - 0.1 * t, 1.0, 1.0);
    }
}

// Gravitational redshift calculation - Scientific
float calculateRedShift(float3 pos) {
    float dist = sqrt(dot(pos, pos));
    if (dist < 1.0) {
        return 0.0;
    }
    float redshift = sqrt(1.0 - 1.0/dist) - 1.0;
    redshift = (1.0 / (1.0 + redshift));
    return redshift;
}

// Doppler effect calculation - Scientific
float calculateDopplerEffect(float3 pos, float3 viewDir, int accretionDiskOrbit) {
    float3 vel;
    float r = length(pos);
    if (r < 1.0) {
        vel = float3(0.0);
        return 1.0;
    }

    float velMag;
    if (accretionDiskOrbit == 0) {
        velMag = -sqrt((G * M / r));    // Non-relativistic speed
    } else {
        velMag = -sqrt((G * M / r) * (1.0 - 3.0 * G * M / (r * c * c)));    // Relativistic speed
    }

    float3 velDir = normalize(cross(float3(0.0, 1.0, 0.0), pos));
    vel = velDir * velMag;

    float3 beta_s = vel / c;
    float gamma = 1.0 / sqrt(1.0 - dot(beta_s, beta_s));
    float dopplerShift = gamma * (1.0 + dot(vel, normalize(viewDir)));

    return dopplerShift;
}

// Realistic temperature distribution - Scientific
float calculateRealisticTemperature(float3 pos, float baseTemp) {
    float radius = length(pos);
    return baseTemp * pow(radius, -0.75);
}

// Schwarzschild acceleration for geodesics - Scientific
float3 acceleration(float h2, float3 pos) {
    float r2 = dot(pos, pos);
    float r5 = pow(r2, 2.5);
    float3 acc = -1.5 * h2 * pos / r5;
    return acc;
}

// Verlet integration for geodesics - Scientific
void verlet(thread float3& pos, float h2, thread float3& dir, float dt) {
    float3 a = acceleration(h2, pos);
    float3 pos_new = pos + dir * dt + 0.5 * a * dt * dt;
    float3 a_new = acceleration(h2, pos_new);

    dir += 0.5 * (a + a_new) * dt;
    pos = pos_new;
}

// RK4 integration for geodesics - Scientific
void rk4(thread float3& pos, float h2, thread float3& dir, float dt) {
    float3 k1_pos = dir;
    float3 k1_vel = acceleration(h2, pos);

    float3 k2_pos = dir + 0.5 * k1_vel * dt;
    float3 k2_vel = acceleration(h2, pos + 0.5 * k1_pos * dt);

    float3 k3_pos = dir + 0.5 * k2_vel * dt;
    float3 k3_vel = acceleration(h2, pos + 0.5 * k2_pos * dt);

    float3 k4_pos = dir + k3_vel * dt;
    float3 k4_vel = acceleration(h2, pos + k3_pos * dt);

    float3 pos_new = pos + (1.0 / 6.0) * (k1_pos + 2.0 * k2_pos + 2.0 * k3_pos + k4_pos) * dt;
    float3 dir_new = dir + (1.0 / 6.0) * (k1_vel + 2.0 * k2_vel + 2.0 * k3_vel + k4_vel) * dt;

    pos = pos_new;
    dir = dir_new;
}

// Accretion disk rendering with full physics - Scientific
void diskRender(float3 pos, thread float4& color, thread float& alpha, float3 viewDir, float time, BlackHoleSettings settings) {
    float innerRadius = 3.0;
    float outerRadius = 9.0;

    float density = max(0.0, 1.0 - length(pos / float3(outerRadius, diskHeight, outerRadius)));

    if (density < 0.001) {
        return;
    }

    density *= pow(1.0 - abs(pos.y) / diskHeight, diskDensityV);
    density *= smoothstep(innerRadius, innerRadius * 1.1, length(pos));

    if (density < 0.001) {
        return;
    }

    float3 sphericalCoord = toSpherical(pos);
    sphericalCoord.y *= 2.0;
    sphericalCoord.z *= 4.0;

    density *= 1.0 / pow(sphericalCoord.x, diskDensityH);
    density *= 16000.0;

    float noise = 1.0;
    for (int i = 0; i < diskNoiseLOD; ++i) {
        noise *= 0.5 * snoise(sphericalCoord * pow(float(i), 2.0) * diskNoiseScale) + 0.5;
        if (i % 2 == 0) {
            sphericalCoord.y -= time * diskSpeed;
        } else {
            sphericalCoord.y += time * diskSpeed;
        }
    }

    float redshift = calculateRedShift(pos);
    float doppler = calculateDopplerEffect(pos, viewDir, settings.accretionDiskOrbit);

    float accretionTempMod = settings.accretionTemp;

    if (settings.realisticTemperature)
        accretionTempMod = calculateRealisticTemperature(pos, accretionTempMod);

    if (settings.dopplerEffect)
        accretionTempMod /= doppler;

    if (settings.gravitationalRedshift)
        accretionTempMod /= redshift;

    float4 dustColor = getBlackBodyColor(accretionTempMod * redshift) * 0.5;

    color += density * dustColor * alpha * abs(noise);

    if (settings.gravitationalRedshift)
        color /= redshift;

    if (settings.beaming)
        color /= doppler * doppler * doppler;
}

// Enhanced starfield with realistic star distribution
float3 starfield(float3 rd) {
    float3 stars = float3(0.0);
    
    // Convert to spherical coordinates for better distribution
    float phi = atan2(rd.z, rd.x);
    float theta = acos(clamp(rd.y, -1.0, 1.0));
    float2 sphericalCoord = float2(phi * 3.0, theta * 6.0);
    
    // Simple hash function for stars
    auto hash = [](float2 p) -> float {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    };
    
    // Multiple star layers with different densities
    for (int i = 0; i < 4; i++) {
        float scale = pow(2.0, float(i)) * 25.0;
        float2 p = sphericalCoord * scale;
        float starNoise = hash(floor(p));
        
        // Create bright, sharp stars with proper thresholds
        float starThreshold = 0.9985 - float(i) * 0.0003;
        if (starNoise > starThreshold) {
            float brightness = pow((starNoise - starThreshold) / (1.0 - starThreshold), 1.5);
            
            // Color variation for realistic stars
            float colorVar = hash(floor(p) + float2(100.0, 200.0));
            float3 starColor;
            if (colorVar > 0.8) {
                starColor = float3(1.2, 1.1, 0.9); // Warm stars
            } else if (colorVar > 0.5) {
                starColor = float3(0.9, 1.0, 1.2); // Cool stars
            } else {
                starColor = float3(1.0, 1.0, 1.0); // White stars
            }
            
            stars += starColor * brightness * (0.3 + 0.7 * float(i == 0));
        }
    }
    
    return stars;
}

// Scientific ray marching with proper Schwarzschild geodesics
float4 rayMarch(float3 pos, float3 dir, float time, BlackHoleSettings settings) {
    float4 color = float4(0.0);
    float alpha = 1.0;

    float3 h = cross(pos, dir);
    float h2 = dot(h, h);

    for (int i = 0; i < iteration; ++i) {
        if (settings.integration == VERLET) {
            verlet(pos, h2, dir, steps);
        } else {
            rk4(pos, h2, dir, steps);
        }

        if (dot(pos, pos) < 1.0) {
            return color;
        }

        if (settings.disk) {
            diskRender(pos, color, alpha, dir, time, settings);
        }
    }

    // Background starfield
    float3 skyColor = starfield(normalize(dir));
    color += float4(skyColor, 1.0);

    return color;
}

// Main compute kernel - Scientific Black Hole Visualization
kernel void computeShader(texture2d<float, access::write> output [[texture(0)]],
                         constant Uniforms& uniforms [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= uint(uniforms.resolution.x) || gid.y >= uint(uniforms.resolution.y)) {
        return;
    }
    
    float2 uv = (2.0 * float2(gid) - uniforms.resolution) / uniforms.resolution.y;
    
    float3 dir = normalize(float3(uv, 1.0));
    float3 pos = uniforms.camera_position;
    
    // Apply camera rotation
    dir = uniforms.camera_rotation * dir;
    
    // Scientific settings - can be made configurable via uniforms
    BlackHoleSettings settings;
    settings.integration = RK4;  // Use RK4 for highest accuracy
    settings.accretionDiskOrbit = 1;  // Relativistic orbit
    settings.disk = true;
    settings.dopplerEffect = true;
    settings.gravitationalRedshift = true;
    settings.beaming = true;
    settings.realisticTemperature = true;
    settings.accretionTemp = 7500.0;
    
    float4 fragColor = rayMarch(pos, dir, uniforms.time, settings);
    
    // Advanced tone mapping for scientific realism
    fragColor.rgb *= 2.5;
    
    // Hable tone mapping
    float3 x = max(float3(0.0), fragColor.rgb - 0.004);
    fragColor.rgb = (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
    
    // Enhanced Gargantua colors
    fragColor.r *= 1.3;
    fragColor.g *= 1.1;
    fragColor.b *= 0.8;
    
    // Advanced bloom effect
    float brightness = dot(fragColor.rgb, float3(0.299, 0.587, 0.114));
    if (brightness > 0.8) {
        fragColor.rgb += float3(0.1, 0.05, 0.02) * (brightness - 0.8);
    }
    
    // Gamma correction
    fragColor.rgb = pow(max(fragColor.rgb, float3(0.0)), float3(1.0/2.2));
    
    output.write(fragColor, gid);
}