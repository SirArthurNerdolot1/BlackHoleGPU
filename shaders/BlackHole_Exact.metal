#include <metal_stdlib>
using namespace metal;

// Exact constants from scientific repository
constant float G = 1.0;
constant float M = 1.0;
constant float c = 1.0;
constant float TEMP_RANGE = 39000.0; // 1000K~40000K

// Disk parameters (exact from repository)
constant float diskHeight = 0.3;
constant float diskDensityV = 1.0;
constant float diskDensityH = 2.0;
constant float diskNoiseScale = 1.0;
constant float diskSpeed = 0.5;
constant int diskNoiseLOD = 6;

// Ray marching parameters (exact from repository)
constant float steps = 0.1;
constant int iteration = 512;  // Exact value from repository

struct Uniforms {
    float2 resolution;
    float time;
    float gravity;
    float disk_radius;
    float disk_thickness;
    float black_hole_size;
    float camera_distance;
};

// Exact simplex noise from repository
float4 permute(float4 x) { 
    return fmod(((x*34.0)+1.0)*x, 289.0); 
}

float4 taylorInvSqrt(float4 r) { 
    return 1.79284291400159 - 0.85373472095314 * r; 
}

float snoise(float3 v) {
    const float2 C = float2(1.0/6.0, 1.0/3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);

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
        i.z + float4(0.0, i1.z, i2.z, 1.0))
        + i.y + float4(0.0, i1.y, i2.y, 1.0))
        + i.x + float4(0.0, i1.x, i2.x, 1.0));

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

    float4 s0 = floor(b0)*2.0 + 1.0;
    float4 s1 = floor(b1)*2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));

    float4 a0 = b0.xzyw + s0.xzyw*sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw*sh.zzww;

    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);

    float4 norm = taylorInvSqrt(float4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    float4 m = max(0.6 - float4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m*m, float4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

// Coordinate transformation (exact from repository)
float3 toSpherical(float3 pos) {
    float rho = sqrt((pos.x * pos.x) + (pos.y * pos.y) + (pos.z * pos.z));
    float theta = atan2(pos.z, pos.x);
    float phi = asin(pos.y / rho);
    return float3(rho, theta, phi);
}

// Blackbody color approximation (repository uses texture lookup)
float4 getBlackBodyColor(float temp) {
    temp = clamp(temp, 1000.0, 40000.0);
    float x_coord = (temp - 1000.0) / TEMP_RANGE;
    
    // Simplified blackbody approximation
    float3 color;
    if (temp < 3500.0) {
        color = float3(1.0, 0.3 + 0.7 * (temp - 1000.0) / 2500.0, 0.0);
    } else if (temp < 5000.0) {
        color = float3(1.0, 0.8 + 0.2 * (temp - 3500.0) / 1500.0, 0.1 + 0.4 * (temp - 3500.0) / 1500.0);
    } else {
        float t = (temp - 5000.0) / 35000.0;
        color = float3(1.0 - 0.3 * t, 1.0 - 0.2 * t, 1.0);
    }
    
    return float4(color, 1.0);
}

// Exact physics calculations from repository
float calculateRedShift(float3 pos) {
    float dist = sqrt(dot(pos, pos));
    if (dist < 1.0) {
        return 0.0;
    }
    float redshift = sqrt(1.0 - 1.0/dist) - 1.0;
    redshift = (1.0 / (1.0 + redshift));
    return redshift;
}

float calculateDopplerEffect(float3 pos, float3 viewDir) {
    float3 vel;
    float r = length(pos);
    if (r < 1.0) {
        return 1.0;
    }

    // Relativistic orbital velocity
    float velMag = -sqrt((G * M / r) * (1.0 - 3.0 * G * M / (r * c * c)));
    float3 velDir = normalize(cross(float3(0.0, 1.0, 0.0), pos));
    vel = velDir * velMag;

    float3 beta_s = vel / c;
    float gamma = 1.0 / sqrt(1.0 - dot(beta_s, beta_s));
    float dopplerShift = gamma * (1.0 + dot(vel, normalize(viewDir)));

    return dopplerShift;
}

float calculateRealisticTemperature(float3 pos, float baseTemp) {
    float radius = length(pos);
    return baseTemp * pow(radius, -0.75);
}

// Exact disk rendering from repository
void diskRender(float3 pos, thread float4& color, thread float& alpha, float3 viewDir, float time) {
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
    float doppler = calculateDopplerEffect(pos, viewDir);

    float accretionTempMod = 7500.0;  // Base temperature
    accretionTempMod = calculateRealisticTemperature(pos, accretionTempMod);
    accretionTempMod /= doppler;
    accretionTempMod /= redshift;

    float4 dustColor = getBlackBodyColor(accretionTempMod * redshift) * 0.5;

    color += density * dustColor * alpha * abs(noise);
    color /= redshift;
    color /= doppler * doppler * doppler;
}

// Exact acceleration from repository
float3 acceleration(float h2, float3 pos) {
    float r2 = dot(pos, pos);
    float r5 = pow(r2, 2.5);
    float3 acc = -1.5 * h2 * pos / r5;
    return acc;
}

// Exact Verlet integration from repository
void verlet(thread float3& pos, float h2, thread float3& dir, float dt) {
    float3 a = acceleration(h2, pos);
    float3 pos_new = pos + dir * dt + 0.5 * a * dt * dt;
    float3 a_new = acceleration(h2, pos_new);

    dir += 0.5 * (a + a_new) * dt;
    pos = pos_new;
}

// Exact RK4 integration from repository
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

// Exact ray marching from repository
float4 rayMarch(float3 pos, float3 dir, float time) {
    float4 color = float4(0.0);
    float alpha = 1.0;

    float3 h = cross(pos, dir);
    float h2 = dot(h, h);

    for (int i = 0; i < iteration; ++i) {
        // Use RK4 integration (integrationType == 1 in repository)
        rk4(pos, h2, dir, steps);

        if (dot(pos, pos) < 1.0) {
            return color;
        }

        // Disk rendering enabled
        diskRender(pos, color, alpha, dir, time);
    }

    // Background stars (simplified - repository uses cubemap)
    float3 skyColor = float3(0.0, 0.0, 0.02) * (1.0 + 0.5 * snoise(dir * 10.0));
    color += float4(skyColor, 1.0);

    return color;
}

// Main compute kernel - exact coordinate system from repository
kernel void computeShader(texture2d<float, access::write> output [[texture(0)]],
                         constant Uniforms& uniforms [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= uint(uniforms.resolution.x) || gid.y >= uint(uniforms.resolution.y)) {
        return;
    }
    
    // Exact coordinate transformation from repository
    float2 uv = (2.0 * float2(gid) - uniforms.resolution.xy) / uniforms.resolution.y;
    
    float3 dir = normalize(float3(uv, 1.0));
    float3 pos = float3(0.0, 0.0, uniforms.camera_distance);
    
    // Simple view transformation (repository uses proper view matrix)
    float angle = uniforms.time * 0.05;
    float cosA = cos(angle);
    float sinA = sin(angle);
    
    // Rotate camera position
    pos = float3(cosA * pos.x - sinA * pos.z, pos.y, sinA * pos.x + cosA * pos.z);
    
    float4 fragColor = rayMarch(pos, dir, uniforms.time);
    
    output.write(fragColor, gid);
}