
Shader "Lereldarion/Portal/CRT" {
    Properties {
        _Valid_Movement_Max_Distance("Maximum distance allowed to consider a movement legit (no TP)", Float) = 1
        _GrabPass_Portal_Count("Portal count to scan in the grabpass (set by export script)", Integer) = 0
    }
    SubShader {
        Tags {
            "PreviewType" = "Plane"
        }

        ZTest Always
        ZWrite Off
        Blend Off

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

                static void emit(inout PointStream<PixelData> stream, uint2 coordinates, uint4 data) {
                    PixelData output;
                    output.position = target_pixel_to_cs(coordinates, _CustomRenderTextureInfo.xy);
                    output.data = data;
                    stream.Append(output);
                }
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

            uniform float _Valid_Movement_Max_Distance;
            uniform uint _GrabPass_Portal_Count;

            bool is_movement_valid(float3 from, float3 to) {
                float3 movement = to - from;
                return dot(movement, movement) < _Valid_Movement_Max_Distance * _Valid_Movement_Max_Distance;
                // TODO use max speed with deltatime
            }
            bool is_camera_movement_valid(float3 from, float3 to) {
                return any(from != 0) && any(to != 0) && is_movement_valid(from, to);
            }
            
            // If we ever move to 64 portals, we will need to split this part, due to max of 128 emits.
            [maxvertexcount(32 * 2 + 2 + 1)]
            void geometry_stage(point GeometryData input[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                // Compared to flexcrt we only want one thread that will scan all portals, so just get one iteration.
                if(primitive_id != 0) { return; }

                Control control = Control::decode_grabpass(_Lereldarion_Portal_System_GrabPass);
                if(!control.system_valid) {
                    PixelData::emit(stream, uint2(0, 0), Header::encode_disabled_crt());
                    return;
                }

                Header header = Header::decode_crt(_SelfTexture2D); // Retrieve camera state
                header.portal_mask = 0x0;
                header.is_enabled = true;
                
                float3 camera_pos[2] = { CameraPosition::decode_crt(_SelfTexture2D, 0), CameraPosition::decode_crt(_SelfTexture2D, 1) };
                float3 new_camera_pos[2] = { _VRChatScreenCameraPos, _VRChatPhotoCameraPos };
                PixelData::emit(stream, uint2(0, 1), CameraPosition::encode_crt(new_camera_pos[0]));
                PixelData::emit(stream, uint2(0, 2), CameraPosition::encode_crt(new_camera_pos[1]));
                bool camera_movement_valid[2] = {
                    is_camera_movement_valid(camera_pos[0], new_camera_pos[0]),
                    is_camera_movement_valid(camera_pos[1], new_camera_pos[1]),
                };

                _GrabPass_Portal_Count = min(_GrabPass_Portal_Count, 32); // Max supported size for now, safety against bad value
                [loop]
                for(uint index = 0; index < _GrabPass_Portal_Count; index += 1) {
                    // Convert from grabpass to CRT. Always output to set its new state for other passes.
                    Portal new_portal = Portal::decode_grabpass(_Lereldarion_Portal_System_GrabPass, index);
                    uint4 pixels[2];
                    new_portal.encode_crt(pixels);
                    PixelData::emit(stream, uint2(1, index), pixels[0]);
                    PixelData::emit(stream, uint2(2, index), pixels[1]);

                    if(new_portal.is_enabled()) {
                        header.portal_mask |= 0x1 << index;

                        // Update camera portal state
                        PortalPixel0 portal_pixel0 = PortalPixel0::decode_crt(_SelfTexture2D, index);
                        if(portal_pixel0.is_enabled() && is_movement_valid(portal_pixel0.position, new_portal.position)) {
                            Portal portal = Portal::decode_crt(portal_pixel0, _SelfTexture2D, index);

                            [unroll]
                            for(uint i = 0; i < 2; i += 1) {
                                if(camera_movement_valid[i] && Portal::movement_intersect(portal, new_portal, camera_pos[i], new_camera_pos[i]) & 0x1) {
                                    header.camera_in_portal[i] = !header.camera_in_portal[i];
                                }
                            }
                        }
                    }
                }

                PixelData::emit(stream, uint2(0, 0), header.encode_crt());                
            }
            ENDCG
        }
    }
}
