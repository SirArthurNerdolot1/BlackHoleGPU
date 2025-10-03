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
    _currentTab(0), _currentPreset(2)
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
    // Stop recording if active
    if (_isRecording) {
        stopRecording();
    }
    
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
    
        // 2. Modern ImGui Interface
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
                    ImGui::SetItemTooltip("Video recording feature requires advanced Metal texture capture.\nUse macOS screen recording for now.");
                    
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
