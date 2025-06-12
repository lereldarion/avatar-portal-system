
Shader "Lereldarion/Portal/DebugConfiguration" {
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
                
                void init_cs(inout LineStream<LinePoint> stream, float4 position_cs) {
                    output.position = position_cs;
                    stream.RestartStrip();
                    stream.Append(output);
                }
                void init_ws(inout LineStream<LinePoint> stream, float3 position_ws) {
                    init_cs(stream, UnityWorldToClipPos(position_ws));
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
            
            uniform Texture2D<float4> _Lereldarion_Portal_Configuration;
            #include "lereldarion_portal.hlsl"
            
            [maxvertexcount(5 * 14)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, inout LineStream<LinePoint> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                if(primitive_id > 0) { return; }

                LPortal::System system = LPortal::System::decode(_Lereldarion_Portal_Configuration[uint2(0, 0)]);

                [loop]
                while(system.has_portal()) {
                    uint index = system.next_portal();

                    float4 pixels[3] = {
                        _Lereldarion_Portal_Configuration[uint2(1 + 3 * index, 0)],
                        _Lereldarion_Portal_Configuration[uint2(2 + 3 * index, 0)],
                        _Lereldarion_Portal_Configuration[uint2(3 + 3 * index, 0)]
                    };
                    LPortal::Portal p = LPortal::Portal::decode(pixels);

                    LineDrawer drawer = LineDrawer::init(hue_shift_yiq(half3(1, 0, 0), index / 14.0 * UNITY_TWO_PI));
                    drawer.init_ws(stream,  p.position - p.x_axis - p.y_axis);
                    drawer.solid_ws(stream, p.position + p.x_axis - p.y_axis);
                    drawer.solid_ws(stream, p.position + p.x_axis + p.y_axis);
                    drawer.solid_ws(stream, p.position - p.x_axis + p.y_axis);
                    drawer.solid_ws(stream, p.position - p.x_axis - p.y_axis);
                }
            }
            ENDCG
        }
    }
}
