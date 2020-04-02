#ifndef UNIVERSAL_LIGHTING_IRIDESCENCE_INCLUDED
#define UNIVERSAL_LIGHTING_IRIDESCENCE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

///////////////////////////////////////////////////////////////////////////////
//                         Helper Functions                                  //
///////////////////////////////////////////////////////////////////////////////

// Common constants
#define PI 3.14159265358979323846

// XYZ to CIE 1931 RGB color space (using neutral E illuminant)
static const half3x3 XYZ_TO_RGB = half3x3(2.3706743, -0.5138850, 0.0052982, -0.9000405, 1.4253036, -0.0146949, -0.4706338, 0.0885814, 1.0093968);

// Square functions for cleaner code
inline float sqr(float x) { return x * x; }
inline float2 sqr(float2 x) { return x * x; }

// Depolarization functions for natural light
inline float depol(float2 polV) { return 0.5 * (polV.x + polV.y); }
inline float3 depolColor(float3 colS, float3 colP) { return 0.5 * (colS + colP); }

// Evaluation XYZ sensitivity curves in Fourier space
float3 evalSensitivity(float opd, float shift) {

    // Use Gaussian fits, given by 3 parameters: val, pos and var
    float phase = 2 * PI * opd * 1.0e-6;
    float3 val = float3(5.4856e-13, 4.4201e-13, 5.2481e-13);
    float3 pos = float3(1.6810e+06, 1.7953e+06, 2.2084e+06);
    float3 var = float3(4.3278e+09, 9.3046e+09, 6.6121e+09);
    float3 xyz = val * sqrt(2.0 * PI * var) * cos(pos * phase + shift) * exp(-var * phase * phase);
    xyz.x += 9.7470e-14 * sqrt(2.0 * PI * 4.5282e+09) * cos(2.2399e+06 * phase + shift) * exp(-4.5282e+09 * phase * phase);
    return xyz / 1.0685e-7;
}

///////////////////////////////////////////////////////////////////////////////
//                         BRDF Functions                                    //
///////////////////////////////////////////////////////////////////////////////

struct BRDFDataAdvanced
{
    half3 diffuse;
    half3 specular;
    half perceptualRoughness;
    half roughness;
    half roughness2;
    half grazingTerm;

    // We save some light invariant BRDF terms so we don't have to recompute
    // them in the light loop. Take a look at DirectBRDF function for detailed explaination.
    half normalizationTerm;     // roughness * 4.0 + 2.0
    half roughness2MinusOne;    // roughness² - 1.0

#ifdef _IRIDESCENCE
    half iridescenceThickness;
    half iridescenceEta_2;
    half iridescenceEta_3;
    half iridescenceKappa_3;
#endif
};

inline void InitializeBRDFDataAdvanced(SurfaceDataAdvanced surfaceData, out BRDFDataAdvanced outBRDFData)
{
#ifdef _SPECULAR_SETUP
    half reflectivity = ReflectivitySpecular(surfaceData.specular);
    half oneMinusReflectivity = 1.0 - reflectivity;

    outBRDFData.diffuse = surfaceData.albedo * (half3(1.0h, 1.0h, 1.0h) - surfaceData.specular);
    outBRDFData.specular = surfaceData.specular;
#else

    half oneMinusReflectivity = OneMinusReflectivityMetallic(surfaceData.metallic);
    half reflectivity = 1.0 - oneMinusReflectivity;

    outBRDFData.diffuse = surfaceData.albedo * oneMinusReflectivity;
    outBRDFData.specular = lerp(kDieletricSpec.rgb, surfaceData.albedo, surfaceData.metallic);
#endif

    outBRDFData.grazingTerm = saturate(surfaceData.smoothness + reflectivity);
    outBRDFData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(surfaceData.smoothness);
    outBRDFData.roughness = max(PerceptualRoughnessToRoughness(outBRDFData.perceptualRoughness), HALF_MIN);
    outBRDFData.roughness2 = outBRDFData.roughness * outBRDFData.roughness;

    outBRDFData.normalizationTerm = outBRDFData.roughness * 4.0h + 2.0h;
    outBRDFData.roughness2MinusOne = outBRDFData.roughness2 - 1.0h;

#ifdef _IRIDESCENCE
    outBRDFData.iridescenceThickness = surfaceData.iridescenceThickness;
    outBRDFData.iridescenceEta_2 = surfaceData.iridescenceEta_2;
    outBRDFData.iridescenceEta_3 = surfaceData.iridescenceEta_3;
    outBRDFData.iridescenceKappa_3 = surfaceData.iridescenceKappa_3;
#endif

#ifdef _ALPHAPREMULTIPLY_ON
    outBRDFData.diffuse *= surfaceData.alpha;
    surfaceData.alpha = surfaceData.alpha * oneMinusReflectivity + reflectivity;
#endif
}

