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

// Platform-specific headers for Metal and GLFW integration
#define GLFW_INCLUDE_NONE
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_metal.h"

Renderer::Renderer(GLFWwindow* pWindow) : _pWindow(pWindow)
{
    // Initialize default parameters inspired by Gargantua from Interstellar
    // These values provide a good balance between visual appeal and scientific accuracy
    _uniforms.time = 0.0f;
    _uniforms.gravity = 2.5f;           // Strong gravitational field for dramatic lensing
    _uniforms.disk_radius = 5.0f;       // Moderate disk size (5× Schwarzschild radius)
    _uniforms.disk_thickness = 0.2f;    // Geometrically thin disk
    _uniforms.black_hole_size = 0.12f;  // Event horizon size
    _uniforms.camera_distance = 8.0f;   // Safe viewing distance outside ISCO
    
    // Observer parameters (initially at camera position)
    _uniforms.observer_position = {0.0f, 0.0f, 8.0f};
    _uniforms.observer_velocity = {0.0f, 0.0f, 0.0f};
    
    // Orbiting star parameters for additional visual interest
    _uniforms.show_orbiting_star = true;
    _uniforms.star_orbit_radius = 6.0f;     // Outside photon sphere (3M)
    _uniforms.star_orbit_speed = 0.5f;      // rad/s
    _uniforms.star_brightness = 1.0f;
    
    // Enable relativistic background effects by default
    _uniforms.background_redshift = true;
    _uniforms.background_doppler = true;

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
}

Renderer::~Renderer()
{
    // Clean up ImGui resources first
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    // In non-ARC, just set pointers to nil - objects will be released when no longer referenced
    _pPSO = nullptr;
    _pCommandQueue = nullptr;
    _pMetalLayer = nullptr;
    _pDevice = nullptr;
}

void Renderer::draw()
{
    @autoreleasepool {
        CAMetalLayer* metalLayer = (__bridge CAMetalLayer*)_pMetalLayer;
        id<CAMetalDrawable> pDrawable = [metalLayer nextDrawable];
        if (!pDrawable) {
            return;
        }

        id<MTLTexture> pDrawableTexture = pDrawable.texture;
        
        // Sync layer size with window size
        int width, height;
        glfwGetFramebufferSize(_pWindow, &width, &height);
        if (width != metalLayer.drawableSize.width || height != metalLayer.drawableSize.height) {
            metalLayer.drawableSize = CGSizeMake(width, height);
        }
        
        id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)_pCommandQueue;
        id<MTLCommandBuffer> pCmd = [commandQueue commandBuffer];
        if (!pCmd) {
            std::cerr << "Failed to create command buffer" << std::endl;
            return;
        }

        // 1. Black Hole Compute Pass
        {
            id<MTLComputePipelineState> pso = (__bridge id<MTLComputePipelineState>)_pPSO;
            id<MTLComputeCommandEncoder> pEnc = [pCmd computeCommandEncoder];
            [pEnc setComputePipelineState:pso];
            [pEnc setTexture:pDrawableTexture atIndex:0];

            _uniforms.time += 0.01f;
            _uniforms.resolution = {(float)pDrawableTexture.width, (float)pDrawableTexture.height};
            [pEnc setBytes:&_uniforms length:sizeof(Uniforms) atIndex:0];
            
            MTLSize gridSize = MTLSizeMake(pDrawableTexture.width, pDrawableTexture.height, 1);
            NSUInteger threadGroupWidth = pso.threadExecutionWidth;
            NSUInteger threadGroupHeight = pso.maxTotalThreadsPerThreadgroup / threadGroupWidth;
            MTLSize threadgroupSize = MTLSizeMake(threadGroupWidth, threadGroupHeight, 1);

            [pEnc dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
            [pEnc endEncoding];
        }
    
        // 2. ImGui Render Pass
        {
            // Create render pass descriptor with correct settings for ImGui
            MTLRenderPassDescriptor* pRpd = [MTLRenderPassDescriptor renderPassDescriptor];
            pRpd.colorAttachments[0].texture = pDrawableTexture;
            pRpd.colorAttachments[0].loadAction = MTLLoadActionLoad;
            pRpd.colorAttachments[0].storeAction = MTLStoreActionStore;
            pRpd.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
            
            // Start ImGui frame with proper render pass descriptor
            ImGui_ImplMetal_NewFrame(pRpd);
            ImGui_ImplGlfw_NewFrame();
            ImGui::NewFrame();
            
            ImGui::Begin("Gargantua Black Hole");
            ImGui::Text("Interstellar-style Black Hole Simulation");
            ImGui::Separator();
            
            ImGui::Text("Black Hole Properties:");
            ImGui::SliderFloat("Gravity Strength", &_uniforms.gravity, 1.0f, 4.0f);
            ImGui::SliderFloat("Accretion Disk Radius", &_uniforms.disk_radius, 3.0f, 10.0f);
            ImGui::SliderFloat("Disk Thickness", &_uniforms.disk_thickness, 0.1f, 1.0f);
            ImGui::SliderFloat("Schwarzschild Radius", &_uniforms.black_hole_size, 0.1f, 0.6f);
            ImGui::SliderFloat("Camera Distance", &_uniforms.camera_distance, 8.0f, 15.0f);
            
            ImGui::Separator();
            ImGui::Text("Observer Controls:");
            ImGui::SliderFloat3("Position", (float*)&_uniforms.observer_position, -10.0f, 10.0f);
            ImGui::SliderFloat3("Velocity", (float*)&_uniforms.observer_velocity, -0.5f, 0.5f);
            
            ImGui::Separator();
            ImGui::Text("Orbiting Star:");
            ImGui::Checkbox("Show Orbiting Star", &_uniforms.show_orbiting_star);
            if (_uniforms.show_orbiting_star) {
                ImGui::SliderFloat("Orbit Radius", &_uniforms.star_orbit_radius, 3.0f, 10.0f);
                ImGui::SliderFloat("Orbit Speed", &_uniforms.star_orbit_speed, 0.1f, 2.0f);
                ImGui::SliderFloat("Star Brightness", &_uniforms.star_brightness, 0.1f, 3.0f);
            }
            
            ImGui::Separator();
            ImGui::Text("Relativistic Effects:");
            ImGui::Checkbox("Background Redshift", &_uniforms.background_redshift);
            ImGui::Checkbox("Background Doppler", &_uniforms.background_doppler);
            
            ImGui::Separator();
            ImGui::Text("Performance:");
            ImGui::Text("%.3f ms/frame (%.1f FPS)", 1000.0f / ImGui::GetIO().Framerate, ImGui::GetIO().Framerate);
            
            ImGui::Separator();
            ImGui::TextWrapped("Scientific black hole with observer controls, orbiting star, and relativistic effects on background.");
            ImGui::End();

            ImGui::Render();
            
            id<MTLRenderCommandEncoder> pEnc = [pCmd renderCommandEncoderWithDescriptor:pRpd];
            ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), pCmd, pEnc);
            [pEnc endEncoding];
        }

        [pCmd presentDrawable:pDrawable];
        [pCmd commit];
    }
}
