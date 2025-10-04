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
     * Performance: Adaptive based on quality preset (15-60+ FPS possible)
     */
    void draw();

private:
    GLFWwindow* _pWindow;           // GLFW window for rendering context
    void* _pDevice;                 // MTLDevice* - GPU device handle
    void* _pCommandQueue;           // MTLCommandQueue* - command submission queue
    void* _pPSO;                    // MTLComputePipelineState* - compiled shader pipeline
    void* _pMetalLayer;             // CAMetalLayer* - drawable presentation layer

    // Post-processing pipeline states
    void* _bloomBrightnessPSO;      // MTLComputePipelineState* - bloom brightness extraction
    void* _bloomDownsamplePSO;      // MTLComputePipelineState* - bloom downsample
    void* _bloomUpsamplePSO;        // MTLComputePipelineState* - bloom upsample
    void* _bloomCompositePSO;       // MTLComputePipelineState* - bloom composite
    void* _tonemappingPSO;          // MTLComputePipelineState* - ACES tone mapping
    
    // Post-processing textures
    void* _sceneTexture;            // MTLTexture* - main scene render target
    void* _brightnessTexture;       // MTLTexture* - bright pixels for bloom
    void* _bloomDownsample[8];      // MTLTexture* - bloom downsample pyramid
    void* _bloomUpsample[8];        // MTLTexture* - bloom upsample pyramid
    void* _bloomFinalTexture;       // MTLTexture* - final combined bloom
    void* _finalTexture;            // MTLTexture* - after tone mapping
    void* _diskColorMap;            // MTLTexture* - accretion disk color gradient
    
    int   _ppWidth;                 // Width of post-processing textures
    int   _ppHeight;                // Height of post-processing textures
    int   _allocatedBloomIterations;// Number of bloom mip levels allocated
    bool  _postProcessDirty;        // Post-processing resources need rebuild
    
    // Post-processing parameters
    float _bloomStrength;           // Bloom intensity
    float _bloomThreshold;          // Brightness threshold for bloom
    int _bloomIterations;           // Number of bloom mip levels
    float _tonemapGamma;            // Gamma correction value
    bool _tonemappingEnabled;       // Enable/disable tone mapping
    bool _bloomEnabled;             // Enable/disable bloom effect

    Uniforms _uniforms;             // Shared GPU/CPU uniform buffer (see ShaderTypes.h)
    
    // Performance tracking
    double _lastFrameTime;          // Time of last frame for FPS calculation
    float _currentFPS;              // Current frames per second
    float _frameTimeMs;             // Frame time in milliseconds
    
    // Recording state
    bool _isRecording;              // Currently recording video
    void* _videoWriter;             // AVAssetWriter* for video encoding
    void* _videoInput;              // AVAssetWriterInput* for frame data
    void* _pixelBufferAdaptor;      // AVAssetWriterInputPixelBufferAdaptor*
    int _recordedFrames;            // Number of frames captured
    
    // GUI state
    int _currentTab;                // Active GUI tab (0=Physics, 1=Visual, 2=Camera, 3=Recording)
    int _currentPreset;             // Selected quality preset
    int _currentVisualPreset;       // Selected visual preset for accretion disk
    
    // Helper methods
    void updatePerformanceMetrics();
    void applyQualityPreset(int preset);
    void applyVisualPreset(int preset);
    void startRecording(const char* filename);
    void stopRecording();
    void captureFrame();
    
    // Post-processing methods
    void initializePostProcessing();
    void createPostProcessingTextures(int width, int height);
    void applyBloomEffect(void* commandBuffer, void* inputTexture, void* outputTexture);
    void applyToneMapping(void* commandBuffer, void* inputTexture, void* outputTexture);
};
