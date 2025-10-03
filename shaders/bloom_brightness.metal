#include <metal_stdlib>
using namespace metal;

// Brightness extraction pass for bloom effect
// Extracts pixels above threshold for glow
kernel void bloom_brightness_pass(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float &brightPassThreshold [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float4 color = inputTexture.read(gid);
    
    // Luminance calculation
    const float3 luminanceVector = float3(0.2125, 0.7154, 0.0721);
    float luminance = dot(color.rgb, luminanceVector);
    
    // Brightness threshold for bloom (from CPU)
    luminance = max(0.0, luminance - brightPassThreshold);
    
    // Only keep bright pixels
    color.rgb *= sign(luminance);
    color.a = 1.0;
    
    outputTexture.write(color, gid);
}

// Downsample pass with 4-tap bilinear filter
kernel void bloom_downsample(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // 4-tap box filter
    float4 offset = texelSize.xyxy * float4(-1.0, -1.0, 1.0, 1.0) * 0.5;
    
    float4 color = 0.25 * (
        inputTexture.sample(textureSampler, uv + offset.xy) +
        inputTexture.sample(textureSampler, uv + offset.zy) +
        inputTexture.sample(textureSampler, uv + offset.xw) +
        inputTexture.sample(textureSampler, uv + offset.zw)
    );
    
    outputTexture.write(color, gid);
}

// Upsample and combine pass
kernel void bloom_upsample(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::sample> previousTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // 4-tap tent filter for upsample
    float4 offset = texelSize.xyxy * float4(-1.0, -1.0, 1.0, 1.0) * 0.5;
    
    float4 color = 0.25 * (
        inputTexture.sample(textureSampler, uv + offset.xy) +
        inputTexture.sample(textureSampler, uv + offset.zy) +
        inputTexture.sample(textureSampler, uv + offset.xw) +
        inputTexture.sample(textureSampler, uv + offset.zw)
    );
    
    // Add previous level
    color += previousTexture.sample(textureSampler, uv);
    color.a = 1.0;
    
    outputTexture.write(color, gid);
}

// Final bloom composite
kernel void bloom_composite(
    texture2d<float, access::read> sceneTexture [[texture(0)]],
    texture2d<float, access::read> bloomTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant float &bloomStrength [[buffer(0)]],
    constant float &tone [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float4 sceneColor = sceneTexture.read(gid);
    float4 bloomColor = bloomTexture.read(gid);
    
    float4 finalColor = sceneColor * tone + bloomColor * bloomStrength;
    finalColor.a = 1.0;
    
    outputTexture.write(finalColor, gid);
}
