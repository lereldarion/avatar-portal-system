// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

// Modifications made by Lereldarion (https://github.com/lereldarion/avatar-portal-system). MIT license.
// Modifications of an opaque standard shader to be portal-aware.
Shader "Lereldarion/Portal/Standard"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Albedo", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _Glossiness("Smoothness", Range(0.0, 1.0)) = 0.5
        _GlossMapScale("Smoothness Scale", Range(0.0, 1.0)) = 1.0
        [Enum(Metallic Alpha,0,Albedo Alpha,1)] _SmoothnessTextureChannel ("Smoothness texture channel", Float) = 0

        [Gamma] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _GlossyReflections("Glossy Reflections", Float) = 1.0

        _BumpScale("Scale", Float) = 1.0
        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}

        _Parallax ("Height Scale", Range (0.005, 0.08)) = 0.02
        _ParallaxMap ("Height Map", 2D) = "black" {}

        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}

        _EmissionColor("Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}

        _DetailMask("Detail Mask", 2D) = "white" {}

        _DetailAlbedoMap("Detail Albedo x2", 2D) = "grey" {}
        _DetailNormalMapScale("Scale", Float) = 1.0
        [Normal] _DetailNormalMap("Normal Map", 2D) = "bump" {}

        [Enum(UV0,0,UV1,1)] _UVSec ("UV Set for secondary textures", Float) = 0

        [NoScaleOffset] _Portal_State("Portal state texture", 2D) = "" {}

        // Blending state
        [HideInInspector] _Mode ("__mode", Float) = 0.0
        [HideInInspector] _SrcBlend ("__src", Float) = 1.0
        [HideInInspector] _DstBlend ("__dst", Float) = 0.0
        [HideInInspector] _ZWrite ("__zw", Float) = 1.0
    }

    CGINCLUDE
        #define UNITY_SETUP_BRDF_INPUT MetallicSetup

        #include "portal.hlsl"
        uniform Texture2D<uint4> _Portal_State;
        uniform float _VRChatCameraMode;
        uniform float _VRChatMirrorMode;
    ENDCG

    SubShader
    {
        Tags {
            "RenderType"="Opaque"
            "Queue" = "Geometry-164"
            "PerformanceChecks"="False"
        }
        LOD 300


        // ------------------------------------------------------------------
        //  Base forward pass (directional light, emission, lightmaps, ...)
        Pass
        {
            Name "FORWARD"
            Tags { "LightMode" = "ForwardBase" }

            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]

            CGPROGRAM
            #pragma target 5.0

            // -------------------------------------

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature_local _METALLICGLOSSMAP
            #pragma shader_feature_local _DETAIL_MULX2
            #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature_local _GLOSSYREFLECTIONS_OFF
            #pragma shader_feature_local _PARALLAXMAP

            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex vertBaseP
            #pragma fragment fragBaseP
            #include "UnityStandardCoreForward.cginc"

            VertexOutputForwardBase vertBaseP (VertexInput v, float2 puv_in : TEXCOORD7, out nointerpolation float2 puv_out : PORTAL_UV) {
                puv_out = puv_in;
                return vertBase(v);
            }
            half4 fragBaseP (VertexOutputForwardBase i, nointerpolation float2 portal_uv : PORTAL_UV) : SV_Target {
                half4 pixel = fragBase(i);
                pixel.a = portal_fragment_test(IN_WORLDPOS(i), portal_uv, _Portal_State, _VRChatCameraMode, _VRChatMirrorMode);
                return pixel;
            }

            ENDCG
        }
        // ------------------------------------------------------------------
        //  Additive forward pass (one light per pass)
        Pass
        {
            Name "FORWARD_DELTA"
            Tags { "LightMode" = "ForwardAdd" }
            Blend [_SrcBlend] One
            Fog { Color (0,0,0,0) } // in additive pass fog should be black
            ZWrite Off
            ZTest LEqual
            ColorMask RGB // leave alpha alone

            CGPROGRAM
            #pragma target 5.0

            // -------------------------------------


            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local _METALLICGLOSSMAP
            #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature_local _DETAIL_MULX2
            #pragma shader_feature_local _PARALLAXMAP

            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex vertAddP
            #pragma fragment fragAddP
            #include "UnityStandardCoreForward.cginc"

            VertexOutputForwardAdd vertAddP (VertexInput v, float2 puv_in : TEXCOORD7, out nointerpolation float2 puv_out : PORTAL_UV) {
                puv_out = puv_in;
                return vertAdd(v);
            }
            half4 fragAddP (VertexOutputForwardAdd i, nointerpolation float2 portal_uv : PORTAL_UV) : SV_Target {
                half4 pixel = fragAdd(i);
                portal_fragment_test(i.posWorld, portal_uv, _Portal_State, _VRChatCameraMode, _VRChatMirrorMode);
                return pixel;
            }

            ENDCG
        }
        // ------------------------------------------------------------------
        //  Shadow rendering pass
        Pass {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On ZTest LEqual

            CGPROGRAM
            #pragma target 5.0

            // -------------------------------------


            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local _METALLICGLOSSMAP
            #pragma shader_feature_local _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local _PARALLAXMAP
            #pragma multi_compile_shadowcaster
            #pragma multi_compile_instancing
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex vertShadowCasterP
            #pragma fragment fragShadowCasterP

            #include "UnityStandardShadow.cginc"

            // Portal : extracted from the above header and edited, too annoying to wrap
            VertexOutput vertShadowCasterP (VertexInput v
                #ifdef UNITY_STANDARD_USE_SHADOW_OUTPUT_STRUCT
                , out VertexOutputShadowCaster o
                #endif
                #ifdef UNITY_STANDARD_USE_STEREO_SHADOW_OUTPUT_STRUCT
                , out VertexOutputStereoShadowCaster os
                #endif
                , float2 puv_in : TEXCOORD7, out nointerpolation float2 puv_out : PORTAL_UV
                , out float3 world_pos : WORLD_POSITION
            )
            {
                VertexOutput output;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, output);

                #ifdef UNITY_STANDARD_USE_STEREO_SHADOW_OUTPUT_STRUCT
                    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(os);
                #endif
                TRANSFER_SHADOW_CASTER_NOPOS(o, output.pos)
                #if defined(UNITY_STANDARD_USE_SHADOW_UVS)
                    o.tex = TRANSFORM_TEX(v.uv0, _MainTex);

                    #ifdef _PARALLAXMAP
                        TANGENT_SPACE_ROTATION;
                        o.viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
                    #endif
                #endif

                puv_out = puv_in;
                world_pos = mul(unity_ObjectToWorld, v.vertex).xyz;

                return output;
            }

            half4 fragShadowCasterP (VertexOutput input
            #ifdef UNITY_STANDARD_USE_SHADOW_OUTPUT_STRUCT
                , VertexOutputShadowCaster i
            #endif
                , nointerpolation float2 portal_uv : PORTAL_UV, float3 world_pos : WORLD_POSITION
            ) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                portal_shadowcaster_test(world_pos, portal_uv, _Portal_State, _VRChatCameraMode, _VRChatMirrorMode);

                #if defined(UNITY_STANDARD_USE_SHADOW_UVS)
                    #if defined(_PARALLAXMAP) && (SHADER_TARGET >= 30)
                        half3 viewDirForParallax = normalize(i.viewDirForParallax);
                        fixed h = tex2D (_ParallaxMap, i.tex.xy).g;
                        half2 offset = ParallaxOffset1Step (h, _Parallax, viewDirForParallax);
                        i.tex.xy += offset;
                    #endif

                    #if defined(_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A)
                        half alpha = _Color.a;
                    #else
                        half alpha = tex2D(_MainTex, i.tex.xy).a * _Color.a;
                    #endif
                    #if defined(_ALPHATEST_ON)
                        clip (alpha - _Cutoff);
                    #endif
                    #if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
                        #if defined(_ALPHAPREMULTIPLY_ON)
                            half outModifiedAlpha;
                            PreMultiplyAlpha(half3(0, 0, 0), alpha, SHADOW_ONEMINUSREFLECTIVITY(i.tex), outModifiedAlpha);
                            alpha = outModifiedAlpha;
                        #endif
                        #if defined(UNITY_STANDARD_USE_DITHER_MASK)
                            // Use dither mask for alpha blended shadows, based on pixel position xy
                            // and alpha level. Our dither texture is 4x4x16.
                            #ifdef LOD_FADE_CROSSFADE
                                #define _LOD_FADE_ON_ALPHA
                                alpha *= unity_LODFade.y;
                            #endif
                            half alphaRef = tex3D(_DitherMaskLOD, float3(input.pos.xy*0.25,alpha*0.9375)).a;
                            clip (alphaRef - 0.01);
                        #else
                            clip (alpha - _Cutoff);
                        #endif
                    #endif
                #endif // #if defined(UNITY_STANDARD_USE_SHADOW_UVS)

                #ifdef LOD_FADE_CROSSFADE
                    #ifdef _LOD_FADE_ON_ALPHA
                        #undef _LOD_FADE_ON_ALPHA
                    #else
                        UnityApplyDitherCrossFade(input.pos.xy);
                    #endif
                #endif

                SHADOW_CASTER_FRAGMENT(i)
            }

            ENDCG
        }
    }

    CustomEditor "StandardShaderGUI"
}
