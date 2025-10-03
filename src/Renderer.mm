/**
 * Renderer.mm
 * 
 * Metal Rendering Engine Implementation
 * 
 * This Objective-C++ implementation provides the bridge between C++ application
 * logic and Apple's Metal graphics API. It handles:
 * 
 * - Metal device and command queue initialization
 * - Compute shader compilation from .metal source files
 * - CAMetalLayer setup for GLFW window integration
 * - ImGui initialization for interactive UI controls
 * - Per-frame uniform buffer updates and compute dispatch
 * 
 * The implementation uses ARC (Automatic Reference Counting) for memory
 * management of Objective-C objects, while maintaining C++ RAII semantics
 * for the Renderer class itself.
 */

#include "Renderer.hpp"
#include <iostream>
#include <stdexcept>
#include <chrono>
#include <algorithm>

// Platform-specific headers for Metal and GLFW integration
#define GLFW_INCLUDE_NONE
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <AVFoundation/AVFoundation.h>

#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_metal.h"

Renderer::Renderer(GLFWwindow* pWindow) : _pWindow(pWindow),
    _lastFrameTime(0.0), _currentFPS(0.0f), _frameTimeMs(0.0f),
    _isRecording(false), _videoWriter(nullptr), _videoInput(nullptr),
    _pixelBufferAdaptor(nullptr), _recordedFrames(0),
    _currentTab(0), _currentPreset(2), _currentVisualPreset(0),
    _bloomStrength(0.08f), _bloomThreshold(1.2f), _bloomIterations(5),
    _tonemapGamma(2.2f), _tonemappingEnabled(true), _bloomEnabled(true),
    _ppWidth(0), _ppHeight(0), _allocatedBloomIterations(0), _postProcessDirty(true)
{
    // Initialize default parameters inspired by Gargantua from Interstellar
    _uniforms.time = 0.0f;
    _uniforms.gravity = 2.5f;
    _uniforms.disk_radius = 5.0f;
    _uniforms.disk_thickness = 0.2f;
    _uniforms.black_hole_size = 0.12f;
    _uniforms.camera_distance = 8.0f;
    
    // Observer parameters
    _uniforms.observer_position = {0.0f, 0.0f, 8.0f};
    _uniforms.observer_velocity = {0.0f, 0.0f, 0.0f};
    
    // Orbiting star parameters
    _uniforms.show_orbiting_star = true;
    _uniforms.star_orbit_radius = 6.0f;
    _uniforms.star_orbit_speed = 0.5f;
    _uniforms.star_brightness = 1.0f;
    
    // Relativistic effects
    _uniforms.background_redshift = true;
    _uniforms.background_doppler = true;
    
    // Performance parameters - Default to High quality
    _uniforms.quality_preset = 2;  // High
    _uniforms.max_iterations = 256;
    _uniforms.step_size = 0.1f;
    _uniforms.adaptive_stepping = true;

    // Rossning-inspired accretion disk defaults
    _uniforms.disk_density_vertical = 2.0f;
    _uniforms.disk_density_horizontal = 4.0f;
    _uniforms.disk_density_gain = 16000.0f;
    _uniforms.disk_density_clamp = 12.0f;
    _uniforms.disk_noise_scale = 0.8f;
    _uniforms.disk_noise_speed = 0.5f;
    _uniforms.disk_noise_octaves = 5;
    _uniforms.disk_emission_strength = 0.25f;
    _uniforms.disk_alpha_falloff = 0.55f;
    _uniforms.disk_inner_multiplier = 25.0f;
    _uniforms.disk_inner_softness = 1.1f;
    _uniforms.disk_color_mix = 0.65f;

    applyVisualPreset(_currentVisualPreset);

    // Create Metal device (typically the integrated or discrete GPU)
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        std::cerr << "Failed to create Metal device" << std::endl;
        throw std::runtime_error("Metal device creation failed");
    }
    _pDevice = (__bridge void*)device;
    
    // Create command queue for GPU work submission
    id<MTLCommandQueue> commandQueue = [device newCommandQueue];
    if (!commandQueue) {
        std::cerr << "Failed to create Metal command queue" << std::endl;
        throw std::runtime_error("Metal command queue creation failed");
    }
    _pCommandQueue = (__bridge void*)commandQueue;

    // Create Metal layer for rendering output
    CAMetalLayer* metalLayer = [CAMetalLayer layer];
    metalLayer.device = device;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.framebufferOnly = YES;  // Optimize for display-only usage
    _pMetalLayer = (__bridge void*)metalLayer;
    
    // Attach Metal layer to GLFW window's content view
    NSWindow* pNSWindow = glfwGetCocoaWindow(pWindow);
    NSView* pView = [pNSWindow contentView];
    [pView setWantsLayer:YES];
    [pView setLayer:(__bridge CAMetalLayer*)_pMetalLayer];

    // Initialize ImGui for interactive controls
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::StyleColorsDark();
    ImGui_ImplGlfw_InitForOpenGL(pWindow, true);
    ImGui_ImplMetal_Init(device);

    // --- Shader Compilation ---
    NSError* pError = nil;
    id<MTLLibrary> pLibrary = [device newDefaultLibrary];
    if (!pLibrary) {
        std::cerr << "Failed to load default Metal library" << std::endl;
        throw std::runtime_error("Metal library creation failed");
    }

    id<MTLFunction> pKernelFunction = [pLibrary newFunctionWithName:@"computeShader"];
    if (!pKernelFunction) {
        std::cerr << "Failed to find computeShader function in Metal library" << std::endl;
        throw std::runtime_error("Metal kernel function not found");
    }
    
    id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:pKernelFunction error:&pError];
    if (!pso) {
        if (pError) {
            std::cerr << "Failed to create compute pipeline state: " << pError.localizedDescription.UTF8String << std::endl;
        }
        throw std::runtime_error("Metal pipeline state creation failed");
    }
    _pPSO = (__bridge void*)pso;
    
    // Initialize post-processing pipelines
    initializePostProcessing();
}

