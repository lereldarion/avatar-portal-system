
// Encoding :
// 1 system control pixel at (0, 0) :
// - R = f16 sentinel value (>1) to check if system is enabled & grabpass is RGBA16_FLOAT and not RGBA8_UNORM. Currently UNITY_PI
// - G = u14 bitmask for enabled portals
// Portal i : 3 pixels at ([1..3]+3*i, 0).
// - Pixel 1 : xyzw as u14[0..3]
// - Pixel 2 : xyz = normal f16, w as u14[4]
// - Pixel 3 : xyz = tangent f16, w as u14[5]
// TODO ellipse bit

Shader "Lereldarion/Portal/ExportConfiguration" {
    Properties {
        [ToggleUI] _Portal_Enabled_0("Portal 0", Float) = 0
        [ToggleUI] _Portal_Enabled_1("Portal 1", Float) = 0
        [ToggleUI] _Portal_Enabled_2("Portal 2", Float) = 0
        [ToggleUI] _Portal_Enabled_3("Portal 3", Float) = 0
        [ToggleUI] _Portal_Enabled_4("Portal 4", Float) = 0
        [ToggleUI] _Portal_Enabled_5("Portal 5", Float) = 0
        [ToggleUI] _Portal_Enabled_6("Portal 6", Float) = 0
        [ToggleUI] _Portal_Enabled_7("Portal 7", Float) = 0
        [ToggleUI] _Portal_Enabled_8("Portal 8", Float) = 0
        [ToggleUI] _Portal_Enabled_9("Portal 9", Float) = 0
        [ToggleUI] _Portal_Enabled_10("Portal 10", Float) = 0
        [ToggleUI] _Portal_Enabled_11("Portal 11", Float) = 0
        [ToggleUI] _Portal_Enabled_12("Portal 12", Float) = 0
        [ToggleUI] _Portal_Enabled_13("Portal 13", Float) = 0
    }
    SubShader {
        Tags {
            "Queue" = "Geometry-765"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        Pass {
            Name "Export Configuration"
            ZTest Always
            ZWrite Off

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
                float3 position : POSITION;
                float3 normal : NORMAL;
                float3 tangent : TANGENT;
                float2 uv0 : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct PortalData {
                float3 position : W_POSITION;
                float3 normal : W_NORMAL;
                float3 tangent : W_TANGENT;
                float mode : MODE;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct PixelData {
                float4 position : SV_POSITION;
                float4 data : DATA;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            void vertex_stage (MeshData input, out PortalData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                output.position = mul(unity_ObjectToWorld, float4(input.position, 1)).xyz;
                output.normal = mul((float3x3) unity_ObjectToWorld, input.normal);
                output.tangent = mul((float3x3) unity_ObjectToWorld, input.tangent);
                output.mode = input.uv0.x;
                UNITY_TRANSFER_INSTANCE_ID(input, output);
            }

            float4 fragment_stage (PixelData pixel) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(pixel);
                return pixel.data;
            }

            float4 screen_pixel_to_cs(float2 pixel_coord) {
                float2 screen = _ScreenParams.xy;
                float2 position_cs = (pixel_coord * 2 - screen + 1) / screen; // +1 = center of pixels
                if (_ProjectionParams.x < 0) { position_cs.y = -position_cs.y; } // https://docs.unity3d.com/Manual/SL-PlatformDifferences.html
                return float4(position_cs, UNITY_NEAR_CLIP_VALUE, 1);
            }

            float uint14ToFloat(uint input) {
                // https://github.com/pema99/shader-knowledge/blob/main/tips-and-tricks.md#encoding-and-decoding-data-in-a-grabpass
                precise float output = f16tof32((input & 0x00003fff));
                return output;
            }

            uniform float _Portal_Enabled_0;
            uniform float _Portal_Enabled_1;
            uniform float _Portal_Enabled_2;
            uniform float _Portal_Enabled_3;
            uniform float _Portal_Enabled_4;
            uniform float _Portal_Enabled_5;
            uniform float _Portal_Enabled_6;
            uniform float _Portal_Enabled_7;
            uniform float _Portal_Enabled_8;
            uniform float _Portal_Enabled_9;
            uniform float _Portal_Enabled_10;
            uniform float _Portal_Enabled_11;
            uniform float _Portal_Enabled_12;
            uniform float _Portal_Enabled_13;

            [maxvertexcount(4)]
            void geometry_stage(point PortalData input[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                PixelData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                if(primitive_id == 0) {
                    // System control pixel
                    output.position = screen_pixel_to_cs(float2(0, 0));
                    uint portal_mask = 0;
                    portal_mask |= _Portal_Enabled_0 ? (0x1 << 0) : 0;
                    portal_mask |= _Portal_Enabled_1 ? (0x1 << 1) : 0;
                    portal_mask |= _Portal_Enabled_2 ? (0x1 << 2) : 0;
                    portal_mask |= _Portal_Enabled_3 ? (0x1 << 3) : 0;
                    portal_mask |= _Portal_Enabled_4 ? (0x1 << 4) : 0;
                    portal_mask |= _Portal_Enabled_5 ? (0x1 << 5) : 0;
                    portal_mask |= _Portal_Enabled_6 ? (0x1 << 6) : 0;
                    portal_mask |= _Portal_Enabled_7 ? (0x1 << 7) : 0;
                    portal_mask |= _Portal_Enabled_8 ? (0x1 << 8) : 0;
                    portal_mask |= _Portal_Enabled_9 ? (0x1 << 9) : 0;
                    portal_mask |= _Portal_Enabled_10 ? (0x1 << 10) : 0;
                    portal_mask |= _Portal_Enabled_11 ? (0x1 << 11) : 0;
                    portal_mask |= _Portal_Enabled_12 ? (0x1 << 12) : 0;
                    portal_mask |= _Portal_Enabled_13 ? (0x1 << 13) : 0;
                    output.data = float4(UNITY_PI, uint14ToFloat(portal_mask), 0, 0);
                    stream.Append(output);
                }

                // Portal pixels. Always rendered, receivers should use the control mask to ignore.
                uint3 position_fp = uint3(int3(input[0].position / world_position_precision) + int(0x1 << (world_position_bits - 1)));
                
                output.position = screen_pixel_to_cs(float2(1 + 3 * primitive_id, 0));
                output.data = float4(uint14ToFloat(position_fp.x >> 14), uint14ToFloat(position_fp.x), uint14ToFloat(position_fp.y >> 14), uint14ToFloat(position_fp.y));
                stream.Append(output);
                
                output.position = screen_pixel_to_cs(float2(2 + 3 * primitive_id, 0));
                output.data = float4(input[0].normal, uint14ToFloat(position_fp.z >> 14));
                stream.Append(output);
                
                output.position = screen_pixel_to_cs(float2(3 + 3 * primitive_id, 0));
                output.data = float4(input[0].tangent, uint14ToFloat(position_fp.z));
                stream.Append(output);
            }
            ENDCG
        }

        GrabPass {
            "_Lereldarion_Portal_Configuration"
        }
    }
}