// GGX distribution function
float GGX(float NdotH, float a) {
    float a2 = sqr(a);
    return a2 / (PI * sqr(sqr(NdotH) * (a2 - 1) + 1));
}

// Smith GGX geometric functions
float smithG1_GGX(float NdotV, float a) {
    float a2 = sqr(a);
    return 2 / (1 + sqrt(1 + a2 * (1 - sqr(NdotV)) / sqr(NdotV)));
}

float smithG_GGX(float NdotL, float NdotV, float a) {
    return smithG1_GGX(NdotL, a) * smithG1_GGX(NdotV, a);
}


// Fresnel equations for dielectric/dielectric interfaces.
void fresnelDielectric(in float ct1, in float n1, in float n2,
    out float2 R, out float2 phi) {

    float st1 = (1 - ct1 * ct1); // Sinus theta1 'squared'
    float nr = n1 / n2;

    if (sqr(nr) * st1 > 1) { // Total reflection

        float2 R = float2(1, 1);
        phi = 2.0 * atan(float2(-sqr(nr) * sqrt(st1 - 1.0 / sqr(nr)) / ct1,
            -sqrt(st1 - 1.0 / sqr(nr)) / ct1));
    }
    else {   // Transmission & Reflection

        float ct2 = sqrt(1 - sqr(nr) * st1);
        float2 r = float2((n2 * ct1 - n1 * ct2) / (n2 * ct1 + n1 * ct2),
            (n1 * ct1 - n2 * ct2) / (n1 * ct1 + n2 * ct2));
        phi.x = (r.x < 0.0) ? PI : 0.0;
        phi.y = (r.y < 0.0) ? PI : 0.0;
        R = sqr(r);
    }
}

// Fresnel equations for dielectric/conductor interfaces.
void fresnelConductor(in float ct1, in float n1, in float n2, in float k,
    out float2 R, out float2 phi) {

    if (k == 0) { // use dielectric formula to avoid numerical issues
        fresnelDielectric(ct1, n1, n2, R, phi);
        return;
    }

    float A = sqr(n2) * (1 - sqr(k)) - sqr(n1) * (1 - sqr(ct1));
    float B = sqrt(sqr(A) + sqr(2 * sqr(n2) * k));
    float U = sqrt((A + B) / 2.0);
    float V = sqrt((B - A) / 2.0);

    R.y = (sqr(n1 * ct1 - U) + sqr(V)) / (sqr(n1 * ct1 + U) + sqr(V));
    phi.y = atan2(sqr(U) + sqr(V) - sqr(n1 * ct1), 2 * n1 * V * ct1) + PI;

    R.x = (sqr(sqr(n2) * (1 - sqr(k)) * ct1 - n1 * U) + sqr(2 * sqr(n2) * k * ct1 - n1 * V))
        / (sqr(sqr(n2) * (1 - sqr(k)) * ct1 + n1 * U) + sqr(2 * sqr(n2) * k * ct1 + n1 * V));
    phi.x = atan2(sqr(sqr(n2) * (1 + sqr(k)) * ct1) - sqr(n1) * (sqr(U) + sqr(V)), 2 * n1 * sqr(n2) * ct1 * (2 * k * U - (1 - sqr(k)) * V));
}

half3 EnvironmentBRDFIridescence(BRDFDataAdvanced brdfData, half3 indirectDiffuse, half3 indirectSpecular, half3 fresnelIridescent)
{
    half3 c = indirectDiffuse * brdfData.diffuse;
    float surfaceReduction = 1.0 / (brdfData.roughness2 + 1.0);
    c += surfaceReduction * indirectSpecular * lerp(brdfData.specular * fresnelIridescent, brdfData.grazingTerm, fresnelIridescent);
    return c;
}

