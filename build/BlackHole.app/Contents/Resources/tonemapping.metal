#include <metal_stdlib>
using namespace metal;

// ACES Filmic Tone Mapping
// Based on Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
float3 aces_tonemap(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

kernel void tonemapping_kernel(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float &gamma [[buffer(0)]],
    constant bool &tonemappingEnabled [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float4 color = inputTexture.read(gid);
    
    if (tonemappingEnabled) {
        // Apply ACES filmic tone mapping
        color.rgb = aces_tonemap(color.rgb);
        
        // Gamma correction
        color.rgb = pow(color.rgb, float3(1.0 / gamma));
    }
    
    color.a = 1.0;
    outputTexture.write(color, gid);
}
