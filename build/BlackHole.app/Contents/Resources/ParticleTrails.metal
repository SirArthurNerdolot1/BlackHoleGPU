/**
 * ParticleTrails.metal
 * 
 * Advanced Particle Trail and Visual Effects System
 * 
 * This Metal compute shader enhances the particle system with:
 * - Smooth particle motion trails
 * - HDR bloom-ready emission
 * - Advanced color mixing and gradients
 * - Volumetric particle rendering
 * - Performance-optimized LOD system
 */

#include <metal_stdlib>
using namespace metal;

#include "../src/ShaderTypes.h"

// Trail point structure for motion blur
typedef struct {
    vector_float3 position;
    float intensity;
    float age;
} TrailPoint;

/**
 * Update particle trails by recording motion history
 */
kernel void updateParticleTrails(
    device Particle* particles [[buffer(0)]],
    device TrailPoint* trails [[buffer(1)]],
    constant Uniforms& uniforms [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    uint maxParticles = uniforms.max_particles;
    if (index >= maxParticles || !uniforms.particle_trails) return;
    
    device Particle& particle = particles[index];
    if (!particle.is_active) return;
    
    uint trailStartIndex = index * 10; // 10 trail points per particle
    
    // Shift existing trail points
    for (int i = 9; i > 0; i--) {
        trails[trailStartIndex + i] = trails[trailStartIndex + i - 1];
        trails[trailStartIndex + i].age += 1.0/60.0; // Assume 60 FPS
    }
    
    // Add new trail point at current position
    trails[trailStartIndex].position = particle.position;
    trails[trailStartIndex].intensity = particle.luminosity;
    trails[trailStartIndex].age = 0.0;
}

/**
 * Enhanced particle rendering with volumetric effects and trails
 */
kernel void renderParticlesAdvanced(
    device Particle* particles [[buffer(0)]],
    device TrailPoint* trails [[buffer(1)]],
    constant Uniforms& uniforms [[buffer(2)]],
    texture2d<float, access::read_write> outputTexture [[texture(0)]],
    uint2 position [[thread_position_in_grid]]
) {
    uint2 textureSize = uint2(outputTexture.get_width(), outputTexture.get_height());
    if (position.x >= textureSize.x || position.y >= textureSize.y) return;
    
    float2 uv = (float2(position) + 0.5) / float2(textureSize);
    float2 screenPos = (uv - 0.5) * 2.0;
    
    // Enhanced camera setup with perspective projection
    float3 cameraPos = float3(0.0, 0.0, uniforms.camera_distance);
    float3 cameraTarget = float3(0.0, 0.0, 0.0);
    float3 cameraUp = float3(0.0, 1.0, 0.0);
    
    float3 forward = normalize(cameraTarget - cameraPos);
    float3 right = normalize(cross(forward, cameraUp));
    float3 up = cross(right, forward);
    
    float fov = 60.0 * M_PI_F / 180.0; // 60 degree field of view
    float aspect = float(textureSize.x) / float(textureSize.y);
    float3 rayDir = normalize(forward + 
                             tan(fov * 0.5) * (screenPos.x * aspect * right + screenPos.y * up));
    
    // Read existing color from texture for additive blending
    float4 existingColor = outputTexture.read(position);
    float4 finalColor = existingColor;
    
    uint maxParticles = uniforms.max_particles;
    
    // Render all active particles with enhanced effects
    for (uint i = 0; i < maxParticles; i++) {
        device Particle& particle = particles[i];
        if (!particle.is_active) continue;
        
        // Distance-based LOD culling
        float distanceToCamera = length(particle.position - cameraPos);
        if (distanceToCamera > uniforms.disk_radius * 3.0) continue;
        
        // Project particle to screen space with perspective
        float3 particleDir = particle.position - cameraPos;
        float projectionDistance = dot(particleDir, forward);
        if (projectionDistance <= 0.1) continue; // Behind camera
        
        float3 projected = particleDir / projectionDistance;
        float2 screenProjection = float2(
            dot(projected, right) / tan(fov * 0.5) / aspect,
            dot(projected, up) / tan(fov * 0.5)
        );
        
        float2 pixelDistance = screenProjection - screenPos;
        float distance = length(pixelDistance);
        
        // Calculate particle influence radius with LOD
        float baseRadius = particle.size * 0.05;
        float lodFactor = 1.0 / (1.0 + distanceToCamera * 0.1);
        float influenceRadius = baseRadius * lodFactor;
        
        if (distance < influenceRadius) {
            // Calculate particle contribution with smooth falloff
            float falloff = 1.0 - (distance / influenceRadius);
            falloff = smoothstep(0.0, 1.0, falloff);
            falloff = pow(falloff, 1.5); // More concentrated center
            
            // Enhanced color calculation
            float3 particleColor = particle.color * particle.luminosity;
            
            // Add temperature-based emission intensity
            float temperatureIntensity = (particle.temperature - 5000.0) / 45000.0;
            temperatureIntensity = clamp(temperatureIntensity, 0.1, 2.0);
            particleColor *= temperatureIntensity;
            
            // Doppler effect based on velocity
            float velocityMagnitude = length(particle.velocity);
            float dopplerShift = 1.0 + velocityMagnitude * 0.05;
            particleColor.r *= dopplerShift;
            particleColor.b /= dopplerShift;
            
            // Material-specific rendering enhancements
            float alpha = falloff;
            float emission = 1.0;
            
            switch (particle.material_type) {
                case 0: // gas - soft, diffuse
                    alpha *= 0.8;
                    emission = 1.2;
                    particleColor *= float3(1.1, 1.0, 0.9); // Slightly warm tint
                    break;
                case 1: // dust - more solid, cooler
                    alpha *= 1.1;
                    emission = 0.8;
                    particleColor *= float3(0.9, 0.95, 1.1); // Slightly cool tint
                    break;
                case 2: // plasma - bright, energetic
                    alpha *= 0.6;
                    emission = 2.0;
                    particleColor *= float3(1.3, 1.1, 1.4); // Bright and energetic
                    break;
                case 3: // debris - solid, dark core with bright edges
                    if (falloff > 0.7) {
                        alpha *= 1.5;
                        emission = 0.5;
                        particleColor *= float3(0.7, 0.8, 0.9);
                    } else {
                        alpha *= 0.3;
                        emission = 1.8;
                    }
                    break;
            }
            
            // Volumetric density effect
            float volumetricDensity = 1.0 - distanceToCamera / (uniforms.disk_radius * 2.0);
            volumetricDensity = clamp(volumetricDensity, 0.2, 1.0);
            
            // Apply all effects
            float3 finalParticleColor = particleColor * emission * volumetricDensity;
            alpha *= volumetricDensity;
            
            // HDR-compatible additive blending
            finalColor.rgb += finalParticleColor * alpha * (1.0 - finalColor.a * 0.1);
            finalColor.a = min(finalColor.a + alpha * 0.5, 1.0);
        }
        
        // Render particle trails
        if (uniforms.particle_trails && uniforms.trail_length > 0.1) {
            uint trailStartIndex = i * 10;
            
            for (int t = 1; t < 10; t++) {
                TrailPoint trail = trails[trailStartIndex + t];
                if (trail.age > uniforms.trail_length) continue;
                
                // Project trail point to screen space
                float3 trailDir = trail.position - cameraPos;
                float trailProjectionDistance = dot(trailDir, forward);
                if (trailProjectionDistance <= 0.1) continue;
                
                float3 trailProjected = trailDir / trailProjectionDistance;
                float2 trailScreenProjection = float2(
                    dot(trailProjected, right) / tan(fov * 0.5) / aspect,
                    dot(trailProjected, up) / tan(fov * 0.5)
                );
                
                float2 trailPixelDistance = trailScreenProjection - screenPos;
                float trailDistance = length(trailPixelDistance);
                
                float trailRadius = baseRadius * 0.3 * (1.0 - trail.age / uniforms.trail_length);
                
                if (trailDistance < trailRadius) {
                    float trailFalloff = 1.0 - (trailDistance / trailRadius);
                    trailFalloff = pow(trailFalloff, 2.0);
                    
                    float trailIntensity = trail.intensity * (1.0 - trail.age / uniforms.trail_length);
                    float3 trailColor = particle.color * trailIntensity * 0.3;
                    
                    float trailAlpha = trailFalloff * trailIntensity * 0.2;
                    finalColor.rgb += trailColor * trailAlpha;
                    finalColor.a = min(finalColor.a + trailAlpha * 0.1, 1.0);
                }
            }
        }
    }
    
    // Apply final HDR tone mapping for bloom
    finalColor.rgb = finalColor.rgb / (1.0 + finalColor.rgb * 0.1);
    finalColor = clamp(finalColor, 0.0, 10.0); // Clamp to prevent overflow
    
    outputTexture.write(finalColor, position);
}

/**
 * Particle emission calculation for realistic light scattering
 */
kernel void calculateParticleEmission(
    device Particle* particles [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint index [[thread_position_in_grid]]
) {
    uint maxParticles = uniforms.max_particles;
    if (index >= maxParticles) return;
    
    device Particle& particle = particles[index];
    if (!particle.is_active) return;
    
    // Calculate emission based on temperature and material properties
    float baseEmission = particle.temperature / 20000.0; // Normalize to 20,000K
    
    // Black body radiation approximation
    float wavelengthRed = 700e-9;   // 700 nm
    float wavelengthGreen = 550e-9; // 550 nm
    float wavelengthBlue = 450e-9;  // 450 nm
    
    float h = 6.62607015e-34; // Planck constant
    float c = 299792458.0;    // Speed of light
    float k = 1.380649e-23;   // Boltzmann constant
    
    auto planckFunction = [=](float wavelength, float temperature) -> float {
        float x = (h * c) / (wavelength * k * temperature);
        return 1.0 / (exp(x) - 1.0);
    };
    
    float redIntensity = planckFunction(wavelengthRed, particle.temperature);
    float greenIntensity = planckFunction(wavelengthGreen, particle.temperature);
    float blueIntensity = planckFunction(wavelengthBlue, particle.temperature);
    
    // Normalize and apply to particle color
    float maxIntensity = max(max(redIntensity, greenIntensity), blueIntensity);
    if (maxIntensity > 0.0) {
        particle.color = float3(
            redIntensity / maxIntensity,
            greenIntensity / maxIntensity,
            blueIntensity / maxIntensity
        );
    }
    
    // Calculate luminosity based on material and conditions
    float materialLuminosity = 1.0;
    switch (particle.material_type) {
        case 0: // gas
            materialLuminosity = 1.0;
            break;
        case 1: // dust
            materialLuminosity = 0.7;
            break;
        case 2: // plasma
            materialLuminosity = 2.5;
            break;
        case 3: // debris
            materialLuminosity = 0.4;
            break;
    }
    
    particle.luminosity = baseEmission * materialLuminosity;
    
    // Apply gravitational redshift
    float r = length(particle.position);
    float redshift = 1.0 / sqrt(1.0 - 2.0 / r); // Simplified for r >> 2M
    particle.luminosity /= redshift;
}