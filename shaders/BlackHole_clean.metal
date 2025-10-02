#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// Simple hash function for noise
float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Simple noise function
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Simple starfield
float3 starfield(float3 rd) {
    float3 stars = float3(0.0);
    
    // Convert to spherical coordinates
    float phi = atan2(rd.z, rd.x);
    float theta = acos(rd.y);
    float2 sphericalCoord = float2(phi * 4.0, theta * 8.0);
    
    // Multiple star layers
    for (int i = 0; i < 3; i++) {
        float scale = pow(2.0, float(i)) * 20.0;
        float2 p = sphericalCoord * scale;
        float starNoise = hash(floor(p));
        
        if (starNoise > 0.998) {
            float brightness = (starNoise - 0.998) / 0.002;
            stars += float3(1.0, 1.0, 1.0) * brightness * 0.5;
        }
    }
    
    return stars;
}

// Simple gravitational lensing
float3 gravitationalLensing(float3 pos, float3 rd, float rs) {
    float r = length(pos);
    if (r < rs * 3.0) {
        float3 rHat = normalize(pos);
        float deflection = rs / (r * r) * 0.5;
        float3 perpendicular = normalize(cross(cross(pos, rd), pos));
        return normalize(rd + perpendicular * deflection);
    }
    return rd;
}

// Accretion disk density
float diskDensity(float3 pos, constant Uniforms& uniforms) {
    float r = length(pos.xz);
    float y = abs(pos.y);
    
    // Basic disk shape
    if (r < uniforms.black_hole_size * 3.0 || r > uniforms.disk_radius) {
        return 0.0;
    }
    
    // Vertical falloff
    float verticalFalloff = exp(-y / uniforms.disk_thickness);
    
    // Radial density
    float radialDensity = exp(-r / uniforms.disk_radius) * (uniforms.disk_radius / r);
    
    // Simple turbulence
    float2 noiseCoord = float2(r + uniforms.time * 0.1, atan2(pos.z, pos.x) + uniforms.time * 0.05);
    float turbulence = noise(noiseCoord * 3.0) * 0.5 + 0.5;
    
    return verticalFalloff * radialDensity * turbulence;
}

// Temperature to color conversion
float3 temperatureToColor(float temp) {
    temp = clamp(temp, 0.0, 1.0);
    
    if (temp > 0.8) {
        return float3(1.5, 1.2, 0.8); // Hot white-orange
    } else if (temp > 0.6) {
        return float3(1.2, 0.8, 0.4); // Orange
    } else if (temp > 0.4) {
        return float3(1.0, 0.6, 0.2); // Red-orange
    } else if (temp > 0.2) {
        return float3(0.8, 0.3, 0.1); // Deep red
    } else {
        return float3(0.4, 0.1, 0.0); // Very dim red
    }
}

kernel void blackHoleRayMarching(texture2d<float, access::write> colorTexture [[texture(0)]],
                                constant Uniforms& uniforms [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    
    uint2 textureSize = uint2(colorTexture.get_width(), colorTexture.get_height());
    float2 uv = (float2(gid) / float2(textureSize)) * 2.0 - 1.0;
    uv.x *= float(textureSize.x) / float(textureSize.y);
    
    // Camera setup
    float3 cameraPos = float3(0.0, 0.0, uniforms.camera_distance);
    float3 rayDir = normalize(float3(uv.x, uv.y, -1.0));
    
    // Ray marching parameters
    float3 pos = cameraPos;
    float3 rd = rayDir;
    float t = 0.0;
    float3 color = float3(0.0);
    
    float schwarzschildRadius = uniforms.black_hole_size;
    
    // Ray marching loop
    for (int i = 0; i < 100; i++) {
        pos = cameraPos + t * rd;
        float distToCenter = length(pos);
        
        // Event horizon check
        if (distToCenter < schwarzschildRadius * 2.0) {
            color = float3(0.0); // Absorbed by black hole
            break;
        }
        
        // Apply gravitational lensing
        if (distToCenter < schwarzschildRadius * 10.0) {
            rd = gravitationalLensing(pos, rd, schwarzschildRadius);
        }
        
        // Check accretion disk
        float density = diskDensity(pos, uniforms);
        if (density > 0.01) {
            float temperature = density + length(pos.xz) / uniforms.disk_radius * 0.5;
            float3 diskColor = temperatureToColor(temperature) * density;
            color += diskColor * 0.1;
            
            // Reduce ray strength
            if (length(color) > 2.0) break;
        }
        
        // Step forward
        float stepSize = 0.1 + distToCenter * 0.02;
        t += stepSize;
        
        // Ray escape check
        if (distToCenter > uniforms.disk_radius * 3.0) {
            // Add stars
            color += starfield(rd) * 0.3;
            break;
        }
    }
    
    // Tone mapping and output
    color = color / (color + 1.0); // Simple tone mapping
    color = pow(color, float3(1.0/2.2)); // Gamma correction
    
    colorTexture.write(float4(color, 1.0), gid);
}