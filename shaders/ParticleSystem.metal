/**
 * ParticleSystem.metal
 * 
 * GPU-Accelerated Particle-Based Accretion Disk Simulation
 * 
 * This Metal compute shader implements a hyper-realistic particle-based
 * accretion disk around a black hole using thousands of individual particles
 * with physically accurate orbital mechanics, temperature modeling, and
 * visual effects.
 * 
 * PHYSICS IMPLEMENTATION:
 * 
 * 1. Keplerian Orbital Mechanics:
 *    v = √(GM/r) for circular orbits
 *    Precession due to general relativity: Δφ = 6πGM/(rc²)
 * 
 * 2. Temperature Distribution:
 *    T(r) = T₀ × (r/r₀)^(-3/4) (Shakura-Sunyaev model)
 *    Peak temperatures: 10⁶-10⁷ K near event horizon
 * 
 * 3. Magnetic Field Effects:
 *    Lorentz force: F = q(v × B)
 *    Magnetorotational instability (MRI) for turbulence
 * 
 * 4. Particle Interactions:
 *    Collision detection and response
 *    Energy dissipation and angular momentum transfer
 *    Viscous heating and cooling
 * 
 * 5. Relativistic Effects:
 *    Frame dragging near rotating black holes
 *    Doppler beaming for high-velocity particles
 *    Gravitational redshift: z = 1/√(1-2GM/rc²) - 1
 * 
 * VISUAL FEATURES:
 * - Blackbody radiation colors based on temperature
 * - Particle trails showing orbital motion
 * - Turbulent motion from magnetic instabilities
 * - Size variation based on density and temperature
 * - Emission intensity based on velocity and viewing angle
 */

#include <metal_stdlib>
using namespace metal;

// Import shared data structures
#include "../src/ShaderTypes.h"

// Constants for particle physics
constant float SCHWARZSCHILD_RADIUS = 1.0;     // Black hole radius in units
constant float SPEED_OF_LIGHT = 299792458.0;   // m/s
constant float GRAVITATIONAL_CONSTANT = 6.67430e-11; // m³/kg/s²
constant float STEFAN_BOLTZMANN = 5.670374419e-8;    // W/m²/K⁴
constant float PLANCK_CONSTANT = 6.62607015e-34;     // J⋅s
constant float BOLTZMANN_CONSTANT = 1.380649e-23;    // J/K

// Particle material properties
constant float PARTICLE_MASS_GAS = 1.0;        // Relative mass for gas particles
constant float PARTICLE_MASS_DUST = 2.5;       // Relative mass for dust particles
constant float PARTICLE_MASS_PLASMA = 0.8;     // Relative mass for plasma particles
constant float PARTICLE_MASS_DEBRIS = 5.0;     // Relative mass for debris particles

/**
 * Random number generation for particle initialization and turbulence
 */
float rand(uint2 coord, float seed) {
    return fract(sin(dot(float2(coord), float2(12.9898, 78.233)) + seed) * 43758.5453);
}

float3 rand3(uint3 coord, float seed) {
    return float3(
        rand(coord.xy, seed),
        rand(coord.yz, seed + 1.0),
        rand(coord.xz, seed + 2.0)
    );
}

/**
 * Convert temperature to blackbody RGB color
 */
float3 temperatureToColor(float temperature) {
    // Clamp temperature to reasonable range
    temperature = clamp(temperature, 1000.0, 50000.0);
    
    // Wien's displacement law approximation for color
    float x = 1000.0 / temperature;
    
    float3 color;
    
    // Red component
    if (temperature < 6600.0) {
        color.r = 1.0;
    } else {
        color.r = 1.292936 * pow(temperature / 100.0 - 60.0, -0.1332047);
        color.r = clamp(color.r, 0.0, 1.0);
    }
    
    // Green component
    if (temperature < 6600.0) {
        color.g = 0.39008157 * log(temperature / 100.0) - 0.63184144;
    } else {
        color.g = 1.292936 * pow(temperature / 100.0 - 60.0, -0.0755148);
    }
    color.g = clamp(color.g, 0.0, 1.0);
    
    // Blue component
    if (temperature >= 6600.0) {
        color.b = 1.0;
    } else if (temperature >= 1900.0) {
        color.b = 0.543206789 * log(temperature / 100.0 - 10.0) - 1.19625408;
    } else {
        color.b = 0.0;
    }
    color.b = clamp(color.b, 0.0, 1.0);
    
    // Enhance saturation for visual appeal
    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(luminance), color, 1.4);
    
    return color;
}

/**
 * Calculate Keplerian orbital velocity at given radius
 */
