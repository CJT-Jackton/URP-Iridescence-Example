using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Scripting.APIUpdating;

namespace UnityEditor.Rendering.Universal.ShaderGUI
{
    public static class LitGUIIridescence
    {
        public enum WorkflowMode
        {
            Specular = 0,
            Metallic
        }

        public enum SmoothnessMapChannel
        {
            SpecularMetallicAlpha,
            AlbedoAlpha,
        }

        public static class Styles
        {
            public static GUIContent workflowModeText = new GUIContent("Workflow Mode",
                "Select a workflow that fits your textures. Choose between Metallic or Specular.");

            public static GUIContent specularMapText =
                new GUIContent("Specular Map", "Sets and configures the map and color for the Specular workflow.");

            public static GUIContent metallicMapText =
                new GUIContent("Metallic Map", "Sets and configures the map for the Metallic workflow.");

            public static GUIContent smoothnessText = new GUIContent("Smoothness",
                "Controls the spread of highlights and reflections on the surface.");

            public static GUIContent smoothnessMapChannelText =
                new GUIContent("Source",
                    "Specifies where to sample a smoothness map from. By default, uses the alpha channel for your map.");

            public static GUIContent highlightsText = new GUIContent("Specular Highlights",
                "When enabled, the Material reflects the shine from direct lighting.");

            public static GUIContent reflectionsText =
                new GUIContent("Environment Reflections",
                    "When enabled, the Material samples reflections from the nearest Reflection Probes or Lighting Probe.");

            public static GUIContent occlusionText = new GUIContent("Occlusion Map",
                "Sets an occlusion map to simulate shadowing from ambient lighting.");

            public static readonly string[] metallicSmoothnessChannelNames = { "Metallic Alpha", "Albedo Alpha" };
            public static readonly string[] specularSmoothnessChannelNames = { "Specular Alpha", "Albedo Alpha" };

            public static GUIContent enableIridescenceText = new GUIContent("Iridescence", "Enable Iridescence");

            public static GUIContent iridescenceThicknessText = new GUIContent("Thickness",
                "Thickness of the thin-film. Unit is micrometer, mean 0.5 is 500nm.");

            public static GUIContent iridescenceThicknessMapText = new GUIContent("Thickness Map",
                "Specifies the Iridescence Thickness map (R) for this Material.");

            public static GUIContent iridescenceThicknessRemapText = new GUIContent("Remap",
                "Iridescence Thickness remap");

            public static GUIContent iridescenceEta2Text = new GUIContent("Thin-film IOR (η₂)",
                "Index of refraction of the thin-film.");

            public static GUIContent iridescenceEta3Text = new GUIContent("Base IOR (η₃)",
                "The real part of the index of refraction of the base layer. Refer to https://refractiveindex.info/ for more information.");

            public static GUIContent iridescenceKappa3Text = new GUIContent("Base IOR (κ₃)",
                "The imaginary part of the index of refraction of the base layer. Refer to https://refractiveindex.info/ for more information.");
        }

        public struct LitProperties
        {
            // Surface Option Props
            public MaterialProperty workflowMode;

            // Surface Input Props
            public MaterialProperty metallic;
            public MaterialProperty specColor;
            public MaterialProperty metallicGlossMap;
            public MaterialProperty specGlossMap;
            public MaterialProperty smoothness;
            public MaterialProperty smoothnessMapChannel;
            public MaterialProperty bumpMapProp;
            public MaterialProperty bumpScaleProp;
            public MaterialProperty occlusionStrength;
            public MaterialProperty occlusionMap;

            // Advanced Props
            public MaterialProperty highlights;
            public MaterialProperty reflections;

            public MaterialProperty enableIridescence;
            public MaterialProperty iridescenceThickness;
            public MaterialProperty iridescenceThicknessMap;
            public MaterialProperty iridescenceThicknessRemap;
            public MaterialProperty iridescenceEta2;
            public MaterialProperty iridescenceEta3;
            public MaterialProperty iridescenceKappa3;

