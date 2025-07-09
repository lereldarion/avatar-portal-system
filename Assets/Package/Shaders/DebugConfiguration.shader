
Shader "Lereldarion/Portal/DebugConfiguration" {
    Properties {
        [NoScaleOffset] _Portal_State("State texture", 2D) = ""
    }
    SubShader {
        Tags {
            "Queue" = "Geometry"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        Pass {
            Name "Debug Configuration"

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            #include "portal.hlsl"

            uniform Texture2D<uint4> _Portal_State;
            uniform float4 _VRChatScreenCameraRot;
            uniform float4 _VRChatPhotoCameraRot;

            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage
            
            struct MeshData {
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct LinePoint {
                float4 position : SV_POSITION;
                half3 color : LINE_COLOR;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            void vertex_stage (MeshData input, out MeshData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
            }
            
            half4 fragment_stage (LinePoint line_point) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(line_point);
                return half4(line_point.color, 1);
            }
            
            struct LineDrawer {
                LinePoint output;
                
                static LineDrawer init(half3 color) {
                    LineDrawer drawer;
                    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(drawer.output);
                    drawer.output.color = color;
                    return drawer;
                }
                
                void solid_cs(inout LineStream<LinePoint> stream, float4 position_cs) {
                    output.position = position_cs;
                    stream.Append(output);
                }
                void solid_ws(inout LineStream<LinePoint> stream, float3 position_ws) {
                    solid_cs(stream, UnityWorldToClipPos(position_ws));
                }
            };
            
            half3 hue_shift_yiq(const half3 col, const half hueAngle) {
                const half3 k = 0.57735;
                const half sinAngle = sin(hueAngle);
                const half cosAngle = cos(hueAngle);
                return col * cosAngle + cross(k, col) * sinAngle + k * dot(k, col) * (1.0 - cosAngle);
            }

            float3 quaternion_rotate(float4 q, float3 v) {
                return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
            }
            
            [maxvertexcount(128)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, inout LineStream<LinePoint> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                if(primitive_id > 0) { return; }

                Header header = Header::decode(_Portal_State);
                [loop] while(header.portal_mask) {
                    uint index = pop_active_portal(header.portal_mask);
                    Portal p = Portal::decode(_Portal_State, index);

                    LineDrawer drawer = LineDrawer::init(hue_shift_yiq(half3(1, 0, 0), index / 8.0 * UNITY_TWO_PI));
                    stream.RestartStrip();
                    if(!p.is_ellipse) {
                        drawer.solid_ws(stream, p.position - p.x_axis - p.y_axis);
                        drawer.solid_ws(stream, p.position + p.x_axis - p.y_axis);
                        drawer.solid_ws(stream, p.position + p.x_axis + p.y_axis);
                        drawer.solid_ws(stream, p.position - p.x_axis + p.y_axis);
                        drawer.solid_ws(stream, p.position - p.x_axis - p.y_axis);
                    } else {
                        for(int i = 0; i < 9; i += 1) {
                            float2 r;
                            sincos(i/8. * UNITY_TWO_PI, r.x, r.y);
                            drawer.solid_ws(stream, p.position + r.x * p.x_axis + r.y * p.y_axis);
                        }
                    }
                }

                // Cameras
                for(uint index = 0; index < 2; index += 1) {
                    float3 position = CameraPosition::decode(_Portal_State, index);

                    float4 rotation = index == 0 ? _VRChatScreenCameraRot : _VRChatPhotoCameraRot;
                    
                    // Only display camera position if not the current one.
                    float s = 0.1;
                    if(distance(position, _WorldSpaceCameraPos) > s) {
                        bool in_portal = header.camera_in_portal[index];
                        LineDrawer drawer = LineDrawer::init(float3(in_portal, !in_portal, 0));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position - quaternion_rotate(rotation, float3(s, 0, 0)));
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation, float3(s, 0, 0)));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position - quaternion_rotate(rotation, float3(0, s, 0)));
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation, float3(0, s, 0)));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position - quaternion_rotate(rotation, float3(0, 0, s)));
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation, float3(0, 0, s)));
                    }
                }
            }
            ENDCG
        }
    }
}