void Renderer::initializePostProcessing()
{
    @autoreleasepool {
        id<MTLDevice> device = (__bridge id<MTLDevice>)_pDevice;
        NSError* error = nil;
        id<MTLLibrary> library = [device newDefaultLibrary];
        
        // Bloom brightness extraction pipeline
        id<MTLFunction> bloomBrightness = [library newFunctionWithName:@"bloom_brightness_pass"];
        if (bloomBrightness) {
            id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:bloomBrightness error:&error];
            if (pso) {
                _bloomBrightnessPSO = (__bridge_retained void*)pso;
                std::cout << "Bloom brightness pipeline created successfully" << std::endl;
            } else {
                std::cerr << "Failed to create bloom brightness pipeline: " << (error ? error.localizedDescription.UTF8String : "unknown error") << std::endl;
            }
        }
        
        // Bloom downsample pipeline
        id<MTLFunction> bloomDownsample = [library newFunctionWithName:@"bloom_downsample"];
        if (bloomDownsample) {
            id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:bloomDownsample error:&error];
            if (pso) {
                _bloomDownsamplePSO = (__bridge_retained void*)pso;
                std::cout << "Bloom downsample pipeline created successfully" << std::endl;
            } else {
                std::cerr << "Failed to create bloom downsample pipeline: " << (error ? error.localizedDescription.UTF8String : "unknown error") << std::endl;
            }
        }
        
        // Bloom upsample pipeline  
        id<MTLFunction> bloomUpsample = [library newFunctionWithName:@"bloom_upsample"];
        if (bloomUpsample) {
            id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:bloomUpsample error:&error];
            if (pso) {
                _bloomUpsamplePSO = (__bridge_retained void*)pso;
                std::cout << "Bloom upsample pipeline created successfully" << std::endl;
            } else {
                std::cerr << "Failed to create bloom upsample pipeline: " << (error ? error.localizedDescription.UTF8String : "unknown error") << std::endl;
            }
        }
        
        // Bloom composite pipeline
        id<MTLFunction> bloomComposite = [library newFunctionWithName:@"bloom_composite"];
        if (bloomComposite) {
            id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:bloomComposite error:&error];
            if (pso) {
                _bloomCompositePSO = (__bridge_retained void*)pso;
                std::cout << "Bloom composite pipeline created successfully" << std::endl;
            } else {
                std::cerr << "Failed to create bloom composite pipeline: " << (error ? error.localizedDescription.UTF8String : "unknown error") << std::endl;
            }
        }
        
        // Tone mapping pipeline
        id<MTLFunction> tonemapping = [library newFunctionWithName:@"tonemapping_kernel"];
        if (tonemapping) {
            id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:tonemapping error:&error];
            if (pso) {
                _tonemappingPSO = (__bridge_retained void*)pso;
                std::cout << "Tone mapping pipeline created successfully" << std::endl;
            } else {
                std::cerr << "Failed to create tone mapping pipeline: " << (error ? error.localizedDescription.UTF8String : "unknown error") << std::endl;
            }
        }
        
        // Initialize texture pointers to null
        _sceneTexture = nullptr;
        _brightnessTexture = nullptr;
        _bloomFinalTexture = nullptr;
        _finalTexture = nullptr;
        for (int i = 0; i < 8; i++) {
            _bloomDownsample[i] = nullptr;
            _bloomUpsample[i] = nullptr;
        }
        _ppWidth = 0;
        _ppHeight = 0;
        _allocatedBloomIterations = 0;
        _postProcessDirty = true;
    }
}

void Renderer::createPostProcessingTextures(int width, int height)
{
    @autoreleasepool {
        id<MTLDevice> device = (__bridge id<MTLDevice>)_pDevice;

        auto releaseTexture = [](void*& slot) {
            if (slot) {
                id<MTLTexture> oldTex = (__bridge_transfer id<MTLTexture>)slot;
                oldTex = nil;
                slot = nullptr;
            }
        };

        // Release existing textures before reallocating
        releaseTexture(_sceneTexture);
        releaseTexture(_brightnessTexture);
        releaseTexture(_bloomFinalTexture);
        releaseTexture(_finalTexture);
        for (int i = 0; i < 8; ++i) {
            releaseTexture(_bloomDownsample[i]);
            releaseTexture(_bloomUpsample[i]);
        }
        
        // Create scene texture (HDR format for bloom)
        MTLTextureDescriptor* sceneDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                             width:width
                                                                                            height:height
                                                                                         mipmapped:NO];
        sceneDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        id<MTLTexture> sceneTexture = [device newTextureWithDescriptor:sceneDesc];
        _sceneTexture = (__bridge_retained void*)sceneTexture;
        
        // Create brightness texture
        id<MTLTexture> brightnessTexture = [device newTextureWithDescriptor:sceneDesc];
        _brightnessTexture = (__bridge_retained void*)brightnessTexture;
        
        // Create bloom final texture
        id<MTLTexture> bloomFinalTexture = [device newTextureWithDescriptor:sceneDesc];
        _bloomFinalTexture = (__bridge_retained void*)bloomFinalTexture;
        
        // Create bloom pyramid textures
        int requestedLevels = std::max(1, std::min(_bloomIterations, 8));
        int actualLevels = 0;
        for (int i = 0; i < requestedLevels; i++) {
            int mipWidth = width >> (i + 1);
            int mipHeight = height >> (i + 1);
            if (mipWidth < 2 || mipHeight < 2) {
                break;
            }

            MTLTextureDescriptor* mipDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                               width:mipWidth
                                                                                              height:mipHeight
                                                                                           mipmapped:NO];
            mipDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

            id<MTLTexture> downsampleTexture = [device newTextureWithDescriptor:mipDesc];
            _bloomDownsample[i] = (__bridge_retained void*)downsampleTexture;

                MTLTextureDescriptor* upDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                                                             width:width >> i
                                                                                                                            height:height >> i
                                                                                                                        mipmapped:NO];
            upDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
            id<MTLTexture> upsampleTexture = [device newTextureWithDescriptor:upDesc];
            _bloomUpsample[i] = (__bridge_retained void*)upsampleTexture;
            actualLevels++;
        }

        // Clear unused slots when resolution cannot support requested levels
        for (int i = actualLevels; i < 8; ++i) {
            _bloomDownsample[i] = nullptr;
            _bloomUpsample[i] = nullptr;
        }
        
        // Create final tone-mapped texture (LDR format for display)
        MTLTextureDescriptor* finalDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                             width:width
                                                                                            height:height
                                                                                         mipmapped:NO];
        finalDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        id<MTLTexture> finalTexture = [device newTextureWithDescriptor:finalDesc];
        _finalTexture = (__bridge_retained void*)finalTexture;

        _allocatedBloomIterations = actualLevels;
        _ppWidth = width;
        _ppHeight = height;
    }
}

