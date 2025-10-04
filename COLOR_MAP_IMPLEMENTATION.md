# Accretion Disk Color Map Implementation

## Summary

Successfully implemented a procedural color map texture system for the accretion disk rendering, inspired by the rossning92/Blackhole reference implementation. The color map provides an artistic temperature gradient from the hot inner disk to the cooler outer disk regions.

## Changes Made

### 1. Renderer Header (Renderer.hpp)
- Added `void* _diskColorMap;` member variable to store the MTLTexture for the color gradient

### 2. Renderer Implementation (Renderer.mm)

#### Color Map Creation (Constructor)
- Created a 256x1 RGBA8 texture with a procedural temperature gradient:
  - **Inner region (0-30%)**: Blue-white to white (very hot plasma)
  - **Middle region (30-60%)**: White to yellow-orange (moderate temperature)  
  - **Outer region (60-100%)**: Orange to deep red (cooler gas)
- Applied exponential curves for natural color falloff
- Texture is created with `MTLTextureUsageShaderRead` for GPU sampling

#### Texture Binding (draw method)
- Bound color map texture to `texture(1)` slot in the compute shader
- Added proper texture binding before shader dispatch

#### Resource Cleanup (Destructor)
- Added `releaseObj(_diskColorMap)` to properly release the texture when renderer is destroyed

### 3. Metal Shader (BlackHole.metal)

#### Kernel Signature Update
```metal
kernel void computeShader(
    texture2d<float, access::write> output [[texture(0)]],
    texture2d<float, access::sample> diskColorMap [[texture(1)]],  // NEW
    constant Uniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
```

#### Function Signature Updates
- Updated `rayMarch()` to accept and pass through the `diskColorMap` texture
- Updated `diskRender()` to accept and sample from the `diskColorMap` texture

#### Color Map Integration in diskRender()
- Added a linear sampler for the color map texture:
  ```metal
  constexpr sampler colorSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
  ```
- Sample color based on normalized radial position:
  ```metal
  float4 sampledColor = diskColorMap.sample(colorSampler, float2(radialNorm, 0.5));
  ```
- Created hybrid color system that blends between:
  - Physics-based blackbody radiation (when `disk_color_mix = 0.0`)
  - Artistic color map gradient (when `disk_color_mix = 1.0`)
  - Smooth interpolation for values in between

## Technical Details

### Color Gradient Design
The procedural gradient mimics the temperature profile of an accretion disk:
- **Hot inner regions**: Blue-white tones representing plasma at 20,000K+
- **Moderate regions**: Yellow-orange representing 10,000K temperatures
- **Outer regions**: Deep red-orange representing 5,000K cooler gas

### Shader Architecture
The implementation maintains backward compatibility by allowing users to blend between:
1. **Full physics mode**: Pure blackbody radiation based on temperature calculations
2. **Artistic mode**: Color map for more visually striking appearance (rossning92 style)
3. **Hybrid mode**: Mix of both for customizable appearance

The `disk_color_mix` uniform controls this blend (0.0 = physics, 1.0 = artistic).

## Usage

Run the application and adjust the **Disk Color Mix** parameter in the ImGui interface:
- `0.0` - Pure physics-based blackbody colors
- `0.5` - Balanced blend (default: 0.65)
- `1.0` - Full artistic color map gradient

## Build Status

✅ **Build Successful** - Project compiles with only 3 harmless shader warnings (unused constants)

## Benefits

1. **Visual Variety**: Provides artistic control over disk appearance
2. **Performance**: Texture sampling is faster than complex blackbody calculations
3. **Compatibility**: Maintains existing physics-based rendering as an option
4. **Flexibility**: Easy to modify the gradient for different visual styles

## Future Enhancements

Possible improvements:
- Add ability to load custom color map textures from disk
- Create multiple preset gradients (Gargantua, M87, artistic)
- Add color map selection in ImGui interface
- Implement color map editor for real-time gradient adjustment
