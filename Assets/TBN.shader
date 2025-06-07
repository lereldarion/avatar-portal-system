// Made by Lereldarion (https://github.com/lereldarion/unity-shaders)
// Free to redistribute under the MIT license

// Displays the tangent space vectors as lines for each mesh vertex.
// Useful for debugging.

Shader "Lereldarion/Debug/TBN" {
    Properties {
        _Display_Length_Fraction("Vector length as fraction of triangle edge lengths", Range(0, 2)) = 1
        [ToggleUI] _DisplayMeshBinormal("Display mesh binormal (with tangent.w) instead of cross", Float) = 0
    }
    SubShader {
        Tags {
            "Queue" = "Overlay"
            "RenderType" = "Overlay"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }
        
        Cull Off
        ZWrite Off
        ZTest Less
        
        Pass {
            CGPROGRAM
            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage
            #pragma multi_compile_instancing
            
            #include "UnityCG.cginc"
            #pragma target 5.0

            struct VertexInput {
                float4 position_os : POSITION;
                float3 normal_os : NORMAL;
                float4 tangent_os : TANGENT;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct FragmentInput {
                float4 position : SV_POSITION; // CS as rasterizer input, screenspace as fragment input
                float3 color : EDGE_COLOR;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            void vertex_stage (VertexInput input, out VertexInput output) {
                output = input;
            }
            
            uniform float _Display_Length_Fraction;
            uniform float _DisplayMeshBinormal;

            void draw_vector(inout LineStream<FragmentInput> stream, float3 origin, float3 direction, float3 color) {
                FragmentInput output;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.color = color;

                output.position = UnityObjectToClipPos(origin);
                stream.Append(output);
                
                output.position = UnityObjectToClipPos(origin + direction);
                stream.Append(output);

                stream.RestartStrip();
            }
            void draw_tbn(inout LineStream<FragmentInput> stream, VertexInput input, float length) {
                draw_vector(stream, input.position_os, input.tangent_os.xyz * length, float3(1, 0, 0));
                float3 binormal = cross(normalize(input.normal_os), input.tangent_os.xyz);
                if (_DisplayMeshBinormal) {
                    binormal *= input.tangent_os.w;
                }
                draw_vector(stream, input.position_os, binormal * length, float3(0, 1, 0));
                draw_vector(stream, input.position_os, input.normal_os * length, float3(0, 0, 1));
            }

            float length_sq(float3 v) {
                return dot(v, v);
            }

            [maxvertexcount(6)]
            void geometry_stage(point VertexInput input[1], uint triangle_id : SV_PrimitiveID, inout LineStream<FragmentInput> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);

                float display_length = _Display_Length_Fraction;
                draw_tbn(stream, input[0], display_length);
            }

            fixed4 fragment_stage (FragmentInput input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                return fixed4(input.color, 1);
            }
            ENDCG
        }
    }
}
