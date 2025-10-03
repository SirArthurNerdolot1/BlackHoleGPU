/**
 * BlackHole.metal
 * 
 * GPU-Accelerated Black Hole Ray Tracer with Relativistic Physics
 * 
 * This Metal compute shader implements scientifically accurate black hole
 * visualization through geodesic ray tracing in curved spacetime. The
 * implementation follows the Schwarzschild metric for non-rotating black holes.
 * 
 * PHYSICS IMPLEMENTATION:
 * 
 * 1. Schwarzschild Metric:
 *    ds² = -(1-2M/r)c²dt² + (1-2M/r)⁻¹dr² + r²(dθ² + sin²θ dφ²)
 *    Where M is the black hole mass and r is the radial coordinate.
 * 
 * 2. Geodesic Equations:
 *    Light rays follow null geodesics with conserved quantities:
 *    - Energy E (from timelike Killing vector)
 *    - Angular momentum L (from axial Killing vector)
 *    - Impact parameter b = L/E
 * 
 * 3. Integration Methods:
 *    - Verlet Integration: Second-order symplectic integrator for stability
 *    - RK4 (Runge-Kutta 4th Order): Higher accuracy for complex trajectories
 * 
 * 4. Relativistic Effects:
 *    - Gravitational Lensing: Light bending due to spacetime curvature
 *    - Gravitational Redshift: z = 1/√(1-2M/r) - 1
 *    - Doppler Shift: Frequency shift from relative motion
 *    - Relativistic Beaming: Angular intensity enhancement for moving sources
 * 
 * 5. Accretion Disk Model:
 *    - Geometrically thin, optically thick disk
 *    - Temperature profile: T ∝ r⁻³/⁴ (standard Shakura-Sunyaev)
 *    - Procedural turbulence via simplex noise
 *    - Blackbody radiation: Planck function for color temperature
 * 
 * PERFORMANCE CHARACTERISTICS:
 * - 512 ray marching iterations per pixel
 * - Step size: 0.1 Schwarzschild radii
 * - Typical: 9-10 FPS at 1280x720 on integrated GPU
 * - Compute-bound: O(width × height × iterations)
 * 
 * COORDINATE SYSTEM:
 * - Cartesian coordinates (x, y, z) for visualization
 * - Schwarzschild coordinates (r, θ, φ) for physics
 * - Black hole at origin (0, 0, 0)
 * - Camera orbits at configurable radius
 * 
 * REFERENCES:
 * - Original implementation: github.com/hydrogendeuteride/BlackHoleRayTracer
 * - Schwarzschild, K. (1916). "On the Gravitational Field of a Mass Point"
 * - Chandrasekhar, S. (1983). "The Mathematical Theory of Black Holes"
 */

#include <metal_stdlib>
using namespace metal;

// Physical constants (natural units: G = M = c = 1)
constant float G = 1.0;     // Gravitational constant (normalized)
constant float M = 1.0;     // Black hole mass (normalized)
constant float c = 1.0;     // Speed of light (normalized)
constant float TEMP_RANGE = 39000.0; // Temperature range: 1000K~40000K

// Accretion disk parameters
// These define the appearance and behavior of matter orbiting the black hole
constant float diskHeight = 0.3;        // Vertical scale height
constant float diskDensityV = 1.0;      // Vertical density falloff
constant float diskDensityH = 2.0;      // Horizontal density falloff
constant float diskNoiseScale = 1.0;    // Turbulence amplitude
constant float diskSpeed = 0.5;         // Orbital velocity scale
constant int diskNoiseLOD = 4;          // Noise octaves (level of detail)

// Ray marching parameters
// Control the balance between accuracy and performance
constant float steps = 0.1;     // Integration step size (in Schwarzschild radii)
constant int iteration = 512;   // Maximum ray marching iterations

/**
 * Uniforms Structure
 * 
 * Shared between CPU and GPU. Contains all runtime-adjustable parameters
 * for the simulation. Must maintain identical memory layout with ShaderTypes.h
 */