Renderer::~Renderer()
{
    // Stop recording if active
    if (_isRecording) {
        stopRecording();
    }
    
    auto releaseObj = [](void*& slot) {
        if (slot) {
            id obj = (__bridge_transfer id)slot;
            obj = nil;
            slot = nullptr;
        }
    };

    releaseObj(_sceneTexture);
    releaseObj(_brightnessTexture);
    releaseObj(_bloomFinalTexture);
    releaseObj(_finalTexture);
    for (int i = 0; i < 8; ++i) {
        releaseObj(_bloomDownsample[i]);
        releaseObj(_bloomUpsample[i]);
    }
    releaseObj(_bloomBrightnessPSO);
    releaseObj(_bloomDownsamplePSO);
    releaseObj(_bloomUpsamplePSO);
    releaseObj(_bloomCompositePSO);
    releaseObj(_tonemappingPSO);

    // Clean up ImGui resources first
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    // Release Metal resources
    _pPSO = nullptr;
    _pCommandQueue = nullptr;
    _pMetalLayer = nullptr;
    _pDevice = nullptr;
}

void Renderer::updatePerformanceMetrics()
{
    auto currentTime = std::chrono::high_resolution_clock::now();
    double time = std::chrono::duration<double>(currentTime.time_since_epoch()).count();
    
    if (_lastFrameTime > 0.0) {
        double frameDelta = time - _lastFrameTime;
        _currentFPS = 1.0f / frameDelta;
        _frameTimeMs = frameDelta * 1000.0f;
    }
    
    _lastFrameTime = time;
}

void Renderer::applyQualityPreset(int preset)
{
    _uniforms.quality_preset = preset;
    
    switch (preset) {
        case 0: // Low - Maximum performance
            _uniforms.max_iterations = 128;
            _uniforms.step_size = 0.15f;
            _uniforms.adaptive_stepping = false;
            break;
        case 1: // Medium - Balanced
            _uniforms.max_iterations = 192;
            _uniforms.step_size = 0.12f;
            _uniforms.adaptive_stepping = true;
            break;
        case 2: // High - Good quality
            _uniforms.max_iterations = 256;
            _uniforms.step_size = 0.1f;
            _uniforms.adaptive_stepping = true;
            break;
        case 3: // Ultra - Maximum quality
            _uniforms.max_iterations = 512;
            _uniforms.step_size = 0.08f;
            _uniforms.adaptive_stepping = true;
            break;
    }
}

void Renderer::applyVisualPreset(int preset)
{
    _currentVisualPreset = preset;

    switch (preset) {
        case 1: // Rossning Particle Storm
            _uniforms.disk_thickness = 0.58f;
            _uniforms.disk_density_vertical = 1.35f;
            _uniforms.disk_density_horizontal = 3.0f;
            _uniforms.disk_density_gain = 12800.0f;
            _uniforms.disk_density_clamp = 9.0f;
            _uniforms.disk_noise_scale = 1.1f;
            _uniforms.disk_noise_speed = 1.25f;
            _uniforms.disk_noise_octaves = 6;
            _uniforms.disk_emission_strength = 0.28f;
            _uniforms.disk_alpha_falloff = 0.48f;
            _uniforms.disk_inner_multiplier = 24.0f;
            _uniforms.disk_inner_softness = 1.08f;
            _uniforms.disk_color_mix = 0.55f;
            _bloomStrength = 0.17f;
            _bloomThreshold = 0.95f;
            _bloomIterations = 6;
            _tonemapGamma = 2.3f;
            _bloomEnabled = true;
            _tonemappingEnabled = true;
            break;

        case 2: // Rossning Minimal Bloom
            _uniforms.disk_thickness = 0.5f;
            _uniforms.disk_density_vertical = 2.4f;
            _uniforms.disk_density_horizontal = 4.6f;
            _uniforms.disk_density_gain = 9200.0f;
            _uniforms.disk_density_clamp = 8.0f;
            _uniforms.disk_noise_scale = 0.68f;
            _uniforms.disk_noise_speed = 0.7f;
            _uniforms.disk_noise_octaves = 4;
            _uniforms.disk_emission_strength = 0.18f;
            _uniforms.disk_alpha_falloff = 0.58f;
            _uniforms.disk_inner_multiplier = 26.0f;
            _uniforms.disk_inner_softness = 1.15f;
            _uniforms.disk_color_mix = 0.7f;
            _bloomStrength = 0.07f;
            _bloomThreshold = 1.25f;
            _bloomIterations = 5;
            _tonemapGamma = 2.2f;
            _bloomEnabled = true;
            _tonemappingEnabled = true;
            break;

        default: // Rossning Default
            _uniforms.disk_thickness = 0.68f;
            _uniforms.disk_density_vertical = 2.0f;
            _uniforms.disk_density_horizontal = 4.0f;
            _uniforms.disk_density_gain = 13500.0f;
            _uniforms.disk_density_clamp = 10.2f;
            _uniforms.disk_noise_scale = 0.88f;
            _uniforms.disk_noise_speed = 0.95f;
            _uniforms.disk_noise_octaves = 5;
            _uniforms.disk_emission_strength = 0.2f;
            _uniforms.disk_alpha_falloff = 0.55f;
            _uniforms.disk_inner_multiplier = 25.0f;
            _uniforms.disk_inner_softness = 1.1f;
            _uniforms.disk_color_mix = 0.64f;
            _bloomStrength = 0.12f;
            _bloomThreshold = 0.98f;
            _bloomIterations = 7;
            _tonemapGamma = 2.35f;
            _bloomEnabled = true;
            _tonemappingEnabled = true;
            break;
    }

    _uniforms.disk_noise_octaves = std::clamp(_uniforms.disk_noise_octaves, 1, 8);
    _bloomIterations = std::clamp(_bloomIterations, 1, 8);
    _postProcessDirty = true;
}

