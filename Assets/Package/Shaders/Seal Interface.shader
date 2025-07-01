
Shader "Lereldarion/Portal/Seal Interface" {
    Properties {
        [NoScaleOffset] _Portal_CRT("CRT texture", 2D) = ""
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

            uniform Texture2D<uint4> _Portal_CRT;
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

            [maxvertexcount(4)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, inout TriangleStream<FragmentData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                FragmentData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                // Just use the system point mesh as an iterator.
                // We have the guarantee that there is at least one point per portal.
                Header header = Header::decode_crt(_Portal_CRT);
                if(header.is_enabled) {
                    output.camera_in_portal = header.camera_in_portal[_VRChatCameraMode == 0 ? 0 : 1];
                    output.portal_mask = header.portal_mask;

                    const float2 quad[4] = { float2(-1, -1), float2(-1, 1), float2(1, -1), float2(1, 1) };

                    if(output.camera_in_portal) {
                        // One fullscreen quad
                        if(primitive_id == 0) {
                            // Generate in VS close to near clip plane. Having non CS positions is essential to return to WS later.
                            float near_plane_z = -_ProjectionParams.y;
                            float2 tan_half_fov = 1 / unity_CameraProjection._m00_m11; // https://jsantell.com/3d-projection/
                            // Add margins in case the matrix has some rotation/skew
                            float quad_z = near_plane_z * 1.2; // z margin
                            float quad_xy = quad_z * tan_half_fov * 1.2; // xy margin
                            
                            [unroll] for(uint i = 0; i < 4; i += 1) {
                                output.position_vs = float3(quad[i] * quad_xy, quad_z);
                                output.position = UnityViewToClipPos(output.position_vs);
                                output.grab_pos = ComputeGrabScreenPos(output.position);
                                stream.Append(output);
                            }
                        }
                    } else {
                        // One quad per enabled portal
                        if(primitive_id < 32 && header.portal_mask & (0x1 << primitive_id)) {
                            Portal p = Portal::decode_crt(_Portal_CRT, primitive_id);
                            [unroll] for(uint i = 0; i < 4; i += 1) {
                                output.position_vs = UnityWorldToViewPos(p.position + quad[i].x * p.x_axis + quad[i].y * p.y_axis);
                                output.position = UnityViewToClipPos(output.position_vs);
                                output.grab_pos = ComputeGrabScreenPos(output.position);
                                stream.Append(output);
                            }
                        }
                    }
                }
            }

            half4 fragment_stage (FragmentData input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float4 grab_pass_pixel = _Lereldarion_Portal_Seal_GrabPass[_Lereldarion_Portal_Seal_GrabPass_TexelSize.zw * input.grab_pos.xy / input.grab_pos.w];

                // Iterate over portals to check intersect count. Needs unbound intersect routine

                float3 ray_ws = normalize(mul((float3x3) unity_MatrixInvV, input.position_vs));

                // TODO out SV_Depth + impl
                // 
                return half4(grab_pass_pixel.a < 0, 0, 0, 1);
            }
            ENDCG
        }
    }
}
