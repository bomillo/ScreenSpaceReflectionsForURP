#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

TEXTURE2D_X(_BaseMap);
TEXTURE2D_X(_SSR_Texture);

SAMPLER(sampler_BaseMap);
SAMPLER(sampler_SSR_Texture);

float4 _SSR_Params1;
float4 _SSR_Params2;

/*
 float3 _WorldSpaceCameraPos;

     x = orthographic camera's width
     y = orthographic camera's height
     z = unused
     w = 1.0 if camera is ortho, 0.0 if perspective
 float4 unity_OrthoParams;

     x = 1 or -1 (-1 if projection is flipped)
     y = near plane
     z = far plane
     w = 1/far plane
 float4 _ProjectionParams;

     x = width
     y = height
     z = 1 + 1.0/width
     w = 1 + 1.0/height
 float4 _ScreenParams;


 float4 _Time; // (t/20, t, t*2, t*3)
*/

#define INTENSITY _SSR_Params1.x
#define FALLOFF _SSR_Params1.y
#define MAXDISTANCE _SSR_Params1.z
#define RESOLUTION _SSR_Params1.w
#define DISQ (_SSR_Params2.z/100.0)

#define CAMERAWIDTH unity_OrthoParams.x
#define CAMERAHEIGHT unity_OrthoParams.y
#define ISORTHO unity_OrthoParams.w==1.0?true:false
#define FARPLANE _ProjectionParams.z
#define NEARPLANE _ProjectionParams.y

#define SCREENWIDTH _ScreenParams.x
#define SCREENHEIGHT _ScreenParams.y

#define SAMPLE_BASEMAP(uv)   SAMPLE_TEXTURE2D_X(_BaseMap, sampler_BaseMap, UnityStereoTransformScreenSpaceTex(uv))
#define SAMPLE_SSR(uv)   SAMPLE_TEXTURE2D_X(_SSR_Texture, sampler_SSR_Texture, UnityStereoTransformScreenSpaceTex(uv))

#define PI2 (PI/2.0f)

float Depth(float2 uv) {
    return SampleSceneDepth(uv).r;
}

float DepthScaled(float2 uv) {
    return ((1.0-Depth(uv))*(FARPLANE-NEARPLANE))+NEARPLANE;
}

float4 Color(float2 uv) {
    return SAMPLE_BASEMAP(uv);
}

uint2 UVtoScreenPixel(float2 uv) {
    return uint2((uint)(uv.x * SCREENWIDTH), (uint)(uv.y * SCREENHEIGHT));
}

float4 Reflect(float2 uv) {
    float3 normal = SampleSceneNormals(uv).xyz;
    float angle =-( PI2 - (2 * asin(length(normal.xy) + 0.0001)));


    float depth = DepthScaled(uv);
    float distance = 0;

    float lastDepth = 0;
    float currDepth = depth;


    float distanceDelta = MAXDISTANCE / RESOLUTION;
    float depthDelta = sin(angle) * distanceDelta;
    float screenDistanceDeltaMag = distanceDelta * cos(angle);
    float2 screenDistanceDelta = screenDistanceDeltaMag * normalize(normal.xy);

    depth += depthDelta;
    uv += screenDistanceDelta / (CAMERAHEIGHT * 2.0);

    lastDepth = currDepth;
    currDepth = DepthScaled(uv);

    [loop] for (uint i = 0; i < uint(RESOLUTION) && uv.y<1.0; i++) {
        if (depth > DepthScaled(uv)) {
            
            if (currDepth-lastDepth  > -DISQ){
                return float4(Color(uv).rgb, pow(0.5, distance * FALLOFF));
            }
            else {
                return float4(0, 0, 0, 0);

            }
        }

        distance += distanceDelta;
        depth += depthDelta;
        uv += screenDistanceDelta / (CAMERAHEIGHT * 2.0);

        lastDepth = currDepth;
        currDepth = DepthScaled(uv);
    }

    return float4(0, 0, 0, 0);
}


float4 Main(float2 uv){
    float camAngle =  asin(abs(normalize(mul((float3x3)unity_CameraToWorld, float3(0, 0, 1))).y));

    float minY = _WorldSpaceCameraPos.y - unity_OrthoParams.y * sin(PI2 - camAngle);
    float maxY = _WorldSpaceCameraPos.y + unity_OrthoParams.y * sin(PI2 - camAngle);
    float currentY = lerp(minY, maxY, uv.y);

    float depthToPlane = currentY / sin(camAngle);
    if (abs(depthToPlane - DepthScaled(uv)) >0.001f) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    int2 pixel = UVtoScreenPixel(uv);
    if (pixel.y == SCREENHEIGHT-1 || pixel.y==0) {
        return float4(0.0, 0.0, 0, 0.0);
    }

    return Reflect(uv);
}


float4 SSR(Varyings input) : SV_Target
{
    float2 uv = input.uv;
    float4 color = SAMPLE_BASEMAP(uv);
    float4 reflection = Main(uv);

    if (reflection.a!= 0) {
        return reflection;
    }
    return float4(0,0,0,0);
}

float4 SSR_APPLYWITHBLUR(Varyings input) : SV_Target
{
    float2 uv = input.uv;
    float4 color = SAMPLE_BASEMAP(uv);
    float4 reflection = SAMPLE_SSR(uv);

    return color + reflection* reflection.a * INTENSITY;
}


