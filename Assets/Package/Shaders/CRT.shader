
Shader "Lereldarion/Portal/CRT" {
    Properties {
        _Camera_Movement_Max_Distance("Maximum distance allowed to consider camera movement legit", Float) = 1
    }
    SubShader {
        Tags {
            "PreviewType" = "Plane"
        }

        ZTest Always
        ZWrite Off
        Lighting Off

        Pass {
            // Compact portal positions into 2 f32x4 per portal.
            // Use the flexcrt strategy (cnlohr) : geometry pass to blit at interesting places
            // https://github.com/cnlohr/flexcrt/blob/master/Assets/flexcrt_demo/ExampleFlexCRT.shader#L78
            // Also update the camera states

            Name "Process Portal configuration"

            CGPROGRAM
            #pragma target 5.0

            // Trick to get previous texture as Texture2D of our choice
            #define _SelfTexture2D _JunkTexture
            #include "UnityCustomRenderTexture.cginc"
            #undef _SelfTexture2D
            Texture2D<uint4> _SelfTexture2D;
            
            #include "portal.hlsl"
            Texture2D<float4> _Lereldarion_Portal_System_GrabPass;

            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage
            
            struct MeshData {
                uint vertex_id : SV_VertexID;
            };
            struct GeometryData {
                uint batch_id : BATCH_ID;
            };
            struct PixelData {
                float4 position : SV_POSITION;
                uint4 data : DATA;
            };
            
            void vertex_stage (MeshData input, out GeometryData output) {
                // CRT emit a quad per draw call, as 2 separate triangles (6 vertex)
                output.batch_id = input.vertex_id / 6;
            }
            
            uint4 fragment_stage (PixelData pixel) : SV_Target {
                return pixel.data;
            }

            // VRChat global variables, independent on the rendering camera.
            // Available in the CRT so no need for grabpass encodings.
            uniform float3 _VRChatScreenCameraPos;
            uniform float3 _VRChatPhotoCameraPos;

            uniform float _Camera_Movement_Max_Distance;

            bool is_camera_movement_valid(float3 from, float3 to) {
                float3 movement = to - from;
                return all(from != 0 && to != 0) && dot(movement, movement) < _Camera_Movement_Max_Distance * _Camera_Movement_Max_Distance;
            }
                        
            [maxvertexcount(128)]
            void geometry_stage(point GeometryData input[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                // Compared to flexcrt we only want one thread that will scan all portals, so just get one iteration.
                if(primitive_id == 0) {
                    PixelData output;
                    
                    System system = System::decode_grabpass(_Lereldarion_Portal_System_GrabPass);

                    Camera camera[2] = { Camera::decode_crt(_SelfTexture2D, 0), Camera::decode_crt(_SelfTexture2D, 1) };
                    float3 new_camera[2] = { _VRChatScreenCameraPos, _VRChatPhotoCameraPos };
                    bool camera_movement_valid[2] = {
                        is_camera_movement_valid(camera[0].position, new_camera[0]),
                        is_camera_movement_valid(camera[1].position, new_camera[1]),
                    };
                    
                    uint active_portal_count = 0;
                    uint max_portal_scan_count = min(system.portal_count, 32);
                    [loop]
                    for(uint index = 0; index < max_portal_scan_count; index += 1) {
                        Portal p = Portal::decode_grabpass(_Lereldarion_Portal_System_GrabPass, index);
                        if(p.is_enabled()) {
                            uint4 pixels[2];
                            p.encode_crt(pixels);
                            for(uint i = 0; i < 2; i += 1) {
                                output.position = target_pixel_to_cs(uint2(1 + active_portal_count, i), _CustomRenderTextureInfo.xy);
                                output.data = pixels[i];
                                stream.Append(output);
                            }
                            active_portal_count += 1;

                            // Update camera portal state
                            for(i = 0; i < 2; i += 1) {
                                if(camera_movement_valid[i] && p.segment_intersect(camera[i].position, new_camera[i])) {
                                    camera[i].in_portal = !camera[i].in_portal;
                                }
                            }
                        }
                    }

                    // Sentinel pixel with portal of radius 0
                    output.position = target_pixel_to_cs(uint2(1 + active_portal_count, 0), _CustomRenderTextureInfo.xy);
                    output.data = PortalPixel0::encode_disabled_crt();
                    stream.Append(output);

                    // New camera state
                    for(uint i = 0; i < 2; i += 1) {
                        camera[i].position = new_camera[i];
                        output.position = target_pixel_to_cs(uint2(0, i), _CustomRenderTextureInfo.xy);
                        output.data = camera[i].encode_crt();
                        stream.Append(output);
                    }
                }
            }
            ENDCG
        }

    }
}