#ifdef _IRIDESCENCE
// Evaluate the reflectance for a thin-film layer on top of a dielectric medum
// Based on the paper [LAURENT 2017] A Practical Extension to Microfacet Theory for the Modeling of Varying Iridescence
half3 Iridescence(BRDFDataAdvanced brdfData, InputDataAdvanced inputData, half3 lightDirectionWS)
{
    // iridescenceThickness unit is micrometer for this equation here. Mean 0.5 is 500nm.
    float Dinc = brdfData.iridescenceThickness;

    float eta_1 = 1.0; // Air on top, no coat.
    float eta_2 = brdfData.iridescenceEta_2;
    float eta_3 = brdfData.iridescenceEta_3;
    float kappa_3 = brdfData.iridescenceKappa_3;

    // Force eta_2 -> eta_1 when Dinc -> 0.0
    eta_2 = lerp(eta_1, eta_2, smoothstep(0.0, 0.03, Dinc));

    // Compute dot products
    float NdotL = dot(inputData.normalWS, lightDirectionWS);
    float NdotV = dot(inputData.normalWS, inputData.viewDirectionWS);

    //if (NdotL < 0 || NdotV < 0) return half3(0, 0, 0);

    half3 halfDir = SafeNormalize(lightDirectionWS + inputData.viewDirectionWS);
    float NdotH = dot(inputData.normalWS, halfDir);
    float cosTheta1 = dot(halfDir, lightDirectionWS);

    float sinTheta2Sq = sqr(eta_1 / eta_2) * (1.0 - sqr(cosTheta1));
    float cosTheta2Sq = (1.0 - sinTheta2Sq);

    float cosTheta2 = sqrt(1.0 - sqr(eta_1 / eta_2) * (1 - sqr(cosTheta1)));

    // First interface
    float2 R12, phi12;
    fresnelDielectric(cosTheta1, eta_1, eta_2, R12, phi12);
    float2 R21 = R12;
    float2 T121 = float2(1.0, 1.0) - R12;
    float2 phi21 = float2(PI, PI) - phi12;

    // Second interface
    float2 R23, phi23;
    fresnelConductor(cosTheta2, eta_2, eta_3, kappa_3, R23, phi23);

    // Phase shift
    // float OPD = Dinc * cosTheta2;
    float OPD = 2 * eta_2 * brdfData.iridescenceThickness * cosTheta2;
    float2 phi2 = phi21 + phi23;

    // Compound terms
    float3 I = float3(0, 0, 0);
    float2 R123 = R12 * R23;
    float2 r123 = sqrt(R123);
    float2 Rs = sqr(T121) * R23 / (float2(1.0, 1.0) - R123);

    // Reflectance term for m=0 (DC term amplitude)
    float2 C0 = R12 + Rs;
    float3 S0 = evalSensitivity(0.0, 0.0);
    I += depol(C0) * S0;

    // Reflectance term for m>0 (pairs of diracs)
    float2 Cm = Rs - T121;

    [unroll(3)]
    for (int m = 1; m <= 3; ++m)
    {
        Cm *= r123;
        float3 SmS = 2.0 * evalSensitivity(m * OPD, m * phi2.x);
        float3 SmP = 2.0 * evalSensitivity(m * OPD, m * phi2.y);
        I += depolColor(Cm.x * SmS, Cm.y * SmP);
    }

    // Convert back to RGB reflectance
    I = clamp(mul(I, XYZ_TO_RGB), float3(0.0, 0.0, 0.0), float3(1.0, 1.0, 1.0));

    return I;
}

half3 DirectBDRFIridescence(BRDFDataAdvanced brdfData, InputDataAdvanced inputData, half3 lightDirectionWS)
{
    // Compute dot products
    float NdotL = dot(inputData.normalWS, lightDirectionWS);
    float NdotV = dot(inputData.normalWS, inputData.viewDirectionWS);

    float3 halfDir = SafeNormalize(float3(lightDirectionWS) + float3(inputData.viewDirectionWS));
    float NdotH = dot(inputData.normalWS, halfDir);

    half3 I = Iridescence(brdfData, inputData, lightDirectionWS);
    // Microfacet BRDF formula
    float D = GGX(NdotH, brdfData.perceptualRoughness);
    float G = smithG_GGX(NdotL, NdotV, brdfData.perceptualRoughness);

    half3 diffuseTerm = brdfData.diffuse;
    half3 specularTerm = D * G * I / (4 * NdotL * NdotV);
    
    half3 color = specularTerm * brdfData.specular + diffuseTerm;

    return color;
}
#endif

