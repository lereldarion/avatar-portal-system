
Shader "Lereldarion/Portal/Seal Interface" {
    Properties {
        [NoScaleOffset] _Portal_State("Portal state texture", 2D) = ""
        _Portal_Seal_Stencil_Bit("Power of 2 bit used to avoid repetition when sealing", Integer) = 64
    }
    SubShader {
        Tags {
            "Queue" = "Geometry-160"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
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

            #include "UnityCG.cginc"

            #include "portal.hlsl"

            uniform Texture2D<uint4> _Portal_State;
            uniform float _VRChatCameraMode;

            // portal ids of pixels of objects in portal space
            uniform Texture2D<float4> _Lereldarion_Portal_Seal_GrabPass;
            uniform float4 _Lereldarion_Portal_Seal_GrabPass_TexelSize;

            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage
            
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
                output = input;
            }

            [instance(32)]
            [maxvertexcount(4)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, uint instance : SV_GSInstanceID, inout TriangleStream<FragmentData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                // Input mesh just needs one point
                if(primitive_id != 0) { return ; }

                FragmentData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                Header header = Header::decode(_Portal_State);
                if(header.is_enabled) {
                    uint camera_id = _VRChatCameraMode == 0 ? 0 : 1;
                    output.camera_in_portal = header.camera_in_portal[camera_id];
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
                            float quad_z = near_plane_z * 1.1; // z margin
                            float quad_xy = quad_z * tan_half_fov * 1.1; // xy margin
                            
                            [unroll] for(uint i = 0; i < 4; i += 1) {
                                quad_vs[i] = float3(quad_corners[i] * quad_xy, quad_z);
                            }
                            emit_quad = true;
                        }
                    } else {
                        // One quad per enabled portal
                        if(instance < 32 && header.portal_mask & (0x1 << instance)) {
                            Portal p = Portal::decode(_Portal_State, instance);

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

            half4 fragment_stage (FragmentData input, out float output_depth : SV_Depth) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float3 ray_ws = mul((float3x3) unity_MatrixInvV, input.position_vs);

                // If pixel was a portal object, keep color and seal at the portal id stored in alpha
                float4 grab_pass_pixel = _Lereldarion_Portal_Seal_GrabPass[_Lereldarion_Portal_Seal_GrabPass_TexelSize.zw * input.grab_pos.xy / input.grab_pos.w];
                uint portal_id;
                if(pixel_get_depth_portal_id(grab_pass_pixel, portal_id) && input.portal_mask & (0x1 << portal_id)) {
                    Portal p = Portal::decode(_Portal_State, portal_id);
                    float ray_distance = 0;
                    p.ray_intersect(_WorldSpaceCameraPos, ray_ws, ray_distance); // Should be success
                    float4 intersect_cs = UnityWorldToClipPos(_WorldSpaceCameraPos + ray_ws * ray_distance);
                    output_depth = intersect_cs.z / intersect_cs.w;
                    return half4(grab_pass_pixel.rgb, 1);
                }

                // Scan portal for intersections
                uint intersect_count = 0;
                [loop] while(input.portal_mask) {
                    uint index = pop_active_portal(input.portal_mask);
                    PortalPixel0 p0 = PortalPixel0::decode(_Portal_State, index);
                    if(!p0.is_enabled()) { break; }
                    if(!p0.fast_intersect(_WorldSpaceCameraPos, _WorldSpaceCameraPos + ray_ws)) { continue; }
                    Portal portal = Portal::decode(p0, _Portal_State, index);
                    
                    float ray_distance;
                    if(portal.ray_intersect(_WorldSpaceCameraPos, ray_ws, ray_distance)) {
                        intersect_count += 1;
                        // TODO handle distance
                    }
                }

                // If in portal, discard when intersect is odd
                // If in world, discard when intersect is even
                if(input.camera_in_portal == bool(intersect_count & 0x1)) {
                    discard;
                }
                
                // TODO depth logic
                output_depth = UNITY_NEAR_CLIP_VALUE;
                return half4(0, 0, 0, 1);
            }
            ENDCG
        }
    }
}
