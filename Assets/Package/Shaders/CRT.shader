
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
            
            #include "portal.hlsl"
            Texture2D<float4> _Lereldarion_Portal_System_GrabPass;

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
                        
            [maxvertexcount(128)]
            void geometry_stage(point GeometryData input[1], uint primitive_id : SV_PrimitiveID, inout PointStream<PixelData> stream) {
                // Compared to flexcrt we only want one thread that will scan all portals, so just get one iteration.
                if(primitive_id == 0) {
                    PixelData output;
                    
                    System system = System::decode_grabpass(_Lereldarion_Portal_System_GrabPass);
                    
                    uint active_portal_count = 0;
                    uint max_portal_scan_count = min(system.portal_count, 32);
                    [loop]
                    for(uint index = 0; index < max_portal_scan_count; index += 1) {
                        Portal p = Portal::decode_grabpass(_Lereldarion_Portal_System_GrabPass, index);
                        if(p.is_enabled()) {
                            uint4 pixels[2];
                            p.encode_crt(pixels);
                            for(uint i = 0; i < 2; i += 1) {
                                output.position = target_pixel_to_cs(uint2(active_portal_count, i), _CustomRenderTextureInfo.xy);
                                output.data = pixels[i];
                                stream.Append(output);
                            }
                            active_portal_count += 1;
                        }
                    }

                    // Sentinel pixel with portal of radius 0
                    output.position = target_pixel_to_cs(uint2(active_portal_count, 0), _CustomRenderTextureInfo.xy);
                    output.data = PortalPixel0::encode_disabled_crt();
                    stream.Append(output);
                }
            }
            ENDCG
        }

    }
}
