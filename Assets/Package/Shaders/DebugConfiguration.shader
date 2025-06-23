
Shader "Lereldarion/Portal/DebugConfiguration" {
    Properties {
        [KeywordEnum(GrabPass,CRT)] _Portal_Data_Source("Data source", Float) = 0
        [NoScaleOffset] _Portal_CRT("CRT texture", 2D) = ""
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

            #pragma shader_feature _PORTAL_DATA_SOURCE_GRABPASS _PORTAL_DATA_SOURCE_CRT

            #include "UnityCG.cginc"

            #include "portal.hlsl"

            uniform Texture2D<float4> _Lereldarion_Portal_System_GrabPass;
            uniform Texture2D<uint4> _Portal_CRT;

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
                output = input;
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
            
            [maxvertexcount(128)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, inout LineStream<LinePoint> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                if(primitive_id > 0) { return; }

                #ifdef _PORTAL_DATA_SOURCE_CRT
                Header header = Header::decode_crt(_Portal_CRT);
                [loop]
                while(header.has_portals()) {
                    uint index = header.pop_active_portal();
                    PortalPixel0 p0 = PortalPixel0::decode_crt(_Portal_CRT, index);
                    if(!p0.is_enabled()) { break; }
                    Portal p = Portal::decode_crt(p0, _Portal_CRT, index);
                #else
                [loop]
                for(uint index = 0; index < 32; index += 1) {
                    Portal p = Portal::decode_grabpass(_Lereldarion_Portal_System_GrabPass, index);
                    if(abs(dot(p.x_axis, p.y_axis)) > 0.01) { break; } // Count only provided to CRT, so here try to detect garbage values
                #endif

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

                #ifdef _PORTAL_DATA_SOURCE_CRT
                // Cameras
                for(uint index = 0; index < 2; index += 1) {
                    float3 position = CameraPosition::decode_crt(_Portal_CRT, index);
                    
                    // Only display camera position if not the current one.
                    float s = 0.1;
                    if(distance(position, _WorldSpaceCameraPos) > s) {
                        bool in_portal = header.camera_in_portal[index];
                        LineDrawer drawer = LineDrawer::init(float3(in_portal, !in_portal, 0));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position - float3(s, 0, 0));
                        drawer.solid_ws(stream, position + float3(s, 0, 0));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position - float3(0, s, 0));
                        drawer.solid_ws(stream, position + float3(0, s, 0));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position - float3(0, 0, s));
                        drawer.solid_ws(stream, position + float3(0, 0, s));
                    }
                }
                #endif
            }
            ENDCG
        }
    }
}