            public LitProperties(MaterialProperty[] properties)
            {
                // Surface Option Props
                workflowMode = BaseShaderGUI.FindProperty("_WorkflowMode", properties, false);
                // Surface Input Props
                metallic = BaseShaderGUI.FindProperty("_Metallic", properties);
                specColor = BaseShaderGUI.FindProperty("_SpecColor", properties, false);
                metallicGlossMap = BaseShaderGUI.FindProperty("_MetallicGlossMap", properties);
                specGlossMap = BaseShaderGUI.FindProperty("_SpecGlossMap", properties, false);
                smoothness = BaseShaderGUI.FindProperty("_Smoothness", properties, false);
                smoothnessMapChannel = BaseShaderGUI.FindProperty("_SmoothnessTextureChannel", properties, false);
                bumpMapProp = BaseShaderGUI.FindProperty("_BumpMap", properties, false);
                bumpScaleProp = BaseShaderGUI.FindProperty("_BumpScale", properties, false);
                occlusionStrength = BaseShaderGUI.FindProperty("_OcclusionStrength", properties, false);
                occlusionMap = BaseShaderGUI.FindProperty("_OcclusionMap", properties, false);
                // Advanced Props
                highlights = BaseShaderGUI.FindProperty("_SpecularHighlights", properties, false);
                reflections = BaseShaderGUI.FindProperty("_EnvironmentReflections", properties, false);
                // Iridescence Props
                enableIridescence = BaseShaderGUI.FindProperty("_EnableIridescence", properties, false);
                iridescenceThickness = BaseShaderGUI.FindProperty("_IridescenceThickness", properties, false);
                iridescenceThicknessMap = BaseShaderGUI.FindProperty("_IridescenceThicknessMap", properties, false);
                iridescenceThicknessRemap = BaseShaderGUI.FindProperty("_IridescenceThicknessRemap", properties, false);
                iridescenceEta2 = BaseShaderGUI.FindProperty("_IridescneceEta_2", properties, false);
                iridescenceEta3 = BaseShaderGUI.FindProperty("_IridescneceEta_3", properties, false);
                iridescenceKappa3 = BaseShaderGUI.FindProperty("_IridescneceKappa_3", properties, false);
            }
        }

        public static void Inputs(LitProperties properties, MaterialEditor materialEditor, Material material)
        {
            DoMetallicSpecularArea(properties, materialEditor, material);
            BaseShaderGUI.DrawNormalArea(materialEditor, properties.bumpMapProp, properties.bumpScaleProp);

            if (properties.occlusionMap != null)
            {
                materialEditor.TexturePropertySingleLine(Styles.occlusionText, properties.occlusionMap,
                    properties.occlusionMap.textureValue != null ? properties.occlusionStrength : null);
            }

            DoIridescence(properties, materialEditor);
        }

        public static void DoIridescence(LitProperties properties, MaterialEditor materialEditor)
        {
            materialEditor.ShaderProperty(properties.enableIridescence, Styles.enableIridescenceText);

            bool iridescence = properties.enableIridescence.floatValue == 1.0;
            bool hasThicknessMap = properties.iridescenceThicknessMap.textureValue != null;

            EditorGUI.BeginDisabledGroup(!iridescence);

            materialEditor.TexturePropertySingleLine(
                hasThicknessMap ? Styles.iridescenceThicknessMapText : Styles.iridescenceThicknessText,
                properties.iridescenceThicknessMap,
                hasThicknessMap ? properties.iridescenceThicknessRemap : properties.iridescenceThickness);

            EditorGUI.indentLevel++;
            materialEditor.ShaderProperty(properties.iridescenceEta2, Styles.iridescenceEta2Text);
            materialEditor.ShaderProperty(properties.iridescenceEta3, Styles.iridescenceEta3Text);
            materialEditor.ShaderProperty(properties.iridescenceKappa3, Styles.iridescenceKappa3Text);
            EditorGUI.indentLevel--;

            EditorGUI.EndDisabledGroup();
        }

        public static void DoMetallicSpecularArea(LitProperties properties, MaterialEditor materialEditor, Material material)
        {
            string[] smoothnessChannelNames;
            bool hasGlossMap = false;
            if (properties.workflowMode == null ||
                (WorkflowMode)properties.workflowMode.floatValue == WorkflowMode.Metallic)
            {
                hasGlossMap = properties.metallicGlossMap.textureValue != null;
                smoothnessChannelNames = Styles.metallicSmoothnessChannelNames;
                materialEditor.TexturePropertySingleLine(Styles.metallicMapText, properties.metallicGlossMap,
                    hasGlossMap ? null : properties.metallic);
            }
            else
            {
                hasGlossMap = properties.specGlossMap.textureValue != null;
                smoothnessChannelNames = Styles.specularSmoothnessChannelNames;
                BaseShaderGUI.TextureColorProps(materialEditor, Styles.specularMapText, properties.specGlossMap,
                    hasGlossMap ? null : properties.specColor);
            }
            EditorGUI.indentLevel++;
            DoSmoothness(properties, material, smoothnessChannelNames);
            EditorGUI.indentLevel--;
        }

