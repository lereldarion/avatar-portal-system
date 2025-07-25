
Shader "Lereldarion/Portal/Seal Interface" {
    Properties {
        [NoScaleOffset] _Portal_State("Portal state texture", 2D) = "" {}
        _Portal_Seal_Stencil_Bit("Power of 2 bit used to avoid repetition when sealing", Integer) = 64        
    }
    SubShader {
        Tags {
            "Queue" = "Geometry-160"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        Pass {
            Name "Extract Stereo Eye Offsets"

            // Stereo offsets can only be extracted from a grabpass running in VR SPS-I.
            // Goal is for the grabpass to store view-space offsets (2x f16x3 pixels) and let them be used by camera loop update.
            // Update probably runs before VR camera, so we will have last frame offsets, but they should not change in view space.
            // Other problem : only the last grabpass will be kept global for the next frame. So only override when in VR and copy if not to transmit to the last grabpass.
            ZTest Always
            ZWrite Off
            Blend Off
            ColorMask RGB // Keep alpha from portal-aware shaders intact

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage

            uniform Texture2D<half4> _Lereldarion_Portal_Seal_GrabPass;
            uniform float _VRChatCameraMode;
            uniform float3 _VRChatScreenCameraPos;
            uniform float4 _VRChatScreenCameraRot;

            struct MeshData {
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float4 target_pixel_to_cs(uint2 position) {
                const float2 target_resolution = _ScreenParams.xy;
                float2 position_cs = (position * 2 - target_resolution + 1) / target_resolution; // +1 = center of pixels
                // https://docs.unity3d.com/Manual/SL-PlatformDifferences.html
                if (_ProjectionParams.x < 0) { position_cs.y = -position_cs.y; }
                return float4(position_cs, UNITY_NEAR_CLIP_VALUE, 1);
            }

            struct PixelData {
                float4 position : SV_POSITION;
                half4 data : DATA;
                UNITY_VERTEX_OUTPUT_STEREO

                static void emit(inout PointStream<PixelData> stream, uint2 coordinates, half4 data) {
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
            
            half4 fragment_stage (PixelData pixel) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(pixel);
                return pixel.data;
            }

            float3 quaternion_anti_rotate(float4 q, float3 v) {
                return v + 2.0 * cross(q.xyz, cross(q.xyz, v) - q.w * v);
            }

            [maxvertexcount(2)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                if(primitive_id == 0) {
                    half4 pixels[2];

                    if(_VRChatCameraMode == 0) {
                        #ifdef USING_STEREO_MATRICES
                        // Set pixels with VS eye offsets
                        pixels[0] = half4(quaternion_anti_rotate(_VRChatScreenCameraRot, unity_StereoWorldSpaceCameraPos[0] - _VRChatScreenCameraPos), 0);
                        pixels[1] = half4(quaternion_anti_rotate(_VRChatScreenCameraRot, unity_StereoWorldSpaceCameraPos[1] - _VRChatScreenCameraPos), 0);
                        #else
                        pixels[0] = half4(0, 0, 0, 0);
                        pixels[1] = half4(0, 0, 0, 0);
                        #endif
                    } else {
                        // Copy pixels from grabpass to grabpass
                        pixels[0] = _Lereldarion_Portal_Seal_GrabPass[uint2(0, 0)];
                        pixels[1] = _Lereldarion_Portal_Seal_GrabPass[uint2(1, 0)];
                    }

                    PixelData::emit(stream, uint2(0, 0), pixels[0]);
                    PixelData::emit(stream, uint2(1, 0), pixels[1]);
                }
            }
            ENDCG
        }

        GrabPass {
            "_Lereldarion_Portal_Seal_GrabPass"
            Name "Portal Ids"
        }

        Pass {
            Name "Seal Interface"

            // Add portal background and seal depth where necessary.
            // Generate fragment calls for all useful pixels :
            // - for camera in portal space, fullscreen, and discard for exits
            // - for camera in world, generate quads at portal positions, but try avoiding overdraw using stencil bit ("pixel has been done").
            Cull Off
            ZTest Always
            ZWrite On
            Blend Off
            Stencil {
                // Set bit, and only run if not set.
                Ref [_Portal_Seal_Stencil_Bit]
                ReadMask [_Portal_Seal_Stencil_Bit]
                Comp NotEqual
                WriteMask [_Portal_Seal_Stencil_Bit]
                Pass Replace 
            }

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing

            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage

            #include "UnityCG.cginc"
            #include "portal.hlsl"

            uniform Texture2D<uint4> _Portal_State;
            uniform float _VRChatCameraMode;

            // portal ids of pixels of objects in portal space
            uniform Texture2D<float4> _Lereldarion_Portal_Seal_GrabPass;
            uniform float4 _Lereldarion_Portal_Seal_GrabPass_TexelSize;

            struct MeshData {
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct FragmentData {
                float4 position : SV_POSITION;
                float3 position_vs : POSITION_VS; // ray reconstruction
                float4 grab_pos : GRAB_POS;

                // Avoid reloading from texture
                nointerpolation bool camera_in_portal : CAMERA_IN_PORTAL;
                nointerpolation uint portal_mask : PORTAL_MASK;
                
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            void vertex_stage (MeshData input, out MeshData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
            }

            [instance(32)]
            [maxvertexcount(4)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, uint instance : SV_GSInstanceID, inout TriangleStream<FragmentData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                // Input mesh just needs one point
                if(primitive_id != 0) { return ; }

                FragmentData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                const Header header = Header::decode(_Portal_State);
                if(header.is_enabled) {
                    output.camera_in_portal = header.camera_portal_state(_VRChatCameraMode);
                    output.portal_mask = header.portal_mask;

                    // Determine if a quad is printed on the screen for this primitive_id
                    const float near_plane_z = -_ProjectionParams.y;
                    const float2 tan_half_fov = 1 / unity_CameraProjection._m00_m11; // https://jsantell.com/3d-projection/
                    const float2 quad_corners[4] = { float2(-1, -1), float2(-1, 1), float2(1, -1), float2(1, 1) };
                    
                    float3 quad_vs[4] = { float3(0, 0, 0), float3(0, 0, 0), float3(0, 0, 0), float3(0, 0, 0) };
                    bool emit_quad = false;

                    if(output.camera_in_portal) {
                        // One fullscreen quad
                        if(instance == 0) {
                            // Generate in VS close to near clip plane. Having non CS positions is essential to return to WS later.
                            // Add margins in case the matrix has some rotation/skew
                            const float quad_z = near_plane_z * 1.1; // z margin
                            const float quad_xy = quad_z * tan_half_fov * 1.3; // xy margin
                            
                            [unroll] for(uint i = 0; i < 4; i += 1) {
                                quad_vs[i] = float3(quad_corners[i] * quad_xy, quad_z);
                            }
                            emit_quad = true;
                        }
                    } else {
                        // One quad per enabled portal
                        if(header.portal_mask & (0x1 << instance)) {
                            const Portal p = Portal::decode(_Portal_State, instance);

                            // We need the quad only for the screenspace pixel position to activate, not its depth position.
                            // We need to avoid near plane clipping when we traverse.
                            // Solution : scale in VS if distance from camera to quad plane is lower than corners of frustum to near plane.
                            const float frustum_corner_length = length(float3(near_plane_z * tan_half_fov, near_plane_z)) * 1.1; // Add margin
                            const float distance_camera_to_plane = abs(dot(_WorldSpaceCameraPos - p.position, normalize(p.normal)));
                            const float scaling_vs = distance_camera_to_plane < frustum_corner_length ? frustum_corner_length / distance_camera_to_plane : 1;

                            [unroll] for(uint i = 0; i < 4; i += 1) {
                                quad_vs[i] = scaling_vs * UnityWorldToViewPos(p.position + quad_corners[i].x * p.x_axis + quad_corners[i].y * p.y_axis);
                            }
                            emit_quad = true;
                        }
                    }

                    if(emit_quad) {
                        [unroll] for(uint i = 0; i < 4; i += 1) {
                            output.position_vs = quad_vs[i];
                            output.position = UnityViewToClipPos(output.position_vs);
                            output.grab_pos = ComputeGrabScreenPos(output.position);
                            stream.Append(output);
                        }
                    }
                }
            }

            float clamped_depth_from_world_position(float3 position) {
                float3 vs = UnityWorldToViewPos(position);
                vs.z = min(vs.z, -_ProjectionParams.y); // Ensure we are at near plane at minimum ; Z axis is ]-inf,0]
                const float4 cs = UnityViewToClipPos(vs);
                return cs.z / cs.w;
            }

            half4 fragment_stage (FragmentData input, out float output_depth : SV_Depth) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                #if defined(USING_STEREO_MATRICES)
                // Force evaluation here for VR mode. Workaround for "discard bug" (see commits). Removing the dynamic index helps.
                // Using the constant directly generates a miscompile in VR in case 1, which accessed garbage from the constant buffer.
                // This whole function is on the cliff to compiler internal error :(
                const float3 camera_ws = unity_StereoEyeIndex == 0 ? unity_StereoWorldSpaceCameraPos[0] : unity_StereoWorldSpaceCameraPos[1];
                #else
                const float3 camera_ws = _WorldSpaceCameraPos;
                #endif
                
                const float3 ray_ws = mul((float3x3) unity_MatrixInvV, input.position_vs);
                const float4 grab_pass_pixel = _Lereldarion_Portal_Seal_GrabPass[_Lereldarion_Portal_Seal_GrabPass_TexelSize.zw * input.grab_pos.xy / input.grab_pos.w];

                output_depth = UNITY_NEAR_CLIP_VALUE; // Default value
                
                [branch] if(grab_pass_pixel.a <= -1) {
                    // If pixel was from a portal-aware shader
                    const uint n = -(1 + grab_pass_pixel.a);
                    [forcecase] switch(n) {
                        case 0: {
                            // World space
                            discard;
                            break;
                        }
                        case 1: {
                            // Portal space without intersection : seal to near plane
                            output_depth = UNITY_NEAR_CLIP_VALUE;
                            break;
                        }
                        default: {
                            // Portal space with portal surface depth
                            const uint portal_id = n - 2;
                            const Portal portal = Portal::decode(_Portal_State, portal_id);
                            float ray_distance = 0;
                            portal.ray_intersect(camera_ws, ray_ws, ray_distance); // Should be success
                            output_depth = clamped_depth_from_world_position(camera_ws + ray_ws * ray_distance);
                            break;
                        }
                    }
                    return half4(grab_pass_pixel.rgb, 1);
                }

                // Portal world background

                // Scan portal for intersections
                uint intersect_count = 0;
                float max_intersection_ray_distance = 0;
                [loop] while(input.portal_mask) {
                    const uint index = pop_active_portal(input.portal_mask);
                    const PortalPixel0 p0 = PortalPixel0::decode(_Portal_State, index);
                    if(!p0.fast_intersect(camera_ws, camera_ws + ray_ws)) { continue; }
                    const Portal portal = Portal::decode(p0, _Portal_State, index);
                    
                    float ray_distance;
                    if(portal.ray_intersect(camera_ws, ray_ws, ray_distance)) {
                        intersect_count += 1;
                        max_intersection_ray_distance = max(max_intersection_ray_distance, ray_distance);
                    }
                }

                // If in portal, discard when intersect is odd
                // If in world, discard when intersect is even
                if(input.camera_in_portal == bool(intersect_count & 0x1)) {
                    discard;
                }
                
                // Depth logic : use the depth of the last portal intersection, which must go from world to portal.
                // Otherwise it would have been discarded.
                output_depth = clamped_depth_from_world_position(camera_ws + ray_ws * max_intersection_ray_distance);

                // TODO portal visuals
                return half4(0, 0, 0, 1);
            }
            ENDCG
        }

        Pass {
            Name "Portal Surfaces Shadowcaster"
	        Tags { "LightMode" = "ShadowCaster" }

            // Emit portal surfaces as opaque for shadows. FIXME needs improvements

            Cull Off

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing
            #pragma multi_compile_shadowcaster

            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage

            #include "UnityCG.cginc"
            #include "portal.hlsl"

            uniform Texture2D<uint4> _Portal_State;

            struct MeshData {
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct FragmentData {
                V2F_SHADOW_CASTER;

                nointerpolation bool is_ellipse : CAMERA_IN_PORTAL;
                float2 portal_axis_coords : PORTAL_AXIS_COORDS;
                
                UNITY_VERTEX_OUTPUT_STEREO
            };

            struct ShadowCasterAppData {
                // object space
                float3 vertex;
                float3 normal;
            };
            
            void vertex_stage (MeshData input, out MeshData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
            }

            [instance(32)]
            [maxvertexcount(4)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, uint instance : SV_GSInstanceID, inout TriangleStream<FragmentData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                // Input mesh just needs one point
                if(primitive_id != 0) { return ; }

                FragmentData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                const Header header = Header::decode(_Portal_State);
                if(header.is_enabled) {
                    const float2 quad[4] = { float2(-1, -1), float2(-1, 1), float2(1, -1), float2(1, 1) };
                    
                    // One quad per enabled portal
                    if(header.portal_mask & (0x1 << instance)) {
                        const Portal portal = Portal::decode(_Portal_State, instance);

                        ShadowCasterAppData v;
                        const bool normal_towards_camera = dot(_WorldSpaceCameraPos - portal.position, portal.normal) >= 0;
                        v.normal = UnityWorldToObjectDir(normal_towards_camera ? portal.normal : -portal.normal);

                        FragmentData output;
                        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                        output.is_ellipse = portal.is_ellipse;

                        [unroll] for(uint i = 0; i < 4; i += 1) {
                            output.portal_axis_coords = quad[i];
                            const float3 position_ws = portal.position + quad[i].x * portal.x_axis + quad[i].y * portal.y_axis;
                            v.vertex = mul(unity_WorldToObject, float4(position_ws, 1)).xyz;
                            TRANSFER_SHADOW_CASTER_NORMALOFFSET(output);
                            stream.Append(output);
                        }
                    }
                }
            }

            half4 fragment_stage (FragmentData input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Alpha cut ellipse shape from portal
                if(input.is_ellipse && dot(input.portal_axis_coords, input.portal_axis_coords) > 1) {
                    discard;
                }

                SHADOW_CASTER_FRAGMENT(input);
            }
            ENDCG
        }
    }
}