void Renderer::startRecording(const char* filename)
{
    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:filename];
        NSURL* url = [NSURL fileURLWithPath:path];
        
        // Remove existing file
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        
        NSError* error = nil;
        AVAssetWriter* writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
        if (error || !writer) {
            std::cerr << "Failed to create video writer" << std::endl;
            return;
        }
        
        int width, height;
        glfwGetFramebufferSize(_pWindow, &width, &height);
        
        NSDictionary* videoSettings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(width),
            AVVideoHeightKey: @(height),
            AVVideoCompressionPropertiesKey: @{
                AVVideoAverageBitRateKey: @(width * height * 8),
                AVVideoMaxKeyFrameIntervalKey: @(30)
            }
        };
        
        AVAssetWriterInput* input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
        input.expectsMediaDataInRealTime = YES;
        
        NSDictionary* bufferAttributes = @{
            (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (NSString*)kCVPixelBufferWidthKey: @(width),
            (NSString*)kCVPixelBufferHeightKey: @(height),
            (NSString*)kCVPixelBufferMetalCompatibilityKey: @YES
        };
        
        AVAssetWriterInputPixelBufferAdaptor* adaptor = [AVAssetWriterInputPixelBufferAdaptor
            assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
            sourcePixelBufferAttributes:bufferAttributes];
        
        [writer addInput:input];
        [writer startWriting];
        [writer startSessionAtSourceTime:kCMTimeZero];
        
        _videoWriter = (__bridge_retained void*)writer;
        _videoInput = (__bridge_retained void*)input;
        _pixelBufferAdaptor = (__bridge_retained void*)adaptor;
        _isRecording = true;
        _recordedFrames = 0;
        
        std::cout << "Started recording to: " << filename << std::endl;
    }
}

void Renderer::stopRecording()
{
    if (!_isRecording) return;
    
    @autoreleasepool {
        AVAssetWriter* writer = (__bridge_transfer AVAssetWriter*)_videoWriter;
        AVAssetWriterInput* input = (__bridge_transfer AVAssetWriterInput*)_videoInput;
        _pixelBufferAdaptor = nullptr;
        
        [input markAsFinished];
        [writer finishWritingWithCompletionHandler:^{
            std::cout << "Recording finished. Frames captured: " << _recordedFrames << std::endl;
        }];
        
        _isRecording = false;
        _videoWriter = nullptr;
        _videoInput = nullptr;
        _recordedFrames = 0;
    }
}

void Renderer::captureFrame()
{
    if (!_isRecording) return;
    
    @autoreleasepool {
        // Note: Full video recording requires Metal texture->CVPixelBuffer conversion
        // which is complex and requires additional synchronization.
        // For now, increment frame counter to show recording is active.
        // A complete implementation would:
        // 1. Create CVPixelBuffer from Metal texture
        // 2. Use AVAssetWriterInputPixelBufferAdaptor to append pixel buffer
        // 3. Handle timing with CMTime based on frame rate
        
        _recordedFrames++;
        
        // TODO: Implement actual frame capture:
        // - Read MTLTexture data
        // - Convert to CVPixelBuffer
        // - Append to video using AVAssetWriterInputPixelBufferAdaptor
    }
}

