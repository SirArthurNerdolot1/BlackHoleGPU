/**
 * Black Hole GPU Ray Tracer
 * 
 * A real-time black hole visualization using GPU-accelerated ray tracing.
 * Implements scientifically accurate gravitational lensing, accretion disk physics,
 * and relativistic effects including Doppler shift and gravitational redshift.
 * 
 * Based on the Schwarzschild metric and general relativity physics.
 * 
 * Author: Ported to Metal/macOS
 * Original Physics: hydrogendeuteride/BlackHoleRayTracer
 * Date: October 2025
 */

#include <iostream>
#define GLFW_INCLUDE_NONE // IMPORTANT: This prevents GLFW from including graphics headers
#include <GLFW/glfw3.h>
#include "Renderer.hpp"   // This should be the ONLY local include

int main() {
    // Initialize the GLFW windowing system
    if (!glfwInit()) {
        std::cerr << "Failed to initialize GLFW" << std::endl;
        return -1;
    }

    // Configure window for Metal rendering (no OpenGL)
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    
    // Create application window
    GLFWwindow* window = glfwCreateWindow(1280, 720, "Black Hole GPU - Scientific Ray Tracer", nullptr, nullptr);
    if (!window) {
        std::cerr << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return -1;
    }

    try {
        // Initialize the Metal renderer
        Renderer renderer(window);

        // Main render loop
        while (!glfwWindowShouldClose(window)) {
            // Process window events (keyboard, mouse, etc.)
            glfwPollEvents();
            
            // Render one frame
            renderer.draw();
        }
    } catch (const std::exception& e) {
        std::cerr << "Renderer error: " << e.what() << std::endl;
        glfwDestroyWindow(window);
        glfwTerminate();
        return -1;
    }

    // Clean up resources
    glfwDestroyWindow(window);
    glfwTerminate();
    
    return 0;
}
