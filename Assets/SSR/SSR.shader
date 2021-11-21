Shader "Hidden/ScreenSpaceReflections"
{
    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

    struct Attributes
    {
        float4 positionHCS   : POSITION;
        float2 uv           : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4  positionCS  : SV_POSITION;
        float2  uv          : TEXCOORD0;
        UNITY_VERTEX_OUTPUT_STEREO
    };

    Varyings VertDefault(Attributes input)
    {
        Varyings output;
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

        output.positionCS = float4(input.positionHCS.xy , 1.0, 1.0);

#if UNITY_UV_STARTS_AT_TOP
        output.positionCS.y *= -1;
#endif

        output.uv = input.uv;
        // Add a small epsilon to avoid artifacts when reconstructing the normals
        output.uv += 1.0e-6;

        return output;
    }

    ENDHLSL

    SubShader
    {
        Tags{ "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            Name "SSR"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma exclude_renderers d3d11_9x
            #pragma exclude_renderers d3d9
            #pragma vertex VertDefault
            #pragma fragment SSR
            #include "./SSR.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "SSR_APPLY"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma exclude_renderers d3d11_9x
            #pragma exclude_renderers d3d9
            #pragma vertex VertDefault
            #pragma fragment SSR_APPLY
            #include "./SSR.hlsl"
            ENDHLSL
        }
    }
}