void Renderer::draw()
{
    updatePerformanceMetrics();
    
    @autoreleasepool {
        CAMetalLayer* metalLayer = (__bridge CAMetalLayer*)_pMetalLayer;
        id<CAMetalDrawable> pDrawable = [metalLayer nextDrawable];
        if (!pDrawable) {
            return;
        }

        id<MTLTexture> pDrawableTexture = pDrawable.texture;
        
        // Sync layer size with window size and (re)create post-processing textures
        int width, height;
        glfwGetFramebufferSize(_pWindow, &width, &height);
        if (width != metalLayer.drawableSize.width || height != metalLayer.drawableSize.height) {
            metalLayer.drawableSize = CGSizeMake(width, height);
        }
        // Lazily (re)allocate post-process textures when missing, size changed, or settings updated
        bool needsPPResize = _postProcessDirty;
        if (!needsPPResize) {
            if (_ppWidth != (int)pDrawableTexture.width || _ppHeight != (int)pDrawableTexture.height) {
                needsPPResize = true;
            }
        }
        if (needsPPResize) {
            createPostProcessingTextures((int)pDrawableTexture.width, (int)pDrawableTexture.height);
            _postProcessDirty = false;
        }
        
        id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)_pCommandQueue;
        id<MTLCommandBuffer> pCmd = [commandQueue commandBuffer];
        if (!pCmd) {
            std::cerr << "Failed to create command buffer" << std::endl;
            return;
        }

        // 1. Black Hole Compute Pass -> render into HDR scene texture
        {
            id<MTLComputePipelineState> pso = (__bridge id<MTLComputePipelineState>)_pPSO;
            id<MTLTexture> sceneTex = (__bridge id<MTLTexture>)_sceneTexture;
            id<MTLComputeCommandEncoder> pEnc = [pCmd computeCommandEncoder];
            [pEnc setComputePipelineState:pso];
            [pEnc setTexture:sceneTex atIndex:0];

            _uniforms.time += 0.01f;
            _uniforms.resolution = {(float)sceneTex.width, (float)sceneTex.height};
            [pEnc setBytes:&_uniforms length:sizeof(Uniforms) atIndex:0];
            
            MTLSize gridSize = MTLSizeMake(sceneTex.width, sceneTex.height, 1);
            NSUInteger threadGroupWidth = pso.threadExecutionWidth;
            NSUInteger threadGroupHeight = pso.maxTotalThreadsPerThreadgroup / threadGroupWidth;
            MTLSize threadgroupSize = MTLSizeMake(threadGroupWidth, threadGroupHeight, 1);

            [pEnc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
            [pEnc endEncoding];
        }

        // 2. Bloom (optional) -> writes to _bloomFinalTexture
        {
            id<MTLTexture> sceneTex = (__bridge id<MTLTexture>)_sceneTexture;
            id<MTLTexture> bloomOut = (__bridge id<MTLTexture>)_bloomFinalTexture;
            if (_bloomEnabled && _bloomBrightnessPSO && _bloomDownsamplePSO && _bloomUpsamplePSO) {
                applyBloomEffect((__bridge void*)pCmd, (__bridge void*)sceneTex, (__bridge void*)bloomOut);
            } else {
                // If bloom disabled, just copy scene into bloomOut via simple compute copy using composite with strength 0
                id<MTLComputePipelineState> pso = (__bridge id<MTLComputePipelineState>)_bloomCompositePSO;
                if (pso) {
                    id<MTLComputeCommandEncoder> enc = [pCmd computeCommandEncoder];
                    [enc setComputePipelineState:pso];
                    [enc setTexture:sceneTex atIndex:0];
                    [enc setTexture:sceneTex atIndex:1];
                    [enc setTexture:(__bridge id<MTLTexture>)_bloomFinalTexture atIndex:2];
                    float strength = 0.0f;
                    float tone = 1.0f;
                    [enc setBytes:&strength length:sizeof(float) atIndex:0];
                    [enc setBytes:&tone length:sizeof(float) atIndex:1];
                    MTLSize grid = MTLSizeMake(sceneTex.width, sceneTex.height, 1);
                    NSUInteger tw = pso.threadExecutionWidth;
                    NSUInteger th = pso.maxTotalThreadsPerThreadgroup / tw;
                    MTLSize tgs = MTLSizeMake(tw, th, 1);
                    [enc dispatchThreads:grid threadsPerThreadgroup:tgs];
                    [enc endEncoding];
                }
            }
        }
    
        // 3. Tone mapping (optional) -> write into final texture when available
        bool usedIntermediate = false;
        {
            id<MTLTexture> inputTex = (__bridge id<MTLTexture>)_bloomFinalTexture;
            id<MTLTexture> finalTex = (__bridge id<MTLTexture>)_finalTexture;
            if (finalTex) {
                applyToneMapping((__bridge void*)pCmd, (__bridge void*)inputTex, (__bridge void*)finalTex);
                usedIntermediate = true;
            } else {
                applyToneMapping((__bridge void*)pCmd, (__bridge void*)inputTex, (__bridge void*)pDrawableTexture);
            }
        }

        // 4. Copy tone-mapped result into the drawable when using intermediate texture
        if (usedIntermediate) {
            id<MTLTexture> finalTex = (__bridge id<MTLTexture>)_finalTexture;
            if (finalTex) {
                id<MTLBlitCommandEncoder> blit = [pCmd blitCommandEncoder];
                [blit copyFromTexture:finalTex
                          sourceSlice:0
                          sourceLevel:0
                         sourceOrigin:MTLOriginMake(0, 0, 0)
                           sourceSize:MTLSizeMake(finalTex.width, finalTex.height, 1)
                            toTexture:pDrawableTexture
                     destinationSlice:0
                     destinationLevel:0
                    destinationOrigin:MTLOriginMake(0, 0, 0)];
                [blit endEncoding];
            }
        }

        // 5. Modern ImGui Interface
        {
            MTLRenderPassDescriptor* pRpd = [MTLRenderPassDescriptor renderPassDescriptor];
            pRpd.colorAttachments[0].texture = pDrawableTexture;
            pRpd.colorAttachments[0].loadAction = MTLLoadActionLoad;
            pRpd.colorAttachments[0].storeAction = MTLStoreActionStore;
            pRpd.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
            
            ImGui_ImplMetal_NewFrame(pRpd);
            ImGui_ImplGlfw_NewFrame();
            ImGui::NewFrame();
            
            // Main control window with modern styling
            ImGui::SetNextWindowPos(ImVec2(10, 10), ImGuiCond_FirstUseEver);
            ImGui::SetNextWindowSize(ImVec2(400, 700), ImGuiCond_FirstUseEver);
            
            ImGui::Begin("Black Hole GPU Control Panel", nullptr, ImGuiWindowFlags_None);
            
            // Performance display at top
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.2f, 1.0f, 0.3f, 1.0f));
            ImGui::Text("%.1f FPS | %.2f ms/frame", _currentFPS, _frameTimeMs);
            ImGui::PopStyleColor();
            
            ImGui::Separator();
            
            // Quality preset dropdown
            ImGui::Text("Quality Preset:");
            const char* presets[] = { "Low (Fast)", "Medium", "High", "Ultra (Slow)" };
            if (ImGui::Combo("##preset", &_currentPreset, presets, 4)) {
                applyQualityPreset(_currentPreset);
            }
            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Higher quality = Better visuals but lower FPS");
            }
            
            ImGui::Separator();
            
            // Tabbed interface
            if (ImGui::BeginTabBar("ControlTabs", ImGuiTabBarFlags_None)) {
                
                // === PHYSICS TAB ===
                if (ImGui::BeginTabItem("Physics")) {
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "Core Parameters");
                    ImGui::Separator();
                    
                    ImGui::Text("Gravity Strength");
                    ImGui::SliderFloat("##gravity", &_uniforms.gravity, 0.1f, 10.0f, "%.2f");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Controls how much spacetime curves around the black hole");
                    }
                    
                    ImGui::Text("Disk Radius");
                    ImGui::SliderFloat("##disk_radius", &_uniforms.disk_radius, 1.0f, 20.0f, "%.1f Rs");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Outer edge of the accretion disk (in Schwarzschild radii)");
                    }
                    
                    ImGui::Text("Disk Thickness");
                    ImGui::SliderFloat("##disk_thickness", &_uniforms.disk_thickness, 0.01f, 2.0f, "%.2f");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Vertical extent of the accretion disk");
                    }
                    
                    ImGui::Text("Event Horizon Size");
                    ImGui::SliderFloat("##bh_size", &_uniforms.black_hole_size, 0.01f, 1.0f, "%.2f");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Schwarzschild radius - point of no return");
                    }
                    
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.5f, 0.8f, 1.0f, 1.0f), "Quick Presets");
                    ImGui::Separator();
                    
                    if (ImGui::Button("Gargantua (Interstellar)", ImVec2(-1, 0))) {
                        _uniforms.gravity = 2.5f;
                        _uniforms.disk_radius = 5.0f;
                        _uniforms.disk_thickness = 0.2f;
                        _uniforms.black_hole_size = 0.12f;
                        _uniforms.camera_distance = 8.0f;
                    }
                    
                    if (ImGui::Button("Extreme Gravity", ImVec2(-1, 0))) {
                        _uniforms.gravity = 8.0f;
                        _uniforms.disk_radius = 15.0f;
                        _uniforms.disk_thickness = 0.5f;
                        _uniforms.black_hole_size = 0.5f;
                    }
                    
                    if (ImGui::Button("Thin Disk", ImVec2(-1, 0))) {
                        _uniforms.gravity = 3.0f;
                        _uniforms.disk_radius = 10.0f;
                        _uniforms.disk_thickness = 0.05f;
                        _uniforms.black_hole_size = 0.2f;
                    }
                    
                    ImGui::EndTabItem();
                }
                
                // === VISUAL EFFECTS TAB ===
                if (ImGui::BeginTabItem("Visual")) {
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.7f, 0.9f, 1.0f, 1.0f), "Visual Presets");
                    const char* visualPresets[] = { "Rossning Default", "Rossning Particle Storm", "Rossning Minimal Bloom" };
                    if (ImGui::Combo("##visual_preset", &_currentVisualPreset, visualPresets, IM_ARRAYSIZE(visualPresets))) {
                        applyVisualPreset(_currentVisualPreset);
                    }
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Copy of Ross Ning's OpenGL presets tailored for this renderer");
                    }
                    if (ImGui::Button("Reapply Preset")) {
                        applyVisualPreset(_currentVisualPreset);
                    }
                    ImGui::Spacing();

                    ImGui::TextColored(ImVec4(1.0f, 0.5f, 1.0f, 1.0f), "Relativistic Effects");
                    ImGui::Separator();
                    
                    ImGui::Checkbox("Background Redshift", &_uniforms.background_redshift);
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Gravitational frequency shift of distant stars");
                    }
                    
                    ImGui::Checkbox("Background Doppler", &_uniforms.background_doppler);
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Color shift from relative motion");
                    }
                    
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(1.0f, 0.9f, 0.2f, 1.0f), "Post-Processing");
                    ImGui::Separator();
                    
                    ImGui::Checkbox("Enable Bloom", &_bloomEnabled);
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Glow effect on bright areas of the accretion disk");
                    }
                    
                    if (_bloomEnabled) {
                        ImGui::Indent();
                        ImGui::Text("Bloom Strength");
                        ImGui::SliderFloat("##bloom_str", &_bloomStrength, 0.0f, 1.0f, "%.2f");
                        
                        ImGui::Text("Bloom Threshold");
                        ImGui::SliderFloat("##bloom_thresh", &_bloomThreshold, 0.5f, 2.0f, "%.2f");
                        if (ImGui::IsItemHovered()) {
                            ImGui::SetTooltip("Brightness level required for bloom effect");
                        }
                        
                        ImGui::Text("Bloom Quality");
                        if (ImGui::SliderInt("##bloom_iter", &_bloomIterations, 1, 8)) {
                            _postProcessDirty = true;
                        }
                        if (ImGui::IsItemHovered()) {
                            ImGui::SetTooltip("Higher = smoother glow but slower");
                        }
                        ImGui::Unindent();
                    }
                    
                    ImGui::Spacing();
                    ImGui::Checkbox("Enable Tone Mapping", &_tonemappingEnabled);
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("ACES filmic tone mapping for better color and contrast");
                    }
                    
                    if (_tonemappingEnabled) {
                        ImGui::Indent();
                        ImGui::Text("Gamma Correction");
                        ImGui::SliderFloat("##gamma", &_tonemapGamma, 1.0f, 4.0f, "%.2f");
                        if (ImGui::IsItemHovered()) {
                            ImGui::SetTooltip("Adjust overall brightness curve (2.2 is standard)");
                        }
                        ImGui::Unindent();
                    }
                    
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.8f, 0.9f, 0.4f, 1.0f), "Accretion Disk");
                    ImGui::Separator();
                    if (ImGui::SliderFloat("Vertical Density", &_uniforms.disk_density_vertical, 0.5f, 4.5f, "%.2f")) {
                        _uniforms.disk_density_vertical = std::max(_uniforms.disk_density_vertical, 0.1f);
                    }
                    if (ImGui::SliderFloat("Radial Density", &_uniforms.disk_density_horizontal, 0.5f, 6.0f, "%.2f")) {
                        _uniforms.disk_density_horizontal = std::max(_uniforms.disk_density_horizontal, 0.1f);
                    }
                    ImGui::SliderFloat("Density Gain", &_uniforms.disk_density_gain, 1000.0f, 20000.0f, "%.0f");
                    ImGui::SliderFloat("Density Clamp", &_uniforms.disk_density_clamp, 0.0f, 20.0f, "%.1f");
                    ImGui::SliderFloat("Emission Strength", &_uniforms.disk_emission_strength, 0.05f, 0.5f, "%.2f");
                    ImGui::SliderFloat("Alpha Falloff", &_uniforms.disk_alpha_falloff, 0.2f, 0.9f, "%.2f");
                    ImGui::SliderFloat("Color Mix", &_uniforms.disk_color_mix, 0.0f, 1.0f, "%.2f");
                    ImGui::SliderFloat("Inner Radius Mult", &_uniforms.disk_inner_multiplier, 10.0f, 35.0f, "%.1f");
                    ImGui::SliderFloat("Inner Softness", &_uniforms.disk_inner_softness, 1.01f, 1.5f, "%.2f");
                    ImGui::SliderFloat("Noise Scale", &_uniforms.disk_noise_scale, 0.2f, 2.0f, "%.2f");
                    if (ImGui::SliderFloat("Noise Speed", &_uniforms.disk_noise_speed, 0.1f, 1.5f, "%.2f")) {
                        _uniforms.disk_noise_speed = std::max(_uniforms.disk_noise_speed, 0.1f);
                    }
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Advects turbulence around the disk and controls the perceived rotation speed");
                    }
                    if (ImGui::SliderInt("Noise Octaves", &_uniforms.disk_noise_octaves, 1, 8)) {
                        _uniforms.disk_noise_octaves = std::clamp(_uniforms.disk_noise_octaves, 1, 8);
                    }
                    ImGui::Spacing();
                    if (ImGui::Button("Reset Disk Overrides")) {
                        applyVisualPreset(_currentVisualPreset);
                    }
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Revert disk tweaks back to the selected preset");
                    }
                    
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "Orbiting Star");
                    ImGui::Separator();
                    
                    ImGui::Checkbox("Show Orbiting Star", &_uniforms.show_orbiting_star);
                    
                    if (_uniforms.show_orbiting_star) {
                        ImGui::Indent();
                        ImGui::Text("Orbit Radius");
                        ImGui::SliderFloat("##star_radius", &_uniforms.star_orbit_radius, 3.0f, 15.0f, "%.1f");
                        
                        ImGui::Text("Orbit Speed");
                        ImGui::SliderFloat("##star_speed", &_uniforms.star_orbit_speed, 0.1f, 2.0f, "%.2f rad/s");
                        
                        ImGui::Text("Brightness");
                        ImGui::SliderFloat("##star_bright", &_uniforms.star_brightness, 0.1f, 3.0f, "%.1f");
                        ImGui::Unindent();
                    }
                    
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.5f, 1.0f, 0.5f, 1.0f), "Advanced Settings");
                    ImGui::Separator();
                    
                    ImGui::Text("Max Iterations: %d", _uniforms.max_iterations);
                    ImGui::SliderInt("##max_iter", &_uniforms.max_iterations, 64, 1024);
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("More iterations = Better quality but slower");
                    }
                    
                    ImGui::Text("Step Size: %.3f", _uniforms.step_size);
                    ImGui::SliderFloat("##step", &_uniforms.step_size, 0.05f, 0.2f, "%.3f");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Smaller steps = More accurate but slower");
                    }
                    
                    ImGui::Checkbox("Adaptive Stepping", &_uniforms.adaptive_stepping);
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Automatically adjust step size based on curvature");
                    }
                    
                    ImGui::EndTabItem();
                }
                
                // === CAMERA TAB ===
                if (ImGui::BeginTabItem("Camera")) {
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.5f, 0.8f, 1.0f, 1.0f), "Camera Position");
                    ImGui::Separator();
                    
                    ImGui::Text("Distance from Black Hole");
                    ImGui::SliderFloat("##cam_dist", &_uniforms.camera_distance, 3.0f, 20.0f, "%.1f");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Orbital radius of camera");
                    }
                    
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.5f, 1.0f), "Observer Frame");
                    ImGui::Separator();
                    
                    ImGui::Text("Position (X, Y, Z)");
                    ImGui::SliderFloat3("##obs_pos", (float*)&_uniforms.observer_position, -10.0f, 10.0f, "%.1f");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("3D position of observer in Schwarzschild coordinates");
                    }
                    
                    ImGui::Text("Velocity (X, Y, Z)");
                    ImGui::SliderFloat3("##obs_vel", (float*)&_uniforms.observer_velocity, -0.5f, 0.5f, "%.2f");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Velocity for Doppler shift calculations");
                    }
                    
                    ImGui::Spacing();
                    if (ImGui::Button("Reset to Default", ImVec2(-1, 0))) {
                        _uniforms.camera_distance = 8.0f;
                        _uniforms.observer_position = {0.0f, 0.0f, 8.0f};
                        _uniforms.observer_velocity = {0.0f, 0.0f, 0.0f};
                    }
                    
                    ImGui::EndTabItem();
                }
                
                // === RECORDING TAB ===
                if (ImGui::BeginTabItem("Recording")) {
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "Screen Capture");
                    ImGui::Separator();
                    
                    ImGui::TextWrapped("Use macOS built-in screen recording for best results:");
                    ImGui::Spacing();
                    
                    ImGui::BulletText("Press Cmd+Shift+5 for screen recorder");
                    ImGui::BulletText("Or use QuickTime Player > File > New Screen Recording");
                    ImGui::BulletText("For screenshots: Press Cmd+Shift+4 and select area");
                    
                    ImGui::Spacing();
                    ImGui::Separator();
                    ImGui::Spacing();
                    
                    ImGui::TextColored(ImVec4(0.7f, 0.7f, 0.7f, 1.0f), "Built-in Video Recording:");
                    ImGui::TextWrapped("(Coming soon - requires Metal texture capture implementation)");
                    
                    ImGui::Spacing();
                    if (ImGui::Button("Coming Soon", ImVec2(-1, 0))) {
                        // Placeholder for future implementation
                    }
                    // Tooltip requires hover checks in some ImGui versions
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("Video recording feature requires advanced Metal texture capture.\nUse macOS screen recording for now.");
                    }
                    
                    ImGui::Spacing();
                    ImGui::Separator();
                    ImGui::TextWrapped("Tip: Set quality to Ultra before recording for best visual results!");
                    
                    ImGui::EndTabItem();
                }
                
                ImGui::EndTabBar();
            }
            
            ImGui::Separator();
            ImGui::TextWrapped("GPU-accelerated black hole ray tracer with scientifically accurate physics");
            
            ImGui::End();

            ImGui::Render();
            
            id<MTLRenderCommandEncoder> pEnc = [pCmd renderCommandEncoderWithDescriptor:pRpd];
            ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), pCmd, pEnc);
            [pEnc endEncoding];
        }

        // Capture frame if recording
        if (_isRecording) {
            captureFrame();
        }

        [pCmd presentDrawable:pDrawable];
        [pCmd commit];
    }
}

