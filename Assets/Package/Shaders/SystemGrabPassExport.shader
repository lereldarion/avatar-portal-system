// Export configuration of portal points to grabpass.

Shader "Lereldarion/Portal/SystemGrabPassExport" {
    Properties {
        // TODO force state change from menu for explicit synchro.
        // [ToggleUI] _Portal_Force_State("Force state TODO", Float) = 0
    }
    SubShader {
        Tags {
            "Queue" = "Geometry-765"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        Pass {
            Name "Encode"
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
            struct WorldMeshData {
                float3 position : W_POSITION;
                float3 normal : W_NORMAL;
                float3 tangent : W_TANGENT;
                float2 uv0 : UV0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct PixelData {
                float4 position : SV_POSITION;
                float4 data : DATA;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            void vertex_stage (MeshData input, out WorldMeshData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                output.position = mul(unity_ObjectToWorld, float4(input.position, 1)).xyz;
                output.normal = mul((float3x3) unity_ObjectToWorld, input.normal);
                output.tangent = mul((float3x3) unity_ObjectToWorld, input.tangent);
                output.uv0 = input.uv0;
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
            
            #include "portal_grabpass.hlsl"
            
            [maxvertexcount(6)]
            void geometry_stage(point WorldMeshData input_array[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                WorldMeshData input = input_array[0];
                UNITY_SETUP_INSTANCE_ID(input);
                
                PixelData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                
                if(primitive_id == 0) {
                    // System control pixel.
                    LP::System system;
                    system.mask = 0x3;                  
                    output.position = screen_pixel_to_cs(float2(0, 0));
                    output.data = system.encode();
                    stream.Append(output);
                }

                int vertex_type = input.uv0.x;

                switch(vertex_type) {
                    case 1: case 2: {
                        // Portal pixels. Always rendered, receivers should use the control mask to ignore.
                        LP::Portal portal;
                        portal.position = input.position;
                        portal.x_axis = input.normal;
                        portal.y_axis = input.tangent;
                        portal.is_ellipse = vertex_type == 2;
                        float4 pixels[3];
                        portal.encode(pixels);
                        
                        float portal_id = input.uv0.y;
                        output.position = screen_pixel_to_cs(float2(1 + 3 * portal_id, 0));
                        output.data = pixels[0];
                        stream.Append(output);
                        output.position = screen_pixel_to_cs(float2(2 + 3 * portal_id, 0));
                        output.data = pixels[1];
                        stream.Append(output);
                        output.position = screen_pixel_to_cs(float2(3 + 3 * portal_id, 0));
                        output.data = pixels[2];
                        stream.Append(output);
                        break;
                    }
                    default: break;
                }
            }
            ENDCG
        }

        GrabPass {
            "_Lereldarion_Portal_System_GrabPass"
            Name "Export"
        }
    }
}
