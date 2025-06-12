// Export configuration of portal points to grabpass.

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

            
            struct MeshData {
                float3 position : POSITION;
                float3 normal : NORMAL;
                float3 tangent : TANGENT;
                float2 uv0 : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct PortalData {
                float3 position : W_POSITION;
                float3 x_axis : X_AXIS;
                float3 y_axis : Y_AXIS;
                float is_ellipse : IS_ELLIPSE;
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
                output.x_axis = mul((float3x3) unity_ObjectToWorld, input.normal);
                output.y_axis = mul((float3x3) unity_ObjectToWorld, input.tangent);
                output.is_ellipse = input.uv0.x;
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
            
            #include "lereldarion_portal.hlsl"
            
            [maxvertexcount(4)]
            void geometry_stage(point PortalData input[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);
                
                PixelData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                
                if(primitive_id == 0) {
                    // System control pixel
                    LPortal::System system;
                    system.mask = 0;
                    system.mask |= _Portal_Enabled_0 ? (0x1 << 0) : 0;
                    system.mask |= _Portal_Enabled_1 ? (0x1 << 1) : 0;
                    system.mask |= _Portal_Enabled_2 ? (0x1 << 2) : 0;
                    system.mask |= _Portal_Enabled_3 ? (0x1 << 3) : 0;
                    system.mask |= _Portal_Enabled_4 ? (0x1 << 4) : 0;
                    system.mask |= _Portal_Enabled_5 ? (0x1 << 5) : 0;
                    system.mask |= _Portal_Enabled_6 ? (0x1 << 6) : 0;
                    system.mask |= _Portal_Enabled_7 ? (0x1 << 7) : 0;
                    system.mask |= _Portal_Enabled_8 ? (0x1 << 8) : 0;
                    system.mask |= _Portal_Enabled_9 ? (0x1 << 9) : 0;
                    system.mask |= _Portal_Enabled_10 ? (0x1 << 10) : 0;
                    system.mask |= _Portal_Enabled_11 ? (0x1 << 11) : 0;
                    system.mask |= _Portal_Enabled_12 ? (0x1 << 12) : 0;
                    system.mask |= _Portal_Enabled_13 ? (0x1 << 13) : 0;
                    
                    output.position = screen_pixel_to_cs(float2(0, 0));
                    output.data = system.encode();
                    stream.Append(output);
                }

                // Portal pixels. Always rendered, receivers should use the control mask to ignore.
                LPortal::Portal portal;
                portal.position = input[0].position;
                portal.x_axis = input[0].x_axis;
                portal.y_axis = input[0].y_axis;
                portal.is_ellipse = input[0].is_ellipse > 0;
                float4 pixels[3];
                portal.encode(pixels);
                
                output.position = screen_pixel_to_cs(float2(1 + 3 * primitive_id, 0));
                output.data = pixels[0];
                stream.Append(output);
                output.position = screen_pixel_to_cs(float2(2 + 3 * primitive_id, 0));
                output.data = pixels[1];
                stream.Append(output);
                output.position = screen_pixel_to_cs(float2(3 + 3 * primitive_id, 0));
                output.data = pixels[2];
                stream.Append(output);
            }
            ENDCG
        }

        GrabPass {
            "_Lereldarion_Portal_Configuration"
        }
    }
}
