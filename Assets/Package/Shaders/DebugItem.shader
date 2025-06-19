
Shader "Lereldarion/Portal/DebugItem" {
    Properties {
        _Color("Color", Color) = (1, 1, 1, 0)

        [Header(Portal)]
        [ToggleUI] _Camera_In_Portal("Camera is in portal space", Float) = 0
        _Item_Portal_State("Item portal state : 0=w,1=p,2+n=transiting_fwd,-2-n=transiting_back)", Integer) = 0
        [NoScaleOffset] _Portal_CRT("Portal CRT texture", 2D) = ""
    }
    SubShader {
        Tags {
            "Queue" = "Geometry"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        Pass {
            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            #pragma vertex vertex_stage
            #pragma fragment fragment_stage
            
            struct MeshData {
                float3 position : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct FragmentData  {
                float4 position : SV_POSITION;
                float3 world_position : WORLD_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            void vertex_stage (MeshData input, out FragmentData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.world_position = mul(unity_ObjectToWorld, float4(input.position, 1)).xyz;
                output.position = UnityWorldToClipPos(output.world_position);
            }
            
            uniform Texture2D<uint4> _Portal_CRT;
            #include "portal_crt.hlsl"

            uniform float _Camera_In_Portal;
            uniform int _Item_Portal_State;

            uniform half4 _Color;

            half4 fragment_stage (FragmentData input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                bool portal_parity = _Camera_In_Portal;
                bool in_portal_space = false;

                uint transiting_portal_id = 1000; // Not tested
                float transiting_direction = 1;

                if(_Item_Portal_State == 0) {
                    // World, do nothing
                } else if(_Item_Portal_State == 1) {
                    // Portal
                    portal_parity = !portal_parity;
                    in_portal_space = true;
                } else {
                    if (_Item_Portal_State < 0) {
                        transiting_direction = -1;
                        transiting_portal_id = 2 - _Item_Portal_State;
                    } else {
                        transiting_portal_id = _Item_Portal_State - 2;
                    }
                }

                [loop]
                for(uint index = 0; index < 32; index += 1) {
                    PortalPixel0 p0 = PortalPixel0::decode(_Portal_CRT, index);
                    if(!p0.is_enabled()) { break; }
                    if(!p0.fast_intersect(_WorldSpaceCameraPos, input.world_position)) { continue; }
                    Portal portal = Portal::decode(p0, _Portal_CRT, index);

                    if(portal.segment_intersect(_WorldSpaceCameraPos, input.world_position)) {
                        portal_parity = !portal_parity;
                    }

                    if(index == transiting_portal_id) {
                        if(dot(input.world_position - portal.position, portal.normal) * transiting_direction >= 0) {
                            portal_parity = !portal_parity;
                            in_portal_space = true;
                        }
                    }
                }

                if(portal_parity) { discard; }
                
                return _Color;
            }
            ENDCG
        }
    }
}
