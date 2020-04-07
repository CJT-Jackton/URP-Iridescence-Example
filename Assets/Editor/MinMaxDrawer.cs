using UnityEditor;
using UnityEngine;

public class MinMaxDrawer : MaterialPropertyDrawer
{
    private float minLimit;
    private float maxLimit;

    public MinMaxDrawer(float min = 0f, float max = 1f)
    {
        this.minLimit = min;
        this.maxLimit = max;
    }

    public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
    {
        if (prop.type != MaterialProperty.PropType.Vector)
        {
            GUIContent c = EditorGUIUtility.TrTextContentWithIcon("MinMax used on a non-vector property: " + prop.name,
                MessageType.Warning);
            EditorGUI.LabelField(position, c, EditorStyles.helpBox);
            return;
        }

        int sliderId = GUIUtility.GetControlID("EditorSliderKnob".GetHashCode(), FocusType.Passive, position);
        int id = GUIUtility.GetControlID("EditorMinMaxSlider".GetHashCode(), FocusType.Keyboard, position);

        if (GUIUtility.keyboardControl == id)
        {
            GUIUtility.keyboardControl = sliderId;
        }

        float minValue = prop.vectorValue.x;
        float maxValue = prop.vectorValue.y;

        // Whether draw the label or not
        bool drawLabel = label != string.Empty;

        // Width of the input field and spacing
        float floatFieldWidth = EditorGUIUtility.fieldWidth;
        float kSpacing = 5f;
        
        // Rect of properties fields
        Rect minRect, maxRect, sliderRect;
        Rect labelRect = new Rect(position) { width = EditorGUIUtility.labelWidth };

        // The width of indent
        float indentWidth = labelRect.width - EditorGUI.IndentedRect(labelRect).width;

        // Handle with or without label
        if (drawLabel)
        {
            labelRect = EditorGUI.IndentedRect(labelRect);

            minRect = new Rect(position)
            {
                x = labelRect.x + labelRect.width - indentWidth,
                width = floatFieldWidth + indentWidth
            };
        }
        else
        {
            labelRect = new Rect(0, 0, 0, 0);

            minRect = new Rect(position)
            {
                width = floatFieldWidth
            };
        }

        sliderRect = new Rect(position)
        {
            x = minRect.x + floatFieldWidth + kSpacing,
            width = position.width - labelRect.width - 2 * (floatFieldWidth + kSpacing)
        };

        maxRect = new Rect(position)
        { 
            x = sliderRect.x + sliderRect.width + kSpacing - indentWidth,
            width = floatFieldWidth + indentWidth
        };

        // Draw label
        GUI.Label(labelRect, new GUIContent(label), EditorStyles.label);
        //EditorGUI.LabelField(labelRect, new GUIContent(label));
       
        EditorGUI.BeginChangeCheck();

        // Draw float field of min and max value
        minValue = EditorGUI.DelayedFloatField(minRect, GUIContent.none, minValue);
        maxValue = EditorGUI.DelayedFloatField(maxRect, GUIContent.none, maxValue);
        // Draw min max slider
        EditorGUI.MinMaxSlider(sliderRect, GUIContent.none, ref minValue, ref maxValue, minLimit, maxLimit);

        if (EditorGUI.EndChangeCheck())
        {
            // Clamp the input value
            minValue = minValue < maxValue ? minValue : maxValue;
            minValue = Mathf.Clamp(minValue, minLimit, maxValue);
            maxValue = Mathf.Clamp(maxValue, minValue, maxLimit);

            prop.vectorValue = new Vector2(minValue, maxValue);
        }
    }
}
