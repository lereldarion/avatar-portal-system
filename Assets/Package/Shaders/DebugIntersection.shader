
Shader "Lereldarion/Portal/DebugIntersection" {
    Properties {
        _Color("Color", Color) = (1, 1, 1, 0)
    }
    SubShader {
        Tags {
            "Queue" = "Geometry"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        Pass {
            Name "Debug Intersection"

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            #pragma vertex vertex_stage
            #pragma fragment fragment_stage

            
            struct MeshData {
                float3 position : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct FragmentData  {
                float4 position : SV_POSITION;
                float3 world_position : WORLD_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            void vertex_stage (MeshData input, out FragmentData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.world_position = mul(unity_ObjectToWorld, float4(input.position, 1)).xyz;
                output.position = UnityWorldToClipPos(output.world_position);
            }
            
            #include "lereldarion_portal.hlsl"
            uniform Texture2D<float4> _Lereldarion_Portal_Configuration;

            uniform half4 _Color;

            half4 fragment_stage (FragmentData input) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Just test if any portal is here
                LPortal::System system = LPortal::System::decode(_Lereldarion_Portal_Configuration[uint2(0, 0)]);

                bool has_intersect = false;

                [loop]
                while(system.has_portal() && !has_intersect) {
                    uint index = system.next_portal();

                    float4 pixels[3] = {
                        _Lereldarion_Portal_Configuration[uint2(1 + 3 * index, 0)],
                        _Lereldarion_Portal_Configuration[uint2(2 + 3 * index, 0)],
                        _Lereldarion_Portal_Configuration[uint2(3 + 3 * index, 0)]
                    };
                    LPortal::Portal portal = LPortal::Portal::decode(pixels);

                    has_intersect = portal.segment_intersect(_WorldSpaceCameraPos, input.world_position);
                }

                if(has_intersect) { discard; }
                
                return _Color;
            }
            ENDCG
        }
    }
}
