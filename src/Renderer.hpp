/**
 * Renderer.hpp
 * 
 * Metal Rendering Engine for Black Hole GPU Ray Tracer
 * 
 * This class encapsulates the Metal graphics pipeline for real-time black hole
 * visualization using GPU-accelerated compute shaders. It manages:
 * 
 * - Metal device and command queue initialization
 * - Compute pipeline state setup for ray tracing shader
 * - CAMetalLayer integration with GLFW window
 * - ImGui integration for interactive parameter controls
 * - Per-frame uniform buffer updates
 * 
 * The renderer uses Metal compute shaders to perform parallel ray tracing
 * of geodesics around a Schwarzschild black hole, implementing scientifically
 * accurate gravitational lensing, accretion disk rendering, and relativistic
 * effects including gravitational redshift and Doppler shifting.
 * 
 * Architecture:
 * - C++ interface with Objective-C++ implementation (.mm file)
 * - Opaque pointer pattern for Metal types to maintain C++ compatibility
 * - GLFW provides cross-platform windowing and input handling
 * - ImGui provides immediate-mode GUI for real-time parameter adjustment
 */

#pragma once
#include "ShaderTypes.h"

// Forward declarations for Objective-C types
// Using opaque pointers to keep the header pure C++ compatible
#ifdef __OBJC__
@class CAMetalLayer;
@protocol MTLDevice;
@protocol MTLCommandQueue;
@protocol MTLComputePipelineState;
#else
typedef void CAMetalLayer;
typedef void MTLDevice;
typedef void MTLCommandQueue;
typedef void MTLComputePipelineState;
#endif

struct GLFWwindow;

class Renderer
{
public:
    /**
     * Constructor: Initializes Metal device, command queue, and compute pipeline
     * 
     * @param pWindow GLFW window handle for Metal layer attachment
     * 
     * Responsibilities:
     * - Creates Metal device and command queue
     * - Compiles compute shader from BlackHole.metal
     * - Sets up CAMetalLayer with appropriate pixel format
     * - Initializes ImGui with Metal backend
     * - Sets default physical parameters for black hole simulation
     */
    Renderer(GLFWwindow* pWindow);
    
    /**
     * Destructor: Cleans up Metal resources and ImGui context
     */
    ~Renderer();
    
    /**
     * Main render loop entry point
     * 
     * Called once per frame to:
     * - Update uniform buffer with current parameters
     * - Dispatch compute shader for ray tracing
     * - Render ImGui controls and overlays
     * - Present frame to screen
     * 
     * Performance: Typically 9-10 FPS at 1280x720 on integrated GPU
     */
    void draw();

private:
    GLFWwindow* _pWindow;           // GLFW window for rendering context
    void* _pDevice;                 // MTLDevice* - GPU device handle
    void* _pCommandQueue;           // MTLCommandQueue* - command submission queue
    void* _pPSO;                    // MTLComputePipelineState* - compiled shader pipeline
    void* _pMetalLayer;             // CAMetalLayer* - drawable presentation layer

    Uniforms _uniforms;             // Shared GPU/CPU uniform buffer (see ShaderTypes.h)
};
