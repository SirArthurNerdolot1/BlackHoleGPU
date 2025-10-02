/**
 * ShaderTypes.h
 * 
 * Shared Data Structures for CPU-GPU Communication
 * 
 * This header defines the Uniforms struct that is shared between the C++
 * host application and the Metal compute shader. It provides a consistent
 * memory layout for passing parameters from CPU to GPU each frame.
 * 
 * IMPORTANT: This struct must maintain identical memory layout on both
 * CPU and GPU. All types use SIMD-compatible primitives from <simd/simd.h>
 * to ensure proper alignment and ABI compatibility.
 * 
 * Parameter Categories:
 * 
 * 1. Display & Timing:
 *    - resolution: Screen dimensions for ray generation
 *    - time: Animation time for dynamic effects
 * 
 * 2. Physical Parameters:
 *    - gravity: Gravitational field strength (affects geodesic curvature)
 *    - disk_radius: Accretion disk size in Schwarzschild radii
 *    - disk_thickness: Vertical extent of accretion disk
 *    - black_hole_size: Schwarzschild radius (event horizon size)
 *    - camera_distance: Orbital radius of camera/observer
 * 
 * 3. Simulation Settings:
 *    - integration_method: 0=Verlet, 1=RK4 (Runge-Kutta 4th order)
 *    - orbit_type: Reserved for different orbital configurations
 * 
 * 4. Visual Effects Toggles:
 *    - disk_enabled: Show/hide accretion disk
 *    - doppler_enabled: Apply Doppler shift to moving matter
 *    - redshift_enabled: Apply gravitational redshift
 *    - beaming_enabled: Apply relativistic beaming
 *    - realistic_temp: Use physical blackbody temperatures
 * 
 * 5. Accretion Disk Physics:
 *    - accretion_temperature: Base temperature (1000K - 40000K)
 * 
 * 6. Observer Perspective:
 *    - observer_position: 3D position of virtual observer
 *    - observer_velocity: 3D velocity for Doppler calculations
 * 
 * 7. Orbiting Star:
 *    - show_orbiting_star: Toggle orbiting point light source
 *    - star_orbit_radius: Orbital distance from black hole
 *    - star_orbit_speed: Angular velocity in rad/s
 *    - star_brightness: Luminosity multiplier
 * 
 * 8. Background Stars:
 *    - background_redshift: Apply redshift to distant stars
 *    - background_doppler: Apply Doppler shift to distant stars
 */

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

typedef struct
{
    // Display parameters
    vector_float2 resolution;       // Screen width and height in pixels
    float time;                     // Current simulation time in seconds
    
    // Core physical parameters (interactive sliders)
    float gravity;                  // Gravitational field strength multiplier
    float disk_radius;              // Accretion disk outer radius (in Schwarzschild radii)
    float disk_thickness;           // Vertical thickness of accretion disk
    float black_hole_size;          // Schwarzschild radius (event horizon size)
    float camera_distance;          // Observer orbital radius
    
    // Scientific parameters
    int integration_method;         // Geodesic integration: 0=Verlet, 1=RK4
    int orbit_type;                 // Orbital configuration (reserved for future use)
    bool disk_enabled;              // Toggle accretion disk rendering
    bool doppler_enabled;           // Toggle Doppler shift effects
    bool redshift_enabled;          // Toggle gravitational redshift
    bool beaming_enabled;           // Toggle relativistic beaming
    bool realistic_temp;            // Use physically accurate blackbody temperatures
    float accretion_temperature;    // Disk base temperature in Kelvin
    
    // Observer parameters for perspective rendering
    vector_float3 observer_position;  // 3D position of observer
    vector_float3 observer_velocity;  // 3D velocity for relativistic effects
    
    // Orbiting star parameters
    bool show_orbiting_star;        // Enable orbiting point light source
    float star_orbit_radius;        // Orbital radius of star
    float star_orbit_speed;         // Angular velocity (rad/s)
    float star_brightness;          // Star luminosity multiplier
    
    // Background star effects
    bool background_redshift;       // Apply gravitational redshift to background
    bool background_doppler;        // Apply Doppler shift to background
} Uniforms;

#endif