        public static void DoSmoothness(LitProperties properties, Material material, string[] smoothnessChannelNames)
        {
            var opaque = ((BaseShaderGUI.SurfaceType)material.GetFloat("_Surface") ==
                          BaseShaderGUI.SurfaceType.Opaque);
            EditorGUI.indentLevel++;
            EditorGUI.BeginChangeCheck();
            EditorGUI.showMixedValue = properties.smoothness.hasMixedValue;
            var smoothness = EditorGUILayout.Slider(Styles.smoothnessText, properties.smoothness.floatValue, 0f, 1f);
            if (EditorGUI.EndChangeCheck())
                properties.smoothness.floatValue = smoothness;
            EditorGUI.showMixedValue = false;

            if (properties.smoothnessMapChannel != null) // smoothness channel
            {
                EditorGUI.indentLevel++;
                EditorGUI.BeginDisabledGroup(!opaque);
                EditorGUI.BeginChangeCheck();
                EditorGUI.showMixedValue = properties.smoothnessMapChannel.hasMixedValue;
                var smoothnessSource = (int)properties.smoothnessMapChannel.floatValue;
                if (opaque)
                    smoothnessSource = EditorGUILayout.Popup(Styles.smoothnessMapChannelText, smoothnessSource,
                        smoothnessChannelNames);
                else
                    EditorGUILayout.Popup(Styles.smoothnessMapChannelText, 0, smoothnessChannelNames);
                if (EditorGUI.EndChangeCheck())
                    properties.smoothnessMapChannel.floatValue = smoothnessSource;
                EditorGUI.showMixedValue = false;
                EditorGUI.EndDisabledGroup();
                EditorGUI.indentLevel--;
            }
            EditorGUI.indentLevel--;
        }

        public static SmoothnessMapChannel GetSmoothnessMapChannel(Material material)
        {
            int ch = (int)material.GetFloat("_SmoothnessTextureChannel");
            if (ch == (int)SmoothnessMapChannel.AlbedoAlpha)
                return SmoothnessMapChannel.AlbedoAlpha;

            return SmoothnessMapChannel.SpecularMetallicAlpha;
        }

        public static void SetMaterialKeywords(Material material)
        {
            // Note: keywords must be based on Material value not on MaterialProperty due to multi-edit & material animation
            // (MaterialProperty value might come from renderer material property block)
            var hasGlossMap = false;
            var isSpecularWorkFlow = false;
            var opaque = ((BaseShaderGUI.SurfaceType)material.GetFloat("_Surface") ==
                          BaseShaderGUI.SurfaceType.Opaque);
            if (material.HasProperty("_WorkflowMode"))
            {
                isSpecularWorkFlow = (WorkflowMode)material.GetFloat("_WorkflowMode") == WorkflowMode.Specular;
                if (isSpecularWorkFlow)
                    hasGlossMap = material.GetTexture("_SpecGlossMap") != null;
                else
                    hasGlossMap = material.GetTexture("_MetallicGlossMap") != null;
            }
            else
            {
                hasGlossMap = material.GetTexture("_MetallicGlossMap") != null;
            }

            CoreUtils.SetKeyword(material, "_SPECULAR_SETUP", isSpecularWorkFlow);

            CoreUtils.SetKeyword(material, "_METALLICSPECGLOSSMAP", hasGlossMap);

            if (material.HasProperty("_SpecularHighlights"))
                CoreUtils.SetKeyword(material, "_SPECULARHIGHLIGHTS_OFF",
                    material.GetFloat("_SpecularHighlights") == 0.0f);
            if (material.HasProperty("_EnvironmentReflections"))
                CoreUtils.SetKeyword(material, "_ENVIRONMENTREFLECTIONS_OFF",
                    material.GetFloat("_EnvironmentReflections") == 0.0f);
            if (material.HasProperty("_OcclusionMap"))
                CoreUtils.SetKeyword(material, "_OCCLUSIONMAP", material.GetTexture("_OcclusionMap"));

            if (material.HasProperty("_SmoothnessTextureChannel"))
            {
                CoreUtils.SetKeyword(material, "_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A",
                    GetSmoothnessMapChannel(material) == SmoothnessMapChannel.AlbedoAlpha && opaque);
            }

            if (material.HasProperty("_EnableIridescence"))
                CoreUtils.SetKeyword(material, "_IRIDESCENCE", material.GetFloat("_EnableIridescence") == 1.0f);
            if (material.HasProperty("_IridescenceThicknessMap"))
                CoreUtils.SetKeyword(material, "_IRIDESCENCE_THICKNESSMAP", material.GetTexture("_IridescenceThicknessMap"));
        }
    }
}