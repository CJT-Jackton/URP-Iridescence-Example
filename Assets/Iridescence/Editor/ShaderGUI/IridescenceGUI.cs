using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Scripting.APIUpdating;

namespace UnityEditor.Rendering.Universal.ShaderGUI
{
    public static class IridescenceGUI
    {
        public enum IridescenceMode
        {
            None = 0,
            ThinFilm = 1
        }

        public static class Styles
        {
            public static GUIContent iridescenceText = new GUIContent("Iridescence", "Select the iridescence mode.");

            public static GUIContent iridescenceThicknessText = new GUIContent("Thickness",
                "Thickness of the thin-film. Unit is micrometer, means 0.5 is 500nm.");

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

            public static readonly string[] iridescenceModeName = { "None", "Thin-film" };
        }

        public struct IridescenceProperties
        {
            public MaterialProperty iridescence;
            public MaterialProperty iridescenceThickness;
            public MaterialProperty iridescenceThicknessMap;
            public MaterialProperty iridescenceThicknessRemap;
            public MaterialProperty iridescenceEta2;
            public MaterialProperty iridescenceEta3;
            public MaterialProperty iridescenceKappa3;

            public IridescenceProperties(MaterialProperty[] properties)
            {
                iridescence = BaseShaderGUI.FindProperty("_Iridescence", properties, false);
                iridescenceThickness = BaseShaderGUI.FindProperty("_IridescenceThickness", properties, false);
                iridescenceThicknessMap = BaseShaderGUI.FindProperty("_IridescenceThicknessMap", properties, false);
                iridescenceThicknessRemap = BaseShaderGUI.FindProperty("_IridescenceThicknessRemap", properties, false);
                iridescenceEta2 = BaseShaderGUI.FindProperty("_IridescneceEta2", properties, false);
                iridescenceEta3 = BaseShaderGUI.FindProperty("_IridescneceEta3", properties, false);
                iridescenceKappa3 = BaseShaderGUI.FindProperty("_IridescneceKappa3", properties, false);
            }
        }

        public static void DoIridescenceArea(IridescenceProperties properties, MaterialEditor materialEditor)
        {
            EditorGUI.BeginChangeCheck();
            var iridescenceMode = (int)properties.iridescence.floatValue;
            iridescenceMode = EditorGUILayout.Popup(Styles.iridescenceText, iridescenceMode, Styles.iridescenceModeName);
            if (EditorGUI.EndChangeCheck())
                properties.iridescence.floatValue = iridescenceMode;

            if ((IridescenceMode)iridescenceMode == IridescenceMode.ThinFilm)
            {
                bool hasThicknessMap = properties.iridescenceThicknessMap.textureValue != null;
                materialEditor.TexturePropertySingleLine(
                hasThicknessMap ? Styles.iridescenceThicknessMapText : Styles.iridescenceThicknessText,
                properties.iridescenceThicknessMap,
                hasThicknessMap ? properties.iridescenceThicknessRemap : properties.iridescenceThickness);
                
                EditorGUI.indentLevel++;
                materialEditor.ShaderProperty(properties.iridescenceEta2, Styles.iridescenceEta2Text);
                materialEditor.ShaderProperty(properties.iridescenceEta3, Styles.iridescenceEta3Text);
                materialEditor.ShaderProperty(properties.iridescenceKappa3, Styles.iridescenceKappa3Text);
                EditorGUI.indentLevel--;
            }
        }

        public static void SetMaterialKeywords(Material material)
        {
            if (material.HasProperty("_Iridescence"))
            {
                IridescenceMode iridescenceMode = (IridescenceMode)material.GetFloat("_Iridescence");

                CoreUtils.SetKeyword(material, "_IRIDESCENCE", iridescenceMode == IridescenceMode.ThinFilm);
            }

            //if (material.HasProperty("_EnableIridescence"))
            //    CoreUtils.SetKeyword(material, "_IRIDESCENCE", material.GetFloat("_EnableIridescence") == 1.0f);

            if (material.HasProperty("_IridescenceThicknessMap"))
                CoreUtils.SetKeyword(material, "_IRIDESCENCE_THICKNESSMAP", material.GetTexture("_IridescenceThicknessMap"));
        }
    }
}