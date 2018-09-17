﻿// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

Shader "Ocean/Underwater Skirt"
{
	Properties
	{
		_Diffuse("Diffuse", Color) = (0.2, 0.05, 0.05, 1.0)
		[Toggle] _SubSurfaceScattering("Sub-Surface Scattering", Float) = 1
		_SubSurfaceColour("    Colour", Color) = (0.0, 0.48, 0.36)
		_SubSurfaceBase("    Base Mul", Range(0.0, 2.0)) = 0.6
		_SubSurfaceSun("    Sun Mul", Range(0.0, 10.0)) = 0.8
		_SubSurfaceSunFallOff("    Sun Fall-Off", Range(1.0, 16.0)) = 4.0
		[Toggle] _SubSurfaceHeightLerp("Sub-Surface Scattering Height Lerp", Float) = 1
		_SubSurfaceHeightMax("    Height Max", Range(0.0, 50.0)) = 3.0
		_SubSurfaceHeightPower("    Height Power", Range(0.01, 10.0)) = 1.0
		_SubSurfaceCrestColour("    Crest Colour", Color) = (0.42, 0.69, 0.52)
		[Toggle] _SubSurfaceShallowColour("Sub-Surface Shallow Colour", Float) = 1
		_SubSurfaceDepthMax("    Depth Max", Range(0.01, 50.0)) = 3.0
		_SubSurfaceDepthPower("    Depth Power", Range(0.01, 10.0)) = 1.0
		_SubSurfaceShallowCol("    Shallow Colour", Color) = (0.42, 0.75, 0.69)
		[Toggle] _Transparency("Transparency", Float) = 1
		_DepthFogDensity("    Density", Vector) = (0.28, 0.16, 0.24, 1.0)
		[Toggle] _Caustics("Caustics", Float) = 1
		[NoScaleOffset] _CausticsTexture("    Caustics", 2D) = "black" {}
		_CausticsTextureScale("    Scale", Range(0.0, 25.0)) = 5.0
		_CausticsTextureAverage("    Texture Average Value", Range(0.0, 1.0)) = 0.07
		_CausticsStrength("    Strength", Range(0.0, 10.0)) = 3.2
		_CausticsFocalDepth("    Focal Depth", Range(0.0, 25.0)) = 2.0
		_CausticsDepthOfField("    Depth Of Field", Range(0.01, 10.0)) = 0.33
		_CausticsDistortionScale("    Distortion Scale", Range(0.01, 50.0)) = 10.0
		_CausticsDistortionStrength("    Distortion Strength", Range(0.0, 0.25)) = 0.075
		[Toggle] _Shadows("Shadows", Float) = 1
		[Toggle] _CompileShaderWithDebugInfo("Compile Shader With Debug Info (D3D11)", Float) = 0
	}

	SubShader
	{
		Tags{ "LightMode" = "ForwardBase" "Queue" = "Geometry+510" "IgnoreProjector" = "True" "RenderType" = "Opaque" }
		LOD 100

		GrabPass
		{
			"_BackgroundTexture"
		}

		Pass
		{
			// Could turn this off, and it would allow the ocean surface to render through it
			ZWrite On

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#pragma shader_feature _SUBSURFACESCATTERING_ON
			#pragma shader_feature _SUBSURFACEHEIGHTLERP_ON
			#pragma shader_feature _SUBSURFACESHALLOWCOLOUR_ON
			#pragma shader_feature _TRANSPARENCY_ON
			#pragma shader_feature _CAUSTICS_ON
			#pragma shader_feature _SHADOWS_ON

			#pragma shader_feature _COMPILESHADERWITHDEBUGINFO_ON

			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "../../Crest/Shaders/OceanLODData.hlsl"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				half4 foam_screenPos : TEXCOORD1;
				half4 grabPos : TEXCOORD2;
				float3 worldPos : TEXCOORD3;
			};

			v2f vert (appdata v)
			{
				v2f o;

				// actually this should follow camera around
				float3 right   = mul((float3x3)unity_CameraToWorld, float3(1., 0., 0.));
				float3 up      = mul((float3x3)unity_CameraToWorld, float3(0., 1., 0.));
				float3 forward = mul((float3x3)unity_CameraToWorld, float3(0., 0., 1.));

				float3 center = _WorldSpaceCameraPos + forward * _ProjectionParams.y * 1.001;
				// todo - constant needs to depend on FOV
				o.worldPos = center
					+ 3. * right * v.vertex.x
					+ up * v.vertex.z;

				// isolate topmost edge
				if (v.vertex.z > 0.45)
				{
					half2 nxz_dummy = (half2)0.;

					float2 sampleXZ = o.worldPos.xz;
					float3 disp;
					for (int i = 0; i < 6; i++)
					{
						// sample displacement textures, add results to current world pos / normal / foam
						disp = float3(sampleXZ.x, _OceanCenterPosWorld.y, sampleXZ.y);
						SampleDisplacements(_LD_Sampler_AnimatedWaves_0, LD_0_WorldToUV(sampleXZ), 1.0, _LD_Params_0.w, _LD_Params_0.x, disp, nxz_dummy);
						float3 nearestPointOnUp = o.worldPos + up * dot(disp - o.worldPos, up);
						float2 error = disp.xz - nearestPointOnUp.xz;
						sampleXZ -= error;
					}

					o.worldPos = disp;

					// small fudge to lift up geom a bit and cover any cracks. it will render UNDER the ocean so any overlap will be covered
					o.worldPos += .02 * up;
				}
				else
				{
					// bottom row of verts - push them down a bunch
					o.worldPos -= 8. * up;
				}

				// view-projection
				o.vertex = mul(UNITY_MATRIX_VP, float4(o.worldPos, 1.));
				o.vertex.w = 1.;
				o.vertex.z = 1.;

				o.foam_screenPos.yzw = ComputeScreenPos(o.vertex).xyw;
				o.foam_screenPos.x = 0.;
				o.grabPos = ComputeGrabScreenPos(o.vertex);

				o.uv = v.uv;

				return o;
			}
			
			#include "OceanEmission.hlsl"
			uniform sampler2D _CameraDepthTexture;
			uniform sampler2D _Normals;

			half4 frag(v2f i) : SV_Target
			{
				half3 view = normalize(_WorldSpaceCameraPos - i.worldPos);

				float pixelZ = LinearEyeDepth(i.vertex.z);
				half3 screenPos = i.foam_screenPos.yzw;
				half2 uvDepth = screenPos.xy / screenPos.z;
				float sceneZ01 = tex2D(_CameraDepthTexture, uvDepth).x;
				float sceneZ = LinearEyeDepth(sceneZ01);
				
				float3 lightDir = _WorldSpaceLightPos0.xyz;
				half shadow = 1.;
				half3 bubbleCol = 0.;
				half3 col = OceanEmission(i.worldPos, 3. /*i.lodAlpha_worldXZUndisplaced_oceanDepth.w*/, view, (half3)0. /*n_pixel*/, (half3)0. /*n_geom*/, lightDir, shadow.x, i.grabPos, screenPos, pixelZ, uvDepth, sceneZ, sceneZ01, bubbleCol, _Normals, _CameraDepthTexture);

				// create a fake darkening at the air-water interface
				col *= lerp(1., saturate((.9998 - i.uv.y) / .001), .2);

				return half4(col, 1.);
			}
			ENDCG
		}
	}
}