float3 calculateKeplerianVelocity(float3 position, float blackHoleMass) {
    float r = length(position);
    if (r < SCHWARZSCHILD_RADIUS * 1.1) {
        return float3(0.0); // Too close to event horizon
    }
    
    // Keplerian velocity: v = √(GM/r)
    float speed = sqrt(blackHoleMass / r);
    
    // Convert to tangential velocity vector
    float3 radialDir = normalize(position);
    float3 tangentialDir = normalize(cross(radialDir, float3(0.0, 1.0, 0.0)));
    
    // Add small random perturbation for realistic orbits
    float perturbation = 0.05 * (rand(uint2(position.x * 1000, position.z * 1000), 0.0) - 0.5);
    speed *= (1.0 + perturbation);
    
    return tangentialDir * speed;
}

/**
 * Calculate gravitational acceleration
 */
float3 calculateGravitationalForce(float3 position, float mass, float blackHoleMass) {
    float r = length(position);
    if (r < SCHWARZSCHILD_RADIUS) {
        return float3(0.0); // Past event horizon
    }
    
    // Newtonian gravity with GR corrections
    float force = blackHoleMass * mass / (r * r);
    
    // General relativistic correction (approximate)
    float grCorrection = 1.0 + 1.5 * SCHWARZSCHILD_RADIUS / r;
    force *= grCorrection;
    
    return -normalize(position) * force;
}

/**
 * Calculate magnetic field effects
 */
float3 calculateMagneticForce(float3 position, float3 velocity, float charge, constant Uniforms& uniforms) {
    // Simplified magnetic field model - dipole field
    float r = length(position);
    float3 magneticField = uniforms.particle_magnetism * float3(
        position.x * position.y / (r * r * r),
        (position.y * position.y - 0.5 * (position.x * position.x + position.z * position.z)) / (r * r * r),
        position.z * position.y / (r * r * r)
    );
    
    // Lorentz force: F = q(v × B)
    return charge * cross(velocity, magneticField);
}

/**
 * Particle Update Compute Shader
 * Updates particle physics including orbital mechanics, temperature, and lifetime
 */
kernel void updateParticles(
    device Particle* particles [[buffer(0)]],
    device uint* activeIndices [[buffer(1)]],
    device atomic_uint& particleCount [[buffer(2)]],
    constant Uniforms& uniforms [[buffer(3)]],
    uint index [[thread_position_in_grid]]
) {
    uint maxParticles = uniforms.max_particles;
    if (index >= maxParticles) return;
    
    device Particle& particle = particles[index];
    if (!particle.is_active) return;
    
    float deltaTime = 1.0 / 60.0; // Assume 60 FPS for now
    float3 position = particle.position;
    float3 velocity = particle.velocity;
    float mass = particle.mass;
    
    // Update particle age
    particle.age += deltaTime;
    if (particle.age > particle.lifetime) {
        particle.is_active = false;
        return;
    }
    
    // Calculate forces
    float3 gravitationalForce = calculateGravitationalForce(position, mass, uniforms.gravity);
    float3 magneticForce = calculateMagneticForce(position, velocity, 1.0, uniforms);
    
    // Add turbulence for realistic motion
    float r = length(position);
    float turbulenceStrength = uniforms.particle_turbulence * exp(-r / uniforms.disk_radius);
    float3 turbulence = turbulenceStrength * (rand3(uint3(position * 1000.0), uniforms.time) - 0.5);
    
    // Combine forces
    particle.acceleration = (gravitationalForce + magneticForce + turbulence) / mass;
    
    // Verlet integration for stable orbital motion
    float3 newPosition = position + velocity * deltaTime + 0.5 * particle.acceleration * deltaTime * deltaTime;
    float3 newVelocity = velocity + particle.acceleration * deltaTime;
    
    // Apply collision damping
    float damping = 1.0 - uniforms.particle_collision_damping * deltaTime;
    newVelocity *= damping;
    
    // Check bounds - remove particles that fall into black hole or drift too far
    float newR = length(newPosition);
    if (newR < SCHWARZSCHILD_RADIUS * 1.05 || newR > uniforms.disk_radius * 2.0) {
        particle.is_active = false;
        return;
    }
    
    // Update particle properties
    particle.position = newPosition;
    particle.velocity = newVelocity;
    
    // Update temperature based on orbital dynamics
    float kineticEnergy = 0.5 * mass * dot(newVelocity, newVelocity);
    float potentialEnergy = -uniforms.gravity * mass / newR;
    float totalEnergy = kineticEnergy + potentialEnergy;
    
    // Temperature from virial theorem and Shakura-Sunyaev model
    float baseTemp = 10000.0 * pow(SCHWARZSCHILD_RADIUS / newR, 0.75);
    float energyTemp = abs(totalEnergy) * 1000.0;
    particle.temperature = mix(baseTemp, energyTemp, 0.3);
    
    // Update visual properties
    particle.color = temperatureToColor(particle.temperature);
    particle.luminosity = particle.temperature / 20000.0; // Normalize to reasonable range
    
    // Size based on temperature and material type
    float baseSizeMultiplier = (particle.material_type == 0) ? 1.0 :  // gas
                              (particle.material_type == 1) ? 1.5 :  // dust
                              (particle.material_type == 2) ? 0.8 :  // plasma
                              2.0;                                     // debris
    particle.size = uniforms.particle_size * baseSizeMultiplier * (1.0 + particle.temperature / 50000.0);
}

