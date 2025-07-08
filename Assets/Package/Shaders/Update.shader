// Passes that are used to update the state in the camera loop.
// 0 : camera 0 : copy RT1 to RT0 ; old position and states
// 1 : camera 0 : extract new portal positions from system meshes to RT0 (upper part, +32 to y)
// 2 : camera 1 : update state from RT0 to RT1 (lower half ; upper half of RT1 never set)
//
// Material is applied to system mesh which is configured to touch both camera and be the only one in UIMenu layer.
// Visuals are in Default layer and placed on another renderer
Shader "Lereldarion/Portal/Update" {
    Properties {
        [Header(Camera identification depths)]
        _Camera0_FarPlane("Camera 0 far plane", Float) = 0
        _Camera1_FarPlane("Camera 1 far plane", Float) = 0

        [Header(Render textures)]
        [NoScaleOffset] _Portal_RT0("RT0", 2D) = ""
        [NoScaleOffset] _Portal_RT1("RT1", 2D) = ""

        [Header(Portals)]
        [ToggleUI] _Portal_System_Enabled("Set enabled flag in state texture", Integer) = 1
        [ToggleUI] _Portal_Camera_Force_World("Force camera to world", Integer) = 0

        _Portal_Count("Portal count to scan", Integer) = 0
        _Valid_Movement_Max_Distance("Maximum distance allowed to consider a movement legit (no TP)", Float) = 1
    }
    SubShader {
        Tags {
            "Queue" = "Overlay+1000"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        CGINCLUDE
        #pragma multi_compile_instancing
        #pragma target 5.0
        #include "UnityCG.cginc"

        bool rendering_in_orthographic_camera_with_far_plane(float far_plane) {
            return unity_OrthoParams.w && abs(_ProjectionParams.z - far_plane) < 0.0001;
        }

        float4 target_pixel_to_cs(uint2 position) {
            float2 target_resolution = _ScreenParams.xy;
            float2 position_cs = (position * 2 - target_resolution + 1) / target_resolution; // +1 = center of pixels
            // https://docs.unity3d.com/Manual/SL-PlatformDifferences.html
            if (_ProjectionParams.x < 0) { position_cs.y = -position_cs.y; }
            return float4(position_cs, UNITY_NEAR_CLIP_VALUE, 1);
        }

        ENDCG

        ZTest Always
        ZWrite Off
        Blend Off

        Pass {
            Name "Copy RT1 to RT0"

            Cull Off

            CGPROGRAM
            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage

            uniform float _Camera0_FarPlane;
            uniform Texture2D<uint4> _Portal_RT1;

            struct MeshData {
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct FragmentData {
                float4 position : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            void vertex_stage (MeshData input, out MeshData output) {
                output = input;
            }
            
            uint4 fragment_stage (FragmentData input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                uint2 pixel_pos = input.position.xy;
                return _Portal_RT1[pixel_pos];
            }

            [maxvertexcount(4)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, inout TriangleStream<FragmentData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);
                
                if(!(primitive_id == 0 && rendering_in_orthographic_camera_with_far_plane(_Camera0_FarPlane))) {
                    return;
                }
                
                // Make fullscreen quad to copy all pixels
                FragmentData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                const float2 quad_corners[4] = { float2(-1, -1), float2(-1, 1), float2(1, -1), float2(1, 1) };
                [unroll] for(uint i = 0; i < 4; i += 1) {
                    output.position = float4(quad_corners[i], UNITY_NEAR_CLIP_VALUE, 1);
                    stream.Append(output);
                }
            }
            ENDCG
        }

        Pass {
            Name "Encode System Positions to RT0"

            CGPROGRAM
            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage
            
            #include "portal.hlsl"
            
            uniform float _Camera0_FarPlane;
            
            struct MeshData {
                float3 position : POSITION;
                float3 normal : NORMAL;
                float3 tangent : TANGENT;
                float2 uv0 : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct WorldMeshData {
                float3 position : W_POSITION;
                float3 normal : W_NORMAL;
                float3 tangent : W_TANGENT;
                float2 uv0 : UV0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct PixelData {
                float4 position : SV_POSITION;
                uint4 data : DATA;
                UNITY_VERTEX_OUTPUT_STEREO

                static void emit(inout PointStream<PixelData> stream, uint2 coordinates, uint4 data) {
                    PixelData output;
                    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                    output.position = target_pixel_to_cs(coordinates);
                    output.data = data;
                    stream.Append(output);
                }
            };
            
            void vertex_stage (MeshData input, out WorldMeshData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                output.position = mul(unity_ObjectToWorld, float4(input.position, 1)).xyz;
                output.normal = mul((float3x3) unity_ObjectToWorld, input.normal);
                output.tangent = mul((float3x3) unity_ObjectToWorld, input.tangent);
                output.uv0 = input.uv0;
                UNITY_TRANSFER_INSTANCE_ID(input, output);
            }
            
            uint4 fragment_stage (PixelData pixel) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(pixel);
                return pixel.data;
            }
            
            // Each portal emits 2 pixels of data
            [maxvertexcount(2)]
            void geometry_stage(point WorldMeshData input_array[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                WorldMeshData input = input_array[0];
                UNITY_SETUP_INSTANCE_ID(input);

                if(!rendering_in_orthographic_camera_with_far_plane(_Camera0_FarPlane)) { return; }
                
                PixelData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                
                int vertex_type = input.uv0.x;
                switch(vertex_type) {
                    case 1: case 2: {
                        // Portal pixels. Always rendered, will be sorted
                        Portal portal;
                        portal.position = input.position;
                        portal.x_axis = input.normal;
                        portal.y_axis = input.tangent;
                        portal.is_ellipse = vertex_type == 2;
                        portal.finalize();
                        uint portal_id = input.uv0.y;

                        uint4 pixels[2];
                        portal.encode(pixels);
                        PixelData::emit(stream, uint2(1, portal_id + 32), pixels[0]);
                        PixelData::emit(stream, uint2(2, portal_id + 32), pixels[1]);
                        break;
                    }
                    default: break;
                }
            }
            ENDCG
        }

        Pass {
            Name "Update state from RT0 to RT1"

            CGPROGRAM
            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage

            #include "portal.hlsl"

            uniform float _Camera1_FarPlane;
            uniform Texture2D<uint4> _Portal_RT0; // lower half is old data, upper half new position data (no header).

            // VRChat global variables, independent on the rendering camera.
            uniform float3 _VRChatScreenCameraPos;
            uniform float3 _VRChatPhotoCameraPos;

            uniform uint _Portal_System_Enabled;
            uniform uint _Portal_Camera_Force_World;
            uniform uint _Portal_Count;
            uniform float _Valid_Movement_Max_Distance;
            
            struct MeshData {
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct PixelData {
                float4 position : SV_POSITION;
                uint4 data : DATA;
                UNITY_VERTEX_OUTPUT_STEREO

                static void emit(inout PointStream<PixelData> stream, uint2 coordinates, uint4 data) {
                    PixelData output;
                    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                    output.position = target_pixel_to_cs(coordinates);
                    output.data = data;
                    stream.Append(output);
                }
            };
            
            void vertex_stage (MeshData input, out MeshData output) {
                output = input;
            }
            
            uint4 fragment_stage (PixelData pixel) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(pixel);
                return pixel.data;
            }

            bool is_movement_valid(float3 from, float3 to) {
                float3 movement = to - from;
                return dot(movement, movement) < _Valid_Movement_Max_Distance * _Valid_Movement_Max_Distance;
                // TODO use max speed with deltatime
            }
            
            [instance(32)] // One per horizontal line
            [maxvertexcount(32)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, uint instance : SV_GSInstanceID, inout PointStream<PixelData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                if(!(primitive_id == 0 && rendering_in_orthographic_camera_with_far_plane(_Camera1_FarPlane))) { return; }

                // Max supported size for now, safety against bad value
                _Portal_Count = min(_Portal_Count, 32);

                Header header = Header::decode(_Portal_RT0);
                header.is_enabled = _Portal_System_Enabled;
                header.portal_mask = 0x0;
                
                // Update camera positions
                float3 new_camera_pos[2] = { _VRChatScreenCameraPos, _VRChatPhotoCameraPos };
                if(instance < 2) {
                    PixelData::emit(stream, uint2(0, 1 + instance), CameraPosition::encode(new_camera_pos[instance]));
                }

                // Every thread will load the full old and new portal info and build the portal mask.
                uint portals_with_valid_movement = 0x0;
                [loop] for(uint index = 0; index < _Portal_Count; index += 1) {
                    Portal new_portal = Portal::decode(_Portal_RT0, index + 32);
                    if(new_portal.is_enabled()) {
                        uint bit = 0x1 << index;
                        header.portal_mask |= bit;

                        PortalPixel0 old_portal = PortalPixel0::decode(_Portal_RT0, index);
                        if(old_portal.is_enabled() && is_movement_valid(old_portal.position, new_portal.position)) {
                            portals_with_valid_movement |= bit;
                        }
                    }
                }

                // Output instance new portal data
                if(instance < _Portal_Count) {
                    PixelData::emit(stream, uint2(1, instance), _Portal_RT0[uint2(1, instance + 32)]);
                    PixelData::emit(stream, uint2(2, instance), _Portal_RT0[uint2(2, instance + 32)]);
                }

                // TODO update portal probes of line k

                if(instance == 0) {
                    if(_Portal_Camera_Force_World) {
                        header.camera_in_portal[0] = false;
                        header.camera_in_portal[1] = false;
                    } else {
                        // Update camera states
                        float3 old_camera_pos[2] = { CameraPosition::decode(_Portal_RT0, 0), CameraPosition::decode(_Portal_RT0, 1) };
                        bool update_camera[2] = {
                            is_movement_valid(old_camera_pos[0], new_camera_pos[0]),
                            // Photo camera when disabled is set to exact (0, 0, 0), ignore it as well
                            is_movement_valid(old_camera_pos[1], new_camera_pos[1]) && all(old_camera_pos[1] != 0) && all(new_camera_pos[1] != 0),
                        };
                        
                        uint portal_mask = portals_with_valid_movement;
                        [loop] while(portal_mask) {
                            uint index = pop_active_portal(portal_mask);
                            Portal old_portal = Portal::decode(_Portal_RT0, index);
                            Portal new_portal = Portal::decode(_Portal_RT0, index + 32);
    
                            [unroll] for(uint i = 0; i < 2; i += 1) {
                                if(update_camera[i] && Portal::movement_intersect(old_portal, new_portal, old_camera_pos[i], new_camera_pos[i]) & 0x1) {
                                    header.camera_in_portal[i] = !header.camera_in_portal[i];
                                }
                            }
                        }
                    }

                    PixelData::emit(stream, uint2(0, 0), header.encode());
                }
            }
            ENDCG
        }
    }
}
