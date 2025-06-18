
Shader "Lereldarion/Portal/CRT" {
    Properties {
    }
    SubShader {
        Tags {
            "PreviewType" = "Plane"
        }

        ZTest Always
        ZWrite Off

        Pass {
            Name "Encode"

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
                        
            [maxvertexcount(6)]
            void geometry_stage(point WorldMeshData input_array[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                WorldMeshData input = input_array[0];
                UNITY_SETUP_INSTANCE_ID(input);
                
                PixelData output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
            }
            ENDCG
        }

    }
}
