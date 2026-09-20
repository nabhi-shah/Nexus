#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] float2 rippleDistortion(float2 position, float time, float2 center, float amplitude, float frequency, float decay) {
    float distance = length(position - center);
    float delay = distance / 800.0; // speed of the shockwave
    
    float timeEffect = time - delay;
    if (timeEffect < 0.0) return position;
    
    float amount = amplitude * sin(timeEffect * frequency) * exp(-distance * decay) * exp(-timeEffect * 4.0);
    float2 direction = normalize(position - center);
    
    return position + direction * amount;
}

[[ stitchable ]] half4 chromaticRipple(float2 position, SwiftUI::Layer layer, float time, float2 center, float amplitude, float frequency, float decay) {
    float distance = length(position - center);
    float delay = distance / 2000.0; // Faster shockwave speed
    
    float timeEffect = time - delay;
    
    // We only want ONE strong ring. 
    // The ring lasts for `pulseWidth` seconds at any given pixel.
    float pulseWidth = 0.25; // Faster pulse width
    
    if (timeEffect < 0.0 || timeEffect > pulseWidth) {
        return layer.sample(position);
    }
    
    // Create a single smooth bell curve (0 to 1 back to 0)
    float wave = sin((timeEffect / pulseWidth) * M_PI_F);
    
    // No need to decay over time anymore because the pulse is localized.
    // We just decay it slightly over distance so it's strongest at the center.
    float envelope = exp(-distance * decay * 0.5); // Less distance decay so it stays strong longer
    
    // Calculate base intensity
    float baseAmount = amplitude * wave * envelope;
    
    // Reduce the physical structural distortion (lens warp) significantly
    float amount = baseAmount * 0.8; // Reduced from 2.0 to 0.8
    float2 direction = normalize(position - center);
    
    // Keep the chromatic aberration exactly as strong as before (was 2.0 * 0.5 = 1.0)
    float chromaticSpread = baseAmount * 1.0; 
    
    float2 rPos = position + direction * (amount + chromaticSpread);
    float2 gPos = position + direction * amount;
    float2 bPos = position + direction * (amount - chromaticSpread);
    
    half4 rColor = layer.sample(rPos);
    half4 gColor = layer.sample(gPos);
    half4 bColor = layer.sample(bPos);
    
    // Add white shine at the crest of the single wave
    float shine = wave * envelope * 0.8; // 80% white at the absolute crest for a very bright shine
    
    return half4(rColor.r + shine, gColor.g + shine, bColor.b + shine, gColor.a);
}
