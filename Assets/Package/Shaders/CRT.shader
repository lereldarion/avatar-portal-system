
Shader "Lereldarion/Portal/CRT" {
    Properties {
    }
    SubShader {
        Tags {
            "PreviewType" = "Plane"
        }

        ZTest Always
        ZWrite Off
        Lighting Off

        Pass {
            // Compact portal positions into 2 f32x4 per portal.
            // Use the flexcrt strategy (cnlohr) : geometry pass to blit at interesting places
            // https://github.com/cnlohr/flexcrt/blob/master/Assets/flexcrt_demo/ExampleFlexCRT.shader#L78

            Name "Process Portal configuration"

            CGPROGRAM
            #pragma target 5.0

            #include "UnityCustomRenderTexture.cginc"
            
            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage
            
            struct MeshData {
                uint vertex_id : SV_VertexID;
            };
            struct GeometryData {
                uint batch_id : BATCH_ID;
            };
            struct PixelData {
                float4 position : SV_POSITION;
                uint4 data : DATA;
            };
            
            void vertex_stage (MeshData input, out GeometryData output) {
                // CRT emit a quad per draw call, as 2 separate triangles (6 vertex)
                output.batch_id = input.vertex_id / 6;
            }
            
            uint4 fragment_stage (PixelData pixel) : SV_Target {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(pixel);
                return pixel.data;
            }
            
            float4 crt_pos_cs(uint2 pos) {
                float2 crt_size = _CustomRenderTextureInfo.xy;
                float4 pos_cs = float4((pos * 2 - crt_size + 1 ) / crt_size, UNITY_NEAR_CLIP_VALUE, 1);
                if (_ProjectionParams.x < 0) { pos_cs.y = -pos_cs.y; } // https://docs.unity3d.com/Manual/SL-PlatformDifferences.html
                return pos_cs;
            }

            #include "portal_grabpass.hlsl"
            Texture2D<float4> _Lereldarion_Portal_System_GrabPass;
            
            #include "portal_crt.hlsl"
                        
            [maxvertexcount(128)]
            void geometry_stage(point GeometryData input[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                // Compared to flexcrt we only want one thread that will scan all portals, so just get one iteration.
                if(primitive_id == 0) {
                    PixelData output;
                    
                    LP::System system = LP::System::decode(_Lereldarion_Portal_System_GrabPass[uint2(0, 0)]);
                    
                    uint active_portal_count = 0;
                    uint max_portal_scan_count = min(system.portal_count, 32);
                    [loop]
                    for(uint index = 0; index < max_portal_scan_count; index += 1) {
                        float4 pixels[3] = {
                            _Lereldarion_Portal_System_GrabPass[uint2(1 + 3 * index, 0)],
                            _Lereldarion_Portal_System_GrabPass[uint2(2 + 3 * index, 0)],
                            _Lereldarion_Portal_System_GrabPass[uint2(3 + 3 * index, 0)]
                        };
                        LP::Portal p = LP::Portal::decode(pixels);

                        Portal p2;
                        p2.position = p.position;
                        p2.x_axis = p.x_axis;
                        p2.y_axis = p.y_axis;
                        p2.is_ellipse = p.is_ellipse;
                        uint4 opixels[2];
                        p2.encode(opixels);
                        if(opixels[0].w > 0) {
                            output.position = crt_pos_cs(uint2(active_portal_count, 0));
                            output.data = opixels[0];
                            stream.Append(output);
                            output.position = crt_pos_cs(uint2(active_portal_count, 1));
                            output.data = opixels[1];
                            stream.Append(output);
                            active_portal_count += 1;
                        }
                    }

                    // Sentinel pixel with portal of radius 0
                    output.position = crt_pos_cs(uint2(active_portal_count, 0));
                    output.data = float4(0, 0, 0, 0);
                    stream.Append(output);
                }
            }
            ENDCG
        }

    }
}
