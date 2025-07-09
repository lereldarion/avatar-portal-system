
Shader "Lereldarion/Portal/DebugItem" {
    Properties {
        _Color("Color", Color) = (1, 1, 1, 0)

        [Header(Portal)]
        [NoScaleOffset] _Portal_State("Portal state texture", 2D) = ""
        _Item_Portal_State("Item portal state : 0=w,1=p,2+n=transiting_fwd,-2-n=transiting_back)", Integer) = 0
        [ToggleUI] _Camera_In_Portal("Camera is in portal space", Float) = 0
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

            #include "UnityCG.cginc"

            #include "portal.hlsl"

            uniform Texture2D<uint4> _Portal_State;

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
            
            uniform float _Camera_In_Portal;
            uniform int _Item_Portal_State;

            uniform half4 _Color;

            uniform float _VRChatCameraMode;

            half4 fragment_stage (FragmentData input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Start portal section TODO abstract away.
                half portal_alpha_data = 1;
                
                Header header = Header::decode(_Portal_State);
                if(header.is_enabled) {
                    bool camera_in_portal = header.camera_portal_state(_VRChatCameraMode);
                    bool portal_parity = _Camera_In_Portal; // camera_in_portal; // FIXME Testing
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
                    
                    float max_intersection_ray_01 = -1;
                    uint closest_portal_id = 0;
                    
                    [loop] while(header.portal_mask) {
                        uint index = pop_active_portal(header.portal_mask);
                        PortalPixel0 p0 = PortalPixel0::decode(_Portal_State, index);
                        if(!p0.fast_intersect(_WorldSpaceCameraPos, input.world_position)) { continue; }
                        Portal portal = Portal::decode(p0, _Portal_State, index);
                        
                        float intersection_ray_01;
                        if(portal.segment_intersect(_WorldSpaceCameraPos, input.world_position, intersection_ray_01)) {
                            portal_parity = !portal_parity;

                            if(intersection_ray_01 > max_intersection_ray_01) {
                                closest_portal_id = index;
                                max_intersection_ray_01 = intersection_ray_01;
                            }
                        }
    
                        if(index == transiting_portal_id) {
                            if(dot(input.world_position - portal.position, portal.normal) * transiting_direction >= 0) {
                                portal_parity = !portal_parity;
                                in_portal_space = true;
                            }
                        }
                    }
    
                    if(portal_parity) { discard; }
                    if(in_portal_space) { portal_alpha_data = -(1 + float(closest_portal_id)); }
                }
                
                return half4(_Color.rgb, portal_alpha_data);
            }
            ENDCG
        }
    }
}
