# CMake project definition
cmake_minimum_required(VERSION 3.15)
project(BlackHoleGPU VERSION 1.0.0 LANGUAGES CXX OBJCXX)

# Set C++ standard to C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED YES)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED YES)

# --- Add Dependencies from the 'vendor' folder ---

# Add GLFW for windowing
add_subdirectory(vendor/glfw)

# Add Dear ImGui source files
file(GLOB IMGUI_SOURCES
    "vendor/imgui/imgui.cpp"
    "vendor/imgui/imgui_draw.cpp"
    "vendor/imgui/imgui_tables.cpp"
    "vendor/imgui/imgui_widgets.cpp"
    "vendor/imgui/backends/imgui_impl_glfw.cpp"
    "vendor/imgui/backends/imgui_impl_metal.mm"
)

# --- Configure the Main Executable ---

# Add our source files
add_executable(BlackHole
    src/main.cpp
    src/Renderer.mm
    ${IMGUI_SOURCES}
)

# Specify include directories so the compiler can find the headers
target_include_directories(BlackHole PUBLIC
    "src"
    "vendor/metal-cpp"
    "vendor/glm"
    "vendor/imgui"
    "vendor/imgui/backends"
)

# --- Link macOS Frameworks ---
find_library(METAL_LIB Metal)
find_library(FOUNDATION_LIB Foundation)
find_library(QUARTZCORE_LIB QuartzCore)
find_library(GAME_CONTROLLER_LIB GameController)
find_library(AVFOUNDATION_LIB AVFoundation)
find_library(COREMEDIA_LIB CoreMedia)
find_library(COREVIDEO_LIB CoreVideo)

target_link_libraries(BlackHole PUBLIC
    glfw            # Link our compiled GLFW library
    ${METAL_LIB}
    ${FOUNDATION_LIB}
    ${QUARTZCORE_LIB}
    ${GAME_CONTROLLER_LIB}
    ${AVFOUNDATION_LIB}
    ${COREMEDIA_LIB}
    ${COREVIDEO_LIB}
)

# --- Handle Metal Shaders ---
# This ensures the .metal files are compiled and added to the app bundle
set_source_files_properties(
    shaders/BlackHole.metal
    shaders/bloom_brightness.metal  
    shaders/tonemapping.metal
    PROPERTIES 
    MACOSX_PACKAGE_LOCATION "Resources"
    COMPILE_FLAGS "-I${CMAKE_CURRENT_SOURCE_DIR}/src")

target_sources(BlackHole PRIVATE 
    shaders/BlackHole.metal
    shaders/bloom_brightness.metal
    shaders/tonemapping.metal
)

# --- macOS Bundle Configuration ---
# Set properties for macOS app bundle with proper Info.plist
set_target_properties(BlackHole PROPERTIES 
    MACOSX_BUNDLE YES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME "Black Hole GPU"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.blackholegpu.raytracer"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0.0"
    MACOSX_BUNDLE_COPYRIGHT "Copyright © 2025 Black Hole GPU Contributors"
)
