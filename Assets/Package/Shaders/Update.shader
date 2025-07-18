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
        _Mesh_Probe_Count("Mesh portal count to update", Integer) = 0
        _Valid_Movement_Max_Distance("Maximum distance allowed to consider a movement legit (no TP)", Float) = 1
    }
    SubShader {
        Tags {
            "Queue" = "Overlay+1000"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        CGINCLUDE
        #pragma target 5.0
        #pragma multi_compile_instancing
        #include "UnityCG.cginc"

        bool rendering_in_orthographic_camera_with_far_plane(float far_plane) {
            return unity_OrthoParams.w && abs(_ProjectionParams.z - far_plane) < 0.0001;
        }

        float4 target_pixel_to_cs(uint2 position) {
            const float2 target_resolution = _ScreenParams.xy;
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
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
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
                float4 uv0 : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct WorldMeshData {
                float3 position : W_POSITION;
                float3 normal : W_NORMAL;
                float3 tangent : W_TANGENT;
                float4 uv0 : UV0;
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
                        const uint portal_id = input.uv0.y;

                        uint4 pixels[2];
                        portal.encode(pixels);
                        PixelData::emit(stream, uint2(1, portal_id + 32), pixels[0]);
                        PixelData::emit(stream, uint2(2, portal_id + 32), pixels[1]);
                        break;
                    }
                    case 3: {
                        // Mesh probe config
                        MeshProbeConfig probe;
                        probe.position = input.position;
                        probe.radius = length(input.normal);
                        const float parent = input.uv0.z;
                        if(parent < 0) {
                            probe.parent = MeshProbeConfig::no_parent;
                        } else {
                            probe.parent = min((uint) parent, 0xFFFF);
                        }
                        const uint id = input.uv0.y;
                        PixelData::emit(stream, uint2(3 + id / 32, id % 32 + 32), probe.encode());
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
            
            // Data used to reconstruct stereo eye ws positions
            uniform Texture2D<half4> _Lereldarion_Portal_Seal_GrabPass; // Stereo VS offsets
            uniform float4 _VRChatScreenCameraRot;

            uniform uint _Portal_System_Enabled;
            uniform uint _Portal_Camera_Force_World;
            uniform uint _Portal_Count;
            uniform uint _Mesh_Probe_Count;
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
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
            }
            
            uint4 fragment_stage (PixelData pixel) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(pixel);
                return pixel.data;
            }

            float length_sq(float3 v) { return dot(v, v); }

            bool is_movement_valid(float3 from, float3 to) {
                return length_sq(to - from) < _Valid_Movement_Max_Distance * _Valid_Movement_Max_Distance;
                // TODO use max speed with deltatime
            }

            float3 quaternion_rotate(float4 q, float3 v) {
                return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
            }
            
            [instance(32)] // One per horizontal line
            [maxvertexcount(32)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, uint instance : SV_GSInstanceID, inout PointStream<PixelData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                if(!(primitive_id == 0 && rendering_in_orthographic_camera_with_far_plane(_Camera1_FarPlane))) { return; }

                // Max supported size for now, safety against bad value
                _Portal_Count = min(_Portal_Count, 31);

                Header header = Header::decode(_Portal_RT0);
                header.is_enabled = _Portal_System_Enabled;
                header.mesh_probe_count = _Mesh_Probe_Count; // Make it available because we have unused space.
                const uint old_portal_mask = header.portal_mask;
                header.portal_mask = 0x0;
                
                // Update camera positions
                const float3 new_camera_pos[2] = { _VRChatScreenCameraPos, _VRChatPhotoCameraPos };
                if(instance < 2) {
                    PixelData::emit(stream, uint2(0, 1 + instance), CameraPosition::encode(new_camera_pos[instance]));
                }

                // Every thread will load the full old and new portal info and build the portal mask.
                uint portals_with_valid_movement = 0x0;
                [loop] for(uint index = 0; index < _Portal_Count; index += 1) {
                    const Portal new_portal = Portal::decode(_Portal_RT0, index + 32);
                    if(new_portal.is_enabled()) {
                        const uint bit = 0x1 << index;
                        header.portal_mask |= bit;

                        const PortalPixel0 old_portal = PortalPixel0::decode(_Portal_RT0, index);
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

                // Update portal probes of line "instance"
                const uint active_portals_old_new = old_portal_mask | header.portal_mask;
                for(uint column = 0; column * 32 + instance < _Mesh_Probe_Count; column += 1) {
                    const MeshProbeConfig config = MeshProbeConfig::decode(_Portal_RT0[uint2(3 + column, instance + 32)]);
                    MeshProbeState state = MeshProbeState::decode(_Portal_RT0[uint2(3 + column, instance)]);

                    bool has_parent = false;
                    MeshProbeState parent_state = (MeshProbeState) 0; // Read only if has_parent, but compiler cannot prove it and complains if not initialized.
                    if(config.parent != MeshProbeConfig::no_parent) {
                        parent_state = MeshProbeState::decode(_Portal_RT0, config.parent);
                        has_parent = true;
                    }

                    // Scan portals once and gather all relevant intersection data
                    uint portal_mask = active_portals_old_new;
                    uint link_intersection_count = 0;
                    uint movement_intersection_count = 0;
                    state.traversing_portal_mask = 0x0;
                    [loop] while(portal_mask) {
                        const uint index = pop_active_portal(portal_mask);
                        const uint bit = 0x1 << index;
                        const Portal old_portal = Portal::decode(_Portal_RT0, index);
                        const Portal new_portal = Portal::decode(_Portal_RT0, index + 32);

                        if(has_parent && (bit & old_portal_mask)) {
                            if(old_portal.segment_intersect(state.position, parent_state.position)) {
                                link_intersection_count += 1;
                            }
                        }
                        if(bit & portals_with_valid_movement) {
                            movement_intersection_count += Portal::movement_intersect(old_portal, new_portal, state.position, config.position);
                        }
                        if(bit & header.portal_mask) {
                            if(new_portal.distance_to_point(config.position) < config.radius) {
                                // Mark portal as being possibly traversed
                                state.traversing_portal_mask |= bit;
                            }
                        }
                    }

                    if(has_parent) {
                        // Fix incoherent states : link to parent can only have different state if explained by portal intersection.
                        // This is done on old state because this is the only time where we have all probes (current and parent) of the same frame.
                        const bool same_space = state.in_portal == parent_state.in_portal;
                        if(same_space == bool(link_intersection_count & 0x1)) {
                            // Incoherence, reset to parent
                            state.in_portal = parent_state.in_portal;
                        }
                    }

                    // New state
                    if(movement_intersection_count & 0x1) {
                        state.in_portal = !state.in_portal;
                    }
                    state.position = config.position;
                    PixelData::emit(stream, uint2(3 + column, instance), state.encode());
                    PixelData::emit(stream, uint2(3 + column, instance + 32), config.encode()); // FIXME Expose parent for debug
                }

                if(instance == 0) {
                    if(_Portal_Camera_Force_World) {
                        header.camera_in_portal[0] = false;
                        header.camera_in_portal[1] = false;
                    } else {
                        // Update camera states
                        const float3 old_camera_pos[2] = { CameraPosition::decode(_Portal_RT0, 0), CameraPosition::decode(_Portal_RT0, 1) };
                        const bool update_camera[2] = {
                            is_movement_valid(old_camera_pos[0], new_camera_pos[0]),
                            // Photo camera when disabled is set to exact (0, 0, 0), ignore it as well
                            is_movement_valid(old_camera_pos[1], new_camera_pos[1]) && all(old_camera_pos[1] != 0) && all(new_camera_pos[1] != 0),
                        };
                        
                        uint portal_mask = portals_with_valid_movement;
                        [loop] while(portal_mask) {
                            const uint index = pop_active_portal(portal_mask);
                            const Portal old_portal = Portal::decode(_Portal_RT0, index);
                            const Portal new_portal = Portal::decode(_Portal_RT0, index + 32);
    
                            [unroll] for(uint i = 0; i < 2; i += 1) {
                                if(update_camera[i] && Portal::movement_intersect(old_portal, new_portal, old_camera_pos[i], new_camera_pos[i]) & 0x1) {
                                    header.camera_in_portal[i] = !header.camera_in_portal[i];
                                }
                            }
                        }
                    }

                    // Compute intersection flips between centered pos and stereo eyes.
                    header.stereo_eye_in_portal[0] = header.camera_in_portal[0];
                    header.stereo_eye_in_portal[1] = header.camera_in_portal[0];
                    const float3 stereo_eye_offsets[2] = {
                        _Lereldarion_Portal_Seal_GrabPass[uint2(0, 0)].xyz,
                        _Lereldarion_Portal_Seal_GrabPass[uint2(1, 0)].xyz
                    };
                    if(length_sq(stereo_eye_offsets[0]) > 0) {
                        const float3 stereo_eye_ws[2] = {
                            _VRChatScreenCameraPos + quaternion_rotate(_VRChatScreenCameraRot, stereo_eye_offsets[0]),
                            _VRChatScreenCameraPos + quaternion_rotate(_VRChatScreenCameraRot, stereo_eye_offsets[1])
                        };

                        uint portal_mask = header.portal_mask; // Check all enabled portals at this frame.
                        [loop] while(portal_mask) {
                            const uint index = pop_active_portal(portal_mask);
                            const Portal new_portal = Portal::decode(_Portal_RT0, index + 32);
                            [unroll] for(uint i = 0; i < 2; i += 1) {
                                if(new_portal.segment_intersect(_VRChatScreenCameraPos, stereo_eye_ws[i])) {
                                    header.stereo_eye_in_portal[i] = !header.stereo_eye_in_portal[i];
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
