
// Encoding :
// 1 system control pixel at (0, 0) :
// - R = f16 sentinel value (>1) to check if system is enabled & grabpass is RGBA16_FLOAT and not RGBA8_UNORM. Currently UNITY_PI
// - G = u14 bitmask for enabled portals
// Portal i : 3 pixels at ([1..3]+3*i, 0).
// - Pixel 1 : xyzw as u14[0..3]
// - Pixel 2 : xyz = normal f16, w as u14[4]
// - Pixel 3 : xyz = tangent f16, w as u14[5]
// TODO ellipse bit

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

            static const int world_position_bits = 27;
            static const float world_position_precision = 0.001;

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

            uint floatToUint14(precise float input) {
                // https://github.com/pema99/shader-knowledge/blob/main/tips-and-tricks.md#encoding-and-decoding-data-in-a-grabpass
                uint output = (f32tof16(input)) & 0x00003fff;
                return output;
            }

            uniform Texture2D<float4> _Lereldarion_Portal_Configuration;

            [maxvertexcount(5 * 14)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, inout LineStream<LinePoint> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                if(primitive_id > 0) { return; }

                float4 system = _Lereldarion_Portal_Configuration[uint2(0, 0)];

                // Sentinel check
                if(abs(system.r - UNITY_PI) > 0.001) { return; }

                uint portal_mask = floatToUint14(system.g);
                [loop]
                while(portal_mask != 0) {
                    uint index = firstbitlow(portal_mask);
                    portal_mask ^= 0x1 << index;

                    float4 pixel_1 = _Lereldarion_Portal_Configuration[uint2(1 + 3 * index, 0)];
                    float4 pixel_2 = _Lereldarion_Portal_Configuration[uint2(2 + 3 * index, 0)];
                    float4 pixel_3 = _Lereldarion_Portal_Configuration[uint2(3 + 3 * index, 0)];

                    uint3 position_fp = uint3(
                        (floatToUint14(pixel_1[0]) << 14) | floatToUint14(pixel_1[1]),
                        (floatToUint14(pixel_1[2]) << 14) | floatToUint14(pixel_1[3]),
                        (floatToUint14(pixel_2[3]) << 14) | floatToUint14(pixel_3[3])
                    );
                    float3 position = (int3(position_fp) - int(0x1 << (world_position_bits - 1))) * world_position_precision;
                    float3 normal = pixel_2.xyz;
                    float3 tangent = pixel_3.xyz;

                    LineDrawer drawer = LineDrawer::init(hue_shift_yiq(half3(1, 0, 0), index / 14.0 * UNITY_TWO_PI));
                    drawer.init_ws(stream, position - normal - tangent);
                    drawer.solid_ws(stream, position + normal - tangent);
                    drawer.solid_ws(stream, position + normal + tangent);
                    drawer.solid_ws(stream, position - normal + tangent);
                    drawer.solid_ws(stream, position - normal - tangent);
                }
            }
            ENDCG
        }
    }
}
