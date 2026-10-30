#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Fixed-camera optics: refract the actual chapter plate through the live PET mesh.
// This is a mobile approximation, not ray tracing or a simulated liquid volume.
[[visible]] void bottleGlass(realitykit::surface_parameters params) {
    float4 frame = params.uniforms().custom_parameter();
    float2 screen = params.geometry().screen_position().xy / max(frame.xy, float2(1));
    float2 imageUV = float2(screen.x, frame.z + screen.y * frame.w);
    float visibleWidth = (frame.x / frame.y) * frame.w / (2.0 / 3.0);
    imageUV.x = 0.5 + (imageUV.x - 0.5) * min(1.0, visibleWidth);
    constexpr sampler imageSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    auto chapter = params.textures().custom();
    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());
    float3 nv = normalize((params.uniforms().world_to_view() * float4(n, 0)).xyz);
    float3 p = params.geometry().model_position();
    float fill = params.material_constants().roughness_scale();
    int liquid = int(round(params.material_constants().metallic_scale() * 2));
    float fillHeight = -0.126 + 0.205 * fill;
    float meniscus = 0.0015 * (1 - saturate(p.x * p.x / (0.048 * 0.048)));
    float submerged = 1 - smoothstep(fillHeight + meniscus - 0.0012, fillHeight + meniscus + 0.0012, p.y);
    float fresnel = 0.028 + 0.972 * pow(1 - saturate(abs(dot(n, v))), 5.0);
    float lens = mix(0.004, 0.012, submerged);
    if (p.y < -0.116) lens *= 1.7;
    float2 refractedUV = imageUV + float2(nv.x * visibleWidth, -nv.y * frame.w) * lens;
    // A light PET haze softens scenery inside the shell, so the bottle's body
    // reads separately from a detailed background without turning solid white.
    float2 softness = float2(0.0025 * visibleWidth, 0.0025 * frame.w);
    half3 transmitted = chapter.sample(imageSampler, refractedUV).rgb * half(0.60);
    transmitted += chapter.sample(imageSampler, refractedUV + float2(softness.x, 0)).rgb * half(0.10);
    transmitted += chapter.sample(imageSampler, refractedUV - float2(softness.x, 0)).rgb * half(0.10);
    transmitted += chapter.sample(imageSampler, refractedUV + float2(0, softness.y)).rgb * half(0.10);
    transmitted += chapter.sample(imageSampler, refractedUV - float2(0, softness.y)).rgb * half(0.10);
    float3 absorption = liquid == 2 ? float3(0.58, 0.08, 0.13)
        : liquid == 1 ? float3(1.0, 0.52, 0.10) : float3(0.82, 0.94, 1.0);
    transmitted *= half3(mix(float3(1), absorption, submerged * 0.78));
    half3 frost = half3(0.64, 0.77, 0.83) * half3(mix(float3(1), absorption, submerged * 0.55));
    transmitted = mix(transmitted, frost, half(0.22));
    transmitted *= half3(mix(float3(1), params.material_constants().base_color_tint(), 0.16));
    float3 r = reflect(-v, n);
    half3 reflected = chapter.sample(imageSampler, float2(0.5 + r.x * 0.45, 0.34 - r.y * 0.25)).rgb;
    float leftLight = exp(-pow((nv.x + 0.62) / 0.12, 2.0));
    float rightLight = exp(-pow((nv.x - 0.87) / 0.07, 2.0));
    float mouldedEdge = pow(abs(nv.y), 3.0) * 0.34;
    half3 colour = mix(transmitted, reflected, half(min(0.85, fresnel * 0.9 + 0.075)));
    // Thicker PET at grazing angles has a cool darker rim. Paired with the
    // specular strips, this keeps the silhouette legible on bright stone/ice.
    colour = mix(colour, half3(0.10, 0.22, 0.28), half(fresnel * 0.26));
    colour += half3(1.0, 0.97, 0.94) * half(leftLight * 0.80 + rightLight * 0.95 + mouldedEdge);
    colour += half3(0.14, 0.22, 0.30) * half(submerged * 0.12);
    float waterline = exp(-pow((p.y - fillHeight - meniscus) / 0.0020, 2.0));
    colour = mix(colour, half3(0.88, 0.96, 1.0), half(waterline * 0.70));
    float thickBase = 1 - smoothstep(-0.132, -0.112, p.y);
    colour = mix(colour, reflected * half3(0.70, 0.91, 1.0), half(thickBase * (0.22 + fresnel * 0.35)));
    colour += half3(0.16, 0.28, 0.40) * half(thickBase * pow(abs(nv.y), 3.0));
    float floorLevel = params.material_constants().clearcoat_scale();
    float contact = 1 - smoothstep(0.001, 0.008, params.geometry().world_position().y - floorLevel);
    colour *= half(1 - contact * 0.25);
    params.surface().set_base_color(half3(0));
    params.surface().set_emissive_color(colour);
    params.surface().set_opacity(1.0);
}