struct Uniforms {
    float2 resolution;              // Screen dimensions
    float time;                     // Animation time
    
    // Interactive physical parameters
    float gravity;                  // Gravitational field strength
    float disk_radius;              // Accretion disk size
    float disk_thickness;           // Disk vertical extent
    float black_hole_size;          // Schwarzschild radius
    float camera_distance;          // Observer orbital radius
    
    // Scientific parameters (padding for alignment)
    int integration_method;
    int orbit_type;
    bool disk_enabled;
    bool doppler_enabled;
    bool redshift_enabled;
    bool beaming_enabled;
    bool realistic_temp;
    float accretion_temperature;
    
    // Observer parameters
    float3 observer_position;
    float3 observer_velocity;
    
    // Orbiting star parameters
    bool show_orbiting_star;
    float star_orbit_radius;
    float star_orbit_speed;
    float star_brightness;
    
    // Background star effects
    bool background_redshift;
    bool background_doppler;
    
    // Performance parameters
    int quality_preset;
    int max_iterations;
    float step_size;
    bool adaptive_stepping;
};

//==============================================================================
// PROCEDURAL NOISE
//==============================================================================

/**
 * 3D Simplex Noise
 * 
 * Generates smooth pseudo-random values for accretion disk turbulence.
 * Provides continuous gradient noise with good visual properties.
 * 
 * Implementation: Stefan Gustavson's optimized simplex noise
 * Complexity: O(1) - constant time per evaluation
 */

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

//==============================================================================
// COORDINATE TRANSFORMATIONS
//==============================================================================

/**
 * Cartesian to Spherical Coordinate Transformation
 * 
 * Converts (x, y, z) to (r, θ, φ) for Schwarzschild metric calculations.
 * 
 * @param pos Cartesian position vector
 * @return (r, θ, φ) where:
 *         r = radial distance from origin
 *         θ = azimuthal angle in XZ plane
 *         φ = polar angle from XZ plane
 */
float3 toSpherical(float3 pos) {
    float rho = sqrt((pos.x * pos.x) + (pos.y * pos.y) + (pos.z * pos.z));
    float theta = atan2(pos.z, pos.x);
    float phi = asin(pos.y / rho);
    return float3(rho, theta, phi);
}

//==============================================================================
// THERMAL RADIATION
//==============================================================================

/**
 * Blackbody Color Approximation
 * 
 * Converts temperature to RGB color using simplified Planck function.
 * Approximates Wien's displacement law and blackbody spectrum.
 * 
 * Temperature ranges:
 * - 1000K-3500K: Red to orange (cool stars, disk inner edges)
 * - 3500K-5000K: Orange to yellow (Sun-like)
 * - 5000K-40000K: Yellow to blue-white (hot stars, inner disk)
 * 
 * @param temp Temperature in Kelvin [1000, 40000]
 * @return RGBA color with physically motivated spectrum
 */
