
Shader "Lereldarion/Portal/DebugItem" {
    Properties {
        _Color("Color", Color) = (1, 1, 1, 0)

        [NoScaleOffset] _Portal_State("Portal state texture", 2D) = "" {}
    }
    SubShader {
        Tags {
            "Queue" = "Geometry-164"
            "PreviewType" = "Plane"
        }

        Pass {
            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing
            #pragma vertex vertex_stage
            #pragma fragment fragment_stage

            #include "UnityCG.cginc"
            #include "portal.hlsl"

            uniform Texture2D<uint4> _Portal_State;
            uniform float _VRChatCameraMode;
            uniform float _VRChatMirrorMode;
            
            struct MeshData {
                float3 position : POSITION;
                float2 portal_uv : TEXCOORD7;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct FragmentData  {
                float4 position : SV_POSITION;
                float3 world_position : WORLD_POSITION;
                nointerpolation float2 portal_uv : TEXCOORD7;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            void vertex_stage (MeshData input, out FragmentData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.world_position = mul(unity_ObjectToWorld, float4(input.position, 1)).xyz;
                output.position = UnityWorldToClipPos(output.world_position);
                output.portal_uv = input.portal_uv;
            }
            
            uniform half4 _Color;

            half4 fragment_stage (FragmentData input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                half portal_alpha_data = portal_fragment_test(
                    input.world_position, input.portal_uv,
                    _Portal_State, _VRChatCameraMode, _VRChatMirrorMode
                );
                
                return half4(_Color.rgb, portal_alpha_data);
            }
            ENDCG
        }
    }
}