// Based on Minimalist CookTorrance BRDF
// Implementation is slightly different from original derivation: http://www.thetenthplanet.de/archives/255
//
// * NDF [Modified] GGX
// * Modified Kelemen and Szirmay-​Kalos for Visibility term
// * Fresnel approximated with 1/LdotH
half3 DirectBDRFAdvanced(BRDFDataAdvanced brdfData, InputDataAdvanced inputData, half3 lightDirectionWS)
{
#ifndef _SPECULARHIGHLIGHTS_OFF
    float3 halfDir = SafeNormalize(float3(lightDirectionWS) + float3(inputData.viewDirectionWS));

    float NoH = saturate(dot(inputData.normalWS, halfDir));
    half LoH = saturate(dot(lightDirectionWS, halfDir));

    // GGX Distribution multiplied by combined approximation of Visibility and Fresnel
    // BRDFspec = (D * V * F) / 4.0
    // D = roughness² / ( NoH² * (roughness² - 1) + 1 )²
    // V * F = 1.0 / ( LoH² * (roughness + 0.5) )
    // See "Optimizing PBR for Mobile" from Siggraph 2015 moving mobile graphics course
    // https://community.arm.com/events/1155

    // Final BRDFspec = roughness² / ( NoH² * (roughness² - 1) + 1 )² * (LoH² * (roughness + 0.5) * 4.0)
    // We further optimize a few light invariant terms
    // brdfData.normalizationTerm = (roughness + 0.5) * 4.0 rewritten as roughness * 4.0 + 2.0 to a fit a MAD.
    float d = NoH * NoH * brdfData.roughness2MinusOne + 1.00001f;

    half LoH2 = LoH * LoH;
    half specularTerm = brdfData.roughness2 / ((d * d) * max(0.1h, LoH2) * brdfData.normalizationTerm);
    half3 diffuseTerm = brdfData.diffuse;

    // on mobiles (where half actually means something) denominator have risk of overflow
    // clamp below was added specifically to "fix" that, but dx compiler (we convert bytecode to metal/gles)
    // sees that specularTerm have only non-negative terms, so it skips max(0,..) in clamp (leaving only min(100,...))
#if defined (SHADER_API_MOBILE)
    specularTerm = specularTerm - HALF_MIN;
    specularTerm = clamp(specularTerm, 0.0, 100.0); // Prevent FP16 overflow on mobiles
#endif

    half3 color = specularTerm * brdfData.specular + diffuseTerm;
    return color;
#else
    return brdfData.diffuse;
#endif
}

///////////////////////////////////////////////////////////////////////////////
//                      Global Illumination                                  //
///////////////////////////////////////////////////////////////////////////////

half3 GlobalIlluminationAdvanced(BRDFDataAdvanced brdfData, InputDataAdvanced inputData, half occlusion)
{
    half3 reflectVector = reflect(-inputData.viewDirectionWS, inputData.normalWS);

    half3 indirectDiffuse = inputData.bakedGI * occlusion;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, brdfData.perceptualRoughness, occlusion);

#ifdef _IRIDESCENCE
    half3 fresnelIridescent = Iridescence(brdfData, inputData, reflectVector);
    return EnvironmentBRDFIridescence(brdfData, indirectDiffuse, indirectSpecular, fresnelIridescent);

#else
    half fresnelTerm = Pow4(1.0 - saturate(dot(inputData.normalWS, inputData.viewDirectionWS)));
    return EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

#endif
}

///////////////////////////////////////////////////////////////////////////////
//                      Lighting Functions                                   //
///////////////////////////////////////////////////////////////////////////////

half3 LightingAdvanced(BRDFDataAdvanced brdfData, half3 lightColor, half3 lightDirectionWS, half lightAttenuation, InputDataAdvanced inputData)
{
    half NdotL = saturate(dot(inputData.normalWS, lightDirectionWS));
    half3 radiance = lightColor * (lightAttenuation * NdotL);

#if _IRIDESCENCE
    return DirectBDRFIridescence(brdfData, inputData, lightDirectionWS) * radiance;
#else
    return DirectBDRFAdvanced(brdfData, inputData, lightDirectionWS) * radiance;
#endif
}

half3 LightingAdvanced(BRDFDataAdvanced brdfData, Light light, InputDataAdvanced inputData)
{
    return LightingAdvanced(brdfData, light.color, light.direction, light.distanceAttenuation * light.shadowAttenuation, inputData);
}

///////////////////////////////////////////////////////////////////////////////
//                      Fragment Functions                                   //
//       Used by ShaderGraph and others builtin renderers                    //
///////////////////////////////////////////////////////////////////////////////
half4 UniversalFragmentAdvanced(InputDataAdvanced inputData, SurfaceDataAdvanced surfaceData)
{
    BRDFDataAdvanced brdfData;
    InitializeBRDFDataAdvanced(surfaceData, brdfData);

    Light mainLight = GetMainLight(inputData.shadowCoord);
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, half4(0, 0, 0, 0));

    half3 color = GlobalIlluminationAdvanced(brdfData, inputData, surfaceData.occlusion);
    color += LightingAdvanced(brdfData, mainLight, inputData);

#ifdef _ADDITIONAL_LIGHTS
    int pixelLightCount = GetAdditionalLightsCount();
    for (int i = 0; i < pixelLightCount; ++i)
    {
        Light light = GetAdditionalLight(i, inputData.positionWS);
        color += LightingAdvanced(brdfData, light, inputData);
    }
#endif

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    color += inputData.vertexLighting * brdfData.diffuse;
#endif

    color += surfaceData.emission;
    return half4(color, surfaceData.alpha);
}
#endif // UNIVERSAL_LIGHTING_IRIDESCENCE_INCLUDED
