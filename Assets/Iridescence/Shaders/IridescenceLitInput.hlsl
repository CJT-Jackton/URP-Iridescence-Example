#ifndef UNIVERSAL_IRIDESCENCE_LIT_INPUT_INCLUDED
#define UNIVERSAL_IRIDESCENCE_LIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

// Duplicate from Input.hlsl
struct InputDataAdvanced
{
    float3  positionWS;
    half3   normalWS;
    half3   viewDirectionWS;
    float4  shadowCoord;
    half    fogCoord;
    half3   vertexLighting;
    half3   bakedGI;
};

// Duplicate from SurfaceInput.hlsl
struct SurfaceDataAdvanced
{
    half3 albedo;
    half3 specular;
    half  metallic;
    half  smoothness;
    half3 normalTS;
    half3 emission;
    half  occlusion;
    half  alpha;
#ifdef _IRIDESCENCE
    half iridescenceThickness;
    half iridescenceEta2;
    half iridescenceEta3;
    half iridescenceKappa3;
#endif
};

CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST;
half4 _BaseColor;
half4 _SpecColor;
half4 _EmissionColor;
half4 _IridescenceThicknessRemap;
half _Cutoff;
half _Smoothness;
half _Metallic;
half _BumpScale;
half _OcclusionStrength;
half _IridescenceThickness;
half _IridescneceEta2;
half _IridescneceEta3;
half _IridescneceKappa3;
CBUFFER_END

TEXTURE2D(_OcclusionMap);               SAMPLER(sampler_OcclusionMap);
TEXTURE2D(_MetallicGlossMap);           SAMPLER(sampler_MetallicGlossMap);
TEXTURE2D(_SpecGlossMap);               SAMPLER(sampler_SpecGlossMap);
TEXTURE2D(_IridescenceThicknessMap);    SAMPLER(sampler_IridescenceThicknessMap);

#ifdef _SPECULAR_SETUP
    #define SAMPLE_METALLICSPECULAR(uv) SAMPLE_TEXTURE2D(_SpecGlossMap, sampler_SpecGlossMap, uv)
#else
    #define SAMPLE_METALLICSPECULAR(uv) SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, uv)
#endif

half4 SampleMetallicSpecGloss(float2 uv, half albedoAlpha)
{
    half4 specGloss;

#ifdef _METALLICSPECGLOSSMAP
    specGloss = SAMPLE_METALLICSPECULAR(uv);
    #ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
        specGloss.a = albedoAlpha * _Smoothness;
    #else
        specGloss.a *= _Smoothness;
    #endif
#else // _METALLICSPECGLOSSMAP
    #if _SPECULAR_SETUP
        specGloss.rgb = _SpecColor.rgb;
    #else
        specGloss.rgb = _Metallic.rrr;
    #endif

    #ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
        specGloss.a = albedoAlpha * _Smoothness;
    #else
        specGloss.a = _Smoothness;
    #endif
#endif

    return specGloss;
}

half SampleOcclusion(float2 uv)
{
#ifdef _OCCLUSIONMAP
// TODO: Controls things like these by exposing SHADER_QUALITY levels (low, medium, high)
#if defined(SHADER_API_GLES)
    return SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;
#else
    half occ = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;
    return LerpWhiteTo(occ, _OcclusionStrength);
#endif
#else
    return 1.0;
#endif
}

half SampleIridescenceThickness(float2 uv)
{
    half iridescenceThickness;

#if _IRIDESCENCE_THICKNESSMAP
    iridescenceThickness = SAMPLE_TEXTURE2D(_IridescenceThicknessMap, sampler_IridescenceThicknessMap, uv).r;
    iridescenceThickness = _IridescenceThicknessRemap.x + iridescenceThickness * (_IridescenceThicknessRemap.y - _IridescenceThicknessRemap.x);
#else
    iridescenceThickness = _IridescenceThickness;
#endif

    return iridescenceThickness;
}

inline void InitializeStandardLitSurfaceData(float2 uv, out SurfaceDataAdvanced outSurfaceData)
{
    half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
    outSurfaceData.alpha = Alpha(albedoAlpha.a, _BaseColor, _Cutoff);

    half4 specGloss = SampleMetallicSpecGloss(uv, albedoAlpha.a);
    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;

#if _SPECULAR_SETUP
    outSurfaceData.metallic = 1.0h;
    outSurfaceData.specular = specGloss.rgb;
#else
    outSurfaceData.metallic = specGloss.r;
    outSurfaceData.specular = half3(0.0h, 0.0h, 0.0h);
#endif

    outSurfaceData.smoothness = specGloss.a;
    outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
    outSurfaceData.occlusion = SampleOcclusion(uv);
    outSurfaceData.emission = SampleEmission(uv, _EmissionColor.rgb, TEXTURE2D_ARGS(_EmissionMap, sampler_EmissionMap));

#if _IRIDESCENCE
    outSurfaceData.iridescenceThickness = SampleIridescenceThickness(uv);
    outSurfaceData.iridescenceEta2 = _IridescneceEta2;
    outSurfaceData.iridescenceEta3 = _IridescneceEta3;
    outSurfaceData.iridescenceKappa3 = _IridescneceKappa3;
#endif
}

#endif // UNIVERSAL_IRIDESCENCE_LIT_INPUT_INCLUDED