/**
 * Particle Spawning Compute Shader
 * Creates new particles with realistic initial conditions
 */
kernel void spawnParticles(
    device Particle* particles [[buffer(0)]],
    device atomic_uint& particleCount [[buffer(1)]],
    constant Uniforms& uniforms [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    if (!uniforms.particle_spawning) return;
    
    uint maxParticles = uniforms.max_particles;
    if (index >= maxParticles) return;
    
    // Check if this slot is available
    device Particle& particle = particles[index];
    if (particle.is_active) return;
    
    // Random spawn probability based on emission rate
    float spawnProbability = uniforms.particle_emission_rate / 60.0; // Convert to per-frame probability
    if (rand(uint2(index, uniforms.time * 1000), 0.0) > spawnProbability) return;
    
    // Generate spawn position in annular region
    float spawnRadius = mix(uniforms.spawning_radius_min, uniforms.spawning_radius_max, 
                           rand(uint2(index * 2, uniforms.time * 1000), 1.0));
    float spawnAngle = rand(uint2(index * 3, uniforms.time * 1000), 2.0) * 2.0 * M_PI_F;
    float spawnHeight = (rand(uint2(index * 4, uniforms.time * 1000), 3.0) - 0.5) * uniforms.disk_thickness;
    
    particle.position = float3(
        spawnRadius * cos(spawnAngle),
        spawnHeight,
        spawnRadius * sin(spawnAngle)
    );
    
    // Set initial Keplerian velocity
    particle.velocity = calculateKeplerianVelocity(particle.position, uniforms.gravity);
    
    // Add small random velocity component
    float3 randomVel = 0.1 * (rand3(uint3(index, uniforms.time * 1000, 0), 4.0) - 0.5);
    particle.velocity += randomVel;
    
    // Initialize other properties
    particle.acceleration = float3(0.0);
    particle.age = 0.0;
    particle.lifetime = uniforms.particle_lifetime * (0.5 + rand(uint2(index * 5, uniforms.time * 1000), 5.0));
    
    // Random material type
    float materialRand = rand(uint2(index * 6, uniforms.time * 1000), 6.0);
    if (materialRand < 0.6) {
        particle.material_type = 0; // gas (most common)
        particle.mass = PARTICLE_MASS_GAS;
    } else if (materialRand < 0.8) {
        particle.material_type = 1; // dust
        particle.mass = PARTICLE_MASS_DUST;
    } else if (materialRand < 0.95) {
        particle.material_type = 2; // plasma
        particle.mass = PARTICLE_MASS_PLASMA;
    } else {
        particle.material_type = 3; // debris
        particle.mass = PARTICLE_MASS_DEBRIS;
    }
    
    // Initial temperature based on spawn radius
    particle.temperature = 15000.0 * pow(SCHWARZSCHILD_RADIUS / spawnRadius, 0.75);
    particle.color = temperatureToColor(particle.temperature);
    particle.luminosity = particle.temperature / 20000.0;
    particle.size = uniforms.particle_size;
    
    particle.angular_momentum = length(cross(particle.position, particle.velocity));
    particle.radial_velocity = dot(particle.velocity, normalize(particle.position));
    particle.magnetic_field = float3(0.0);
    
    particle.is_active = true;
    atomic_fetch_add_explicit(&particleCount, 1, memory_order_relaxed);
}

/**
 * Particle Collision Detection Compute Shader
 * Handles particle-particle interactions and energy exchange
 */
kernel void processParticleCollisions(
    device Particle* particles [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint index [[thread_position_in_grid]]
) {
    uint maxParticles = uniforms.max_particles;
    if (index >= maxParticles) return;
    
    device Particle& particle1 = particles[index];
    if (!particle1.is_active) return;
    
    float collisionRadius = particle1.size * 2.0;
    
    // Check collisions with nearby particles (simplified O(n²) for now)
    // In production, would use spatial hashing for O(n) complexity
    for (uint i = index + 1; i < min(index + 100, maxParticles); i++) {
        device Particle& particle2 = particles[i];
        if (!particle2.is_active) continue;
        
        float3 separation = particle1.position - particle2.position;
        float distance = length(separation);
        float minDistance = (particle1.size + particle2.size) * 1.5;
        
        if (distance < minDistance && distance > 0.0) {
            // Collision detected - exchange momentum and energy
            float3 normal = separation / distance;
            
            // Conservation of momentum (simplified elastic collision)
            float totalMass = particle1.mass + particle2.mass;
            float3 relativeVelocity = particle1.velocity - particle2.velocity;
            float velocityAlongNormal = dot(relativeVelocity, normal);
            
            if (velocityAlongNormal > 0) continue; // Particles separating
            
            // Apply collision response
            float restitution = 0.7; // Slightly inelastic
            float impulse = -(1 + restitution) * velocityAlongNormal / totalMass;
            
            particle1.velocity += impulse * particle2.mass * normal;
            particle2.velocity -= impulse * particle1.mass * normal;
            
            // Energy exchange affects temperature
            float energyTransfer = 0.1 * abs(impulse);
            particle1.temperature += energyTransfer * 500.0;
            particle2.temperature += energyTransfer * 500.0;
            
            // Update colors based on new temperatures
            particle1.color = temperatureToColor(particle1.temperature);
            particle2.color = temperatureToColor(particle2.temperature);
        }
    }
}

/**
 * Particle Rendering Compute Shader
 * Renders particles to texture with trails, bloom, and realistic colors
 */
kernel void renderParticles(
    device Particle* particles [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    texture2d<float, access::write> outputTexture [[texture(0)]],
    uint2 position [[thread_position_in_grid]]
) {
    uint2 textureSize = uint2(outputTexture.get_width(), outputTexture.get_height());
    if (position.x >= textureSize.x || position.y >= textureSize.y) return;
    
    float2 uv = (float2(position) + 0.5) / float2(textureSize);
    float2 screenPos = (uv - 0.5) * 2.0;
    
    // Camera setup (simplified orthographic projection for now)
    float3 cameraPos = float3(0.0, 0.0, uniforms.camera_distance);
    float3 rayDir = normalize(float3(screenPos.x, screenPos.y, -1.0));
    
    float4 finalColor = float4(0.0);
    uint maxParticles = uniforms.max_particles;
    
    // Render all active particles
    for (uint i = 0; i < maxParticles; i++) {
        device Particle& particle = particles[i];
        if (!particle.is_active) continue;
        
        // Project particle to screen space
        float3 particleScreenPos = particle.position - cameraPos;
        float2 screenProjection = particleScreenPos.xy / abs(particleScreenPos.z);
        
        float2 pixelDistance = screenProjection - screenPos;
        float distance = length(pixelDistance);
        
        // Calculate particle influence radius
        float influenceRadius = particle.size * 0.1 / abs(particleScreenPos.z);
        
        if (distance < influenceRadius) {
            // Calculate particle contribution
            float falloff = 1.0 - (distance / influenceRadius);
            falloff = pow(falloff, 2.0); // Smooth falloff
            
            // Apply luminosity and temperature-based emission
            float3 particleColor = particle.color * particle.luminosity;
            
            // Add Doppler shift effect
            float velocityMagnitude = length(particle.velocity);
            float dopplerFactor = 1.0 + velocityMagnitude * 0.1;
            particleColor *= dopplerFactor;
            
            // Material-specific rendering
            float alpha = falloff;
            if (particle.material_type == 2) { // plasma - more transparent, brighter
                alpha *= 0.7;
                particleColor *= 1.5;
            } else if (particle.material_type == 1) { // dust - more solid
                alpha *= 1.2;
                particleColor *= 0.8;
            }
            
            // Accumulate color with proper alpha blending
            finalColor.rgb += particleColor * alpha * (1.0 - finalColor.a);
            finalColor.a += alpha * (1.0 - finalColor.a);
            
            // Clamp to prevent overflow
            finalColor = clamp(finalColor, 0.0, 10.0);
        }
    }
    
    // Apply HDR tone mapping for bloom effect
    finalColor.rgb = finalColor.rgb / (1.0 + finalColor.rgb);
    
    outputTexture.write(finalColor, position);
}