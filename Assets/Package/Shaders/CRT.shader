
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
            //
            // Update the camera states
            //
            // TODO Update portal probe states

            Name "Update Portal Configuration"

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
            
            // If we ever move to 64 portals, we will need to split this part, due to max of 128 emits.
            [instance(32)] // One per horizontal line
            [maxvertexcount(32)]
            void geometry_stage(point GeometryData input[1], uint primitive_id : SV_PrimitiveID, uint instance : SV_GSInstanceID, inout PointStream<PixelData> stream) {
                // One iteration
                if(primitive_id != 0) { return; }

                // Max supported size for now, safety against bad value
                _GrabPass_Portal_Count = min(_GrabPass_Portal_Count, 32);

                Control control = Control::decode_grabpass(_Lereldarion_Portal_System_GrabPass);

                // When system is disabled (control mesh toggled off) or not working :
                // Do not update status of objects.
                // Reset camera state.

                Header new_header;
                new_header.portal_mask = 0x0;
                new_header.is_enabled = false;
                new_header.camera_in_portal[0] = false;
                new_header.camera_in_portal[1] = false;
                
                // Always update camera positions
                float3 new_camera_pos[2] = { _VRChatScreenCameraPos, _VRChatPhotoCameraPos };
                if(instance < 2) {
                    PixelData::emit(stream, uint2(0, 1 + instance), CameraPosition::encode_crt(new_camera_pos[instance]));
                }

                if(control.system_valid) {
                    new_header.is_enabled = true;
                    Header old_header = Header::decode_crt(_SelfTexture2D);
                    new_header.camera_in_portal = old_header.camera_in_portal;

                    uint4 new_portal_pixels[32][2]; // Store encoded portal config for later queries : camera, probe states
                    uint portals_with_valid_movement = 0x0;

                    // Every thread will load the full old and new portal info and build the portal mask.
                    [loop] for(uint index = 0; index < _GrabPass_Portal_Count; index += 1) {
                        Portal new_portal = Portal::decode_grabpass(_Lereldarion_Portal_System_GrabPass, index);
                        new_portal.encode_crt(new_portal_pixels[index]);
                        
                        if(new_portal.is_enabled()) {
                            uint bit = 0x1 << index;
                            new_header.portal_mask |= bit;

                            PortalPixel0 old_portal = PortalPixel0::decode_crt(_SelfTexture2D, index);
                            if(old_portal.is_enabled() && is_movement_valid(old_portal.position, new_portal.position)) {
                                portals_with_valid_movement |= bit;
                            }
                        }
                    }

                    // Output instance new portal data
                    if(instance < _GrabPass_Portal_Count) {
                        PixelData::emit(stream, uint2(1, instance), new_portal_pixels[instance][0]);
                        PixelData::emit(stream, uint2(2, instance), new_portal_pixels[instance][1]);
                    }

                    // Camera state update only for thread 0, which will write the header.
                    if(instance == 0) {
                        float3 old_camera_pos[2] = { CameraPosition::decode_crt(_SelfTexture2D, 0), CameraPosition::decode_crt(_SelfTexture2D, 1) };
                        bool update_camera[2] = {
                            is_movement_valid(old_camera_pos[0], new_camera_pos[0]),
                            // Photo camera when disabled is set to exact (0, 0, 0), ignore it as well
                            is_movement_valid(old_camera_pos[1], new_camera_pos[1]) && all(old_camera_pos[1] != 0) && all(new_camera_pos[1] != 0),
                        };
                        
                        uint portal_mask = portals_with_valid_movement;
                        [loop] while(portal_mask != 0x0) {
                            uint index = firstbitlow(portal_mask);
                            portal_mask ^= 0x1 << index; // Mask as seen

                            Portal old_portal = Portal::decode_crt(_SelfTexture2D, index);
                            Portal new_portal = Portal::decode_crt(new_portal_pixels[index]);

                            [unroll] for(uint i = 0; i < 2; i += 1) {
                                if(update_camera[i] && Portal::movement_intersect(old_portal, new_portal, old_camera_pos[i], new_camera_pos[i]) & 0x1) {
                                    new_header.camera_in_portal[i] = !new_header.camera_in_portal[i];
                                }
                            }
                        }
                    }

                    // TODO update portal probes
                }

                if(instance == 0) {
                    PixelData::emit(stream, uint2(0, 0), new_header.encode_crt());
                }
            }
            ENDCG
        }
    }
}