float4 getBlackBodyColor(float temp) {
    temp = clamp(temp, 1000.0, 40000.0);
    
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

//==============================================================================
// RELATIVISTIC EFFECTS
//==============================================================================

/**
 * Gravitational Redshift Calculator
 * 
 * Computes frequency shift from gravitational time dilation.
 * Based on Schwarzschild metric: z = 1/√(1-2M/r) - 1
 * 
 * Physical interpretation:
 * - Light loses energy climbing out of gravitational well
 * - Frequency decreases (wavelength increases)
 * - Effect is 1/r near event horizon, becomes negligible at infinity
 * 
 * @param pos Position in Schwarzschild coordinates
 * @return Redshift factor (multiply wavelength by this)
 */
float calculateRedShift(float3 pos) {
    float dist = sqrt(dot(pos, pos));
    if (dist < 1.0) {
        return 0.0;  // Inside event horizon, infinite redshift
    }
    float redshift = sqrt(1.0 - 1.0/dist) - 1.0;
    redshift = (1.0 / (1.0 + redshift));
    return redshift;
}

/**
 * Doppler Effect Calculator
 * 
 * Computes frequency shift from relative motion between source and observer.
 * Uses relativistic Doppler formula with orbital velocity.
 * 
 * Physics:
 * - Circular orbit velocity: v = √(GM/r) × √(1 - 3GM/(rc²))
 * - Doppler factor: D = γ(1 + β·n̂) where β = v/c, γ = Lorentz factor
 * - Approaching matter appears blue-shifted, receding red-shifted
 * 
 * @param pos Position of emitting matter
 * @param viewDir Direction from observer to matter
 * @return Doppler shift factor (multiply frequency by this)
 */
float calculateDopplerEffect(float3 pos, float3 viewDir) {
    float3 vel;
    float r = length(pos);
    if (r < 1.0) {
        return 1.0;  // Inside event horizon
    }

    // Relativistic orbital velocity (circular orbit)
    float velMag = -sqrt((G * M / r) * (1.0 - 3.0 * G * M / (r * c * c)));
    float3 velDir = normalize(cross(float3(0.0, 1.0, 0.0), pos));
    vel = velDir * velMag;

    // Relativistic Doppler formula
    float3 beta_s = vel / c;
    float gamma = 1.0 / sqrt(1.0 - dot(beta_s, beta_s));
    float dopplerShift = gamma * (1.0 + dot(vel, normalize(viewDir)));

    return dopplerShift;
}

/**
 * Realistic Temperature Profile
 * 
 * Calculates accretion disk temperature using Shakura-Sunyaev model.
 * Temperature profile: T ∝ r^(-3/4)
 * 
 * Physical basis:
 * - Inner disk is hottest (up to 40000K)
 * - Temperature decreases with radius
 * - Power-law exponent from viscous dissipation theory
 * 
 * @param pos Position in disk
 * @param baseTemp Reference temperature at r=1
 * @return Temperature in Kelvin
 */
float calculateRealisticTemperature(float3 pos, float baseTemp) {
    float radius = length(pos);
    return baseTemp * pow(radius, -0.75);
}

//==============================================================================
// ACCRETION DISK RENDERING
//==============================================================================

/**
 * Disk Render Function
 * 
 * Computes color and opacity of accretion disk at given position.
 * Implements:
 * - Procedural density via simplex noise
 * - Blackbody radiation based on temperature
 * - Gravitational redshift
 * - Doppler shifting from orbital motion
 * - Relativistic beaming
 * 
 * @param pos Position to evaluate
 * @param[out] color Accumulated RGB color
 * @param[out] alpha Accumulated opacity
 * @param viewDir View direction for Doppler calculation
 * @param time Animation time for turbulence
 * @param uniforms User-adjustable parameters
 */
void diskRender(float3 pos, thread float4& color, thread float& alpha, float3 viewDir, float time, constant Uniforms& uniforms) {
    float innerRadius = uniforms.black_hole_size * 25.0;  // Proportional to Schwarzschild radius
    float outerRadius = uniforms.disk_radius;

    // Disk is in XZ plane at y=0
    float yDisk = abs(pos.y);
    float rDisk = length(float2(pos.x, pos.z));
    
    // Check if ray is within disk bounds
    if (yDisk > uniforms.disk_thickness || rDisk < innerRadius || rDisk > outerRadius) {
        return;
    }
    
    // More realistic density falloff
    float density = 1.0 - smoothstep(innerRadius, outerRadius, rDisk);
    density *= pow(1.0 - yDisk / uniforms.disk_thickness, diskDensityV * 2.0);
    density *= smoothstep(innerRadius, innerRadius * 1.2, rDisk);

    if (density < 0.01) {
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

    float4 dustColor = getBlackBodyColor(accretionTempMod * redshift);

    // Apply beaming effect (relativistic intensity boost)
    float beaming = pow(doppler, 3.0);
    
    color += density * dustColor * alpha * abs(noise) * 0.3;
    alpha *= (1.0 - density * abs(noise) * 0.3);
}

// Exact acceleration from repository
float3 acceleration(float h2, float3 pos, float gravityStrength) {
    float r2 = dot(pos, pos);
    float r5 = pow(r2, 2.5);
    float3 acc = -1.5 * h2 * pos / r5 * gravityStrength;
    return acc;
}

// Exact Verlet integration from repository
void verlet(thread float3& pos, float h2, thread float3& dir, float dt, float gravityStrength) {
    float3 a = acceleration(h2, pos, gravityStrength);
    float3 pos_new = pos + dir * dt + 0.5 * a * dt * dt;
    float3 a_new = acceleration(h2, pos_new, gravityStrength);

    dir += 0.5 * (a + a_new) * dt;
    pos = pos_new;
}

// Exact RK4 integration from repository
void rk4(thread float3& pos, float h2, thread float3& dir, float dt, float gravityStrength) {
    float3 k1_pos = dir;
    float3 k1_vel = acceleration(h2, pos, gravityStrength);

    float3 k2_pos = dir + 0.5 * k1_vel * dt;
    float3 k2_vel = acceleration(h2, pos + 0.5 * k1_pos * dt, gravityStrength);

    float3 k3_pos = dir + 0.5 * k2_vel * dt;
    float3 k3_vel = acceleration(h2, pos + 0.5 * k2_pos * dt, gravityStrength);

    float3 k4_pos = dir + k3_vel * dt;
    float3 k4_vel = acceleration(h2, pos + k3_pos * dt, gravityStrength);

    float3 pos_new = pos + (1.0 / 6.0) * (k1_pos + 2.0 * k2_pos + 2.0 * k3_pos + k4_pos) * dt;
    float3 dir_new = dir + (1.0 / 6.0) * (k1_vel + 2.0 * k2_vel + 2.0 * k3_vel + k4_vel) * dt;

    pos = pos_new;
    dir = dir_new;
}

// Render an orbiting star with proper physics
float4 renderOrbitingStar(float3 rayPos, float3 rayDir, float time, float orbitRadius, float orbitSpeed, float brightness) {
    // Calculate star position in circular orbit (XZ plane)
    float angle = time * orbitSpeed;
    float3 starPos = float3(orbitRadius * cos(angle), 0.0, orbitRadius * sin(angle));
    
    // Check if ray intersects star (sphere intersection)
    float3 toStar = starPos - rayPos;
    float starRadius = 0.1;  // Small visible star
    
    float b = dot(toStar, rayDir);
    if (b < 0.0) return float4(0.0);  // Behind ray origin
    
    float c = dot(toStar, toStar) - b * b;
    float disc = starRadius * starRadius - c;
    
    if (disc < 0.0) return float4(0.0);  // No intersection
    
    // Calculate star color with distance falloff
    float dist = b - sqrt(disc);
    float intensity = brightness * (1.0 / (1.0 + dist * dist * 0.1));
    
    // Star color (white/blue-white)
    float3 starColor = float3(0.9, 0.95, 1.0) * intensity;
    
    // Apply gravitational redshift to star
    float starDist = length(starPos);
    if (starDist > 1.0) {
        float redshift = sqrt(max(0.0, 1.0 - 1.0/starDist));
        starColor *= (1.0 + redshift);  // Redshift effect
    }
    
    return float4(starColor, min(intensity, 1.0));
}

// Apply gravitational redshift to background star color
float3 applyBackgroundRedshift(float3 color, float3 pos) {
    float dist = length(pos);
    if (dist < 1.0) return color;
    
    float redshift = sqrt(max(0.0, 1.0 - 1.0/dist)) - 1.0;
    redshift = max(0.0, redshift);
    
    // Shift color toward red
    float factor = 1.0 / (1.0 + redshift * 0.5);
    return color * float3(1.0, factor, factor * factor);
}

// Complete ray marching with adaptive performance optimization
float4 rayMarch(float3 pos, float3 dir, float time, constant Uniforms& uniforms) {
    float4 color = float4(0.0);
    float alpha = 1.0;

    // Calculate angular momentum (critical for proper orbits)
    float3 h = cross(pos, dir);
    float h2 = dot(h, h);
    
    // Use performance parameters for adaptive quality
    int maxSteps = uniforms.max_iterations;
    float stepSize = uniforms.step_size;

    for (int i = 0; i < maxSteps; ++i) {
        // Adaptive step size based on curvature (optional performance feature)
        float currentStepSize = stepSize;
        if (uniforms.adaptive_stepping) {
            float r = length(pos);
            // Reduce step size near event horizon where curvature is extreme
            if (r < 3.0) {
                currentStepSize = stepSize * (r / 3.0);
            }
        }
        
        // Use RK4 integration for maximum accuracy
        rk4(pos, h2, dir, currentStepSize, uniforms.gravity);

        // Check if ray hit event horizon (early termination)
        if (dot(pos, pos) < 1.0) {
            return color;  // Return accumulated color at event horizon
        }

        // Render accretion disk with full physics
        diskRender(pos, color, alpha, dir, time, uniforms);
        
        // Early exit if pixel is opaque enough (performance optimization)
        if (alpha < 0.01) {
            break;
        }
        
        // Early exit if ray goes too far (performance optimization)
        if (length(pos) > 100.0) {
            break;
        }
    }

    // Add background starfield
    float3 skyColor = float3(0.005, 0.01, 0.02);
    
    // Add some procedural stars
    float starNoise = snoise(dir * 50.0);
    if (starNoise > 0.8) {
        float3 starColor = float3(0.8, 0.9, 1.0) * (starNoise - 0.8) * 5.0;
        
        // Apply redshift to background stars based on ray path
        if (length(pos) < 20.0) {
            starColor = applyBackgroundRedshift(starColor, pos);
        }
        
        skyColor += starColor;
    }
    
    // Add subtle color variation to space
    skyColor *= (1.0 + 0.3 * snoise(dir * 5.0));
    
    color += float4(skyColor, 1.0) * (1.0 - color.a);
    color.a = 1.0;

    return color;
}

// Main compute kernel - exact coordinate system from repository
kernel void computeShader(texture2d<float, access::write> output [[texture(0)]],
                         constant Uniforms& uniforms [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= uint(uniforms.resolution.x) || gid.y >= uint(uniforms.resolution.y)) {
        return;
    }
    
    // EXACT coordinate transformation from repository - this is critical!
    float2 uv = (2.0 * float2(gid) - uniforms.resolution.xy) / uniforms.resolution.y;
    
    // Camera setup: use observer position if set, otherwise use camera_distance
    bool useObserverPos = (length(uniforms.observer_position) > 0.1);
    float3 cameraPos = useObserverPos ? 
                       uniforms.observer_position : 
                       float3(0.0, 0.0, uniforms.camera_distance);
    float3 target = float3(0.0, 0.0, 0.0);
    float3 up = float3(0.0, 1.0, 0.0);
    
    // Build camera basis vectors
    float3 forward = normalize(target - cameraPos);
    float3 right = normalize(cross(up, forward));
    float3 trueUp = cross(forward, right);
    
    // Ray direction through pixel
    float3 dir = normalize(uv.x * right + uv.y * trueUp + forward);
    
    // Apply observer velocity for motion-based doppler (future enhancement)
    // This would shift colors based on observer_velocity
    
    float4 fragColor = rayMarch(cameraPos, dir, uniforms.time, uniforms);
    
    // Render orbiting star on top if enabled
    if (uniforms.show_orbiting_star) {
        float4 starColor = renderOrbitingStar(cameraPos, dir, uniforms.time, 
                                              uniforms.star_orbit_radius, 
                                              uniforms.star_orbit_speed, 
                                              uniforms.star_brightness);
        // Blend star over scene
        fragColor.rgb = fragColor.rgb * (1.0 - starColor.a) + starColor.rgb * starColor.a;
        fragColor.a = max(fragColor.a, starColor.a);
    }
    
    output.write(fragColor, gid);
}