// Helper to dispatch a compute kernel sized to an output texture
static inline void dispatchForTexture(id<MTLComputePipelineState> pso,
                                     id<MTLComputeCommandEncoder> enc,
                                     id<MTLTexture> outTex) {
    MTLSize grid = MTLSizeMake(outTex.width, outTex.height, 1);
    NSUInteger tw = pso.threadExecutionWidth;
    NSUInteger th = pso.maxTotalThreadsPerThreadgroup / tw;
    if (th == 0) th = 1; // Safety
    MTLSize tgs = MTLSizeMake(tw, th, 1);
    [enc dispatchThreads:grid threadsPerThreadgroup:tgs];
}

void Renderer::applyBloomEffect(void* commandBuffer, void* inputTexture, void* outputTexture)
{
    id<MTLCommandBuffer> cmd = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLTexture> src = (__bridge id<MTLTexture>)inputTexture;
    id<MTLTexture> dst = (__bridge id<MTLTexture>)outputTexture;

    id<MTLComputePipelineState> brightPSO = (__bridge id<MTLComputePipelineState>)_bloomBrightnessPSO;
    id<MTLComputePipelineState> downPSO = (__bridge id<MTLComputePipelineState>)_bloomDownsamplePSO;
    id<MTLComputePipelineState> upPSO = (__bridge id<MTLComputePipelineState>)_bloomUpsamplePSO;
    id<MTLComputePipelineState> compPSO = (__bridge id<MTLComputePipelineState>)_bloomCompositePSO;

    if (!src || !dst || !brightPSO || !downPSO || !upPSO || !compPSO || !_brightnessTexture) {
        return;
    }

    // 1) Brightness extraction
    {
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:brightPSO];
        [enc setTexture:src atIndex:0];
        [enc setTexture:(__bridge id<MTLTexture>)_brightnessTexture atIndex:1];
        float threshold = _bloomThreshold;
        [enc setBytes:&threshold length:sizeof(float) atIndex:0];
        dispatchForTexture(brightPSO, enc, (__bridge id<MTLTexture>)_brightnessTexture);
        [enc endEncoding];
    }

    // 2) Downsample pyramid
    int levels = std::min(_bloomIterations, _allocatedBloomIterations);
    id<MTLTexture> prev = (__bridge id<MTLTexture>)_brightnessTexture;
    int builtLevels = 0;
    for (int i = 0; i < levels; ++i) {
        if (_bloomDownsample[i] == nullptr) break;
        id<MTLTexture> outLvl = (__bridge id<MTLTexture>)_bloomDownsample[i];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:downPSO];
        [enc setTexture:prev atIndex:0];
        [enc setTexture:outLvl atIndex:1];
        dispatchForTexture(downPSO, enc, outLvl);
        [enc endEncoding];
        prev = outLvl;
        builtLevels++;
    }

    // 3) Upsample and combine
    id<MTLTexture> upPrev = prev; // start from smallest level
    for (int i = builtLevels - 1; i >= 0; --i) {
        id<MTLTexture> bigger = (__bridge id<MTLTexture>)_bloomUpsample[i];
        id<MTLTexture> dsLvl = (__bridge id<MTLTexture>)_bloomDownsample[i];
        if (!bigger || !dsLvl) {
            continue;
        }
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:upPSO];
        [enc setTexture:upPrev atIndex:0];       // smaller
        [enc setTexture:dsLvl atIndex:1];        // previous bigger level to add into
        [enc setTexture:bigger atIndex:2];       // output bigger size
        dispatchForTexture(upPSO, enc, bigger);
        [enc endEncoding];
        upPrev = bigger;
    }

    // 4) Composite bloom with scene into dst
    {
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        [enc setComputePipelineState:compPSO];
        [enc setTexture:src atIndex:0];
        [enc setTexture:upPrev atIndex:1];
        [enc setTexture:dst atIndex:2];
        float strength = _bloomStrength;
        float tone = 1.0f;
        [enc setBytes:&strength length:sizeof(float) atIndex:0];
        [enc setBytes:&tone length:sizeof(float) atIndex:1];
        dispatchForTexture(compPSO, enc, dst);
        [enc endEncoding];
    }
}

void Renderer::applyToneMapping(void* commandBuffer, void* inputTexture, void* outputTexture)
{
    id<MTLCommandBuffer> cmd = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLTexture> src = (__bridge id<MTLTexture>)inputTexture;
    id<MTLTexture> dst = (__bridge id<MTLTexture>)outputTexture;
    id<MTLComputePipelineState> pso = (__bridge id<MTLComputePipelineState>)_tonemappingPSO;

    if (!pso || !src || !dst) {
        return;
    }

    id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
    [enc setComputePipelineState:pso];
    [enc setTexture:src atIndex:0];
    [enc setTexture:dst atIndex:1];
    float gamma = _tonemapGamma;
    bool enabled = _tonemappingEnabled;
    [enc setBytes:&gamma length:sizeof(float) atIndex:0];
    [enc setBytes:&enabled length:sizeof(bool) atIndex:1];
    dispatchForTexture(pso, enc, dst);
    [enc endEncoding];
}
