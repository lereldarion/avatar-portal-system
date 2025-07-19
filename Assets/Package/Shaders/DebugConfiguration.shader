
Shader "Lereldarion/Portal/DebugConfiguration" {
    Properties {
        [NoScaleOffset] _Portal_State("State texture", 2D) = ""
        [ToggleUI] _Portal_Debug_Show("Show anything", Integer) = 1
        [ToggleUI] _Portal_Debug_Show_Camera("Show cameras", Integer) = 0
    }
    SubShader {
        Tags {
            "Queue" = "Overlay"
            "VRCFallback" = "Hidden"
            "PreviewType" = "Plane"
        }

        Pass {
            Name "Debug Configuration"

            ZTest Always
            ZWrite On

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_instancing
            #pragma vertex vertex_stage
            #pragma geometry geometry_stage
            #pragma fragment fragment_stage

            #include "UnityCG.cginc"
            #include "portal.hlsl"

            uniform Texture2D<uint4> _Portal_State;
            uniform Texture2D<half4> _Lereldarion_Portal_Seal_GrabPass;
            uniform float4 _VRChatScreenCameraRot;
            uniform float4 _VRChatPhotoCameraRot;
            uniform uint _Portal_Debug_Show;
            uniform uint _Portal_Debug_Show_Camera;

            struct MeshData {
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct LinePoint {
                float4 position : SV_POSITION;
                half3 color : LINE_COLOR;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            void vertex_stage (MeshData input, out MeshData output) {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
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

                void set_color(half3 color) { output.color = color; }
                void solid_cs(inout LineStream<LinePoint> stream, float4 position_cs) { output.position = position_cs; stream.Append(output); }
                void solid_ws(inout LineStream<LinePoint> stream, float3 position_ws) { solid_cs(stream, UnityWorldToClipPos(position_ws)); }
                void solid_cs(inout LineStream<LinePoint> stream, float4 position_cs, half3 color) { set_color(color); solid_cs(stream, position_cs); }
                void solid_ws(inout LineStream<LinePoint> stream, float3 position_ws, half3 color) { set_color(color); solid_ws(stream, position_ws); }
            };
            
            half3 hue_shift_yiq(const half3 col, const half hueAngle) {
                const half3 k = 0.57735;
                const half sinAngle = sin(hueAngle);
                const half cosAngle = cos(hueAngle);
                return col * cosAngle + cross(k, col) * sinAngle + k * dot(k, col) * (1.0 - cosAngle);
            }

            float3 quaternion_rotate(float4 q, float3 v) {
                return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
            }
            
            [instance(32)]
            [maxvertexcount(9 + 6 + 2 * 10)]
            void geometry_stage(point MeshData input[1], uint primitive_id : SV_PrimitiveID, uint instance : SV_GSInstanceID, inout LineStream<LinePoint> stream) {
                UNITY_SETUP_INSTANCE_ID(input[0]);
                if(primitive_id > 0 || !_Portal_Debug_Show) { return; }

                LineDrawer drawer = LineDrawer::init(half3(0, 0, 0));
                const Header header = Header::decode(_Portal_State);

                // Draw portals
                if((0x1 << instance) & header.portal_mask) {
                    const Portal p = Portal::decode(_Portal_State, instance);
                    drawer.set_color(hue_shift_yiq(half3(1, 0, 0), instance / 8.0 * UNITY_TWO_PI));
                    if(!p.is_ellipse) {
                        drawer.solid_ws(stream, p.position - p.x_axis - p.y_axis);
                        drawer.solid_ws(stream, p.position + p.x_axis - p.y_axis);
                        drawer.solid_ws(stream, p.position + p.x_axis + p.y_axis);
                        drawer.solid_ws(stream, p.position - p.x_axis + p.y_axis);
                        drawer.solid_ws(stream, p.position - p.x_axis - p.y_axis);
                    } else {
                        for(int i = 0; i < 9; i += 1) {
                            float2 r;
                            sincos(i/8. * UNITY_TWO_PI, r.x, r.y);
                            drawer.solid_ws(stream, p.position + r.x * p.x_axis + r.y * p.y_axis);
                        }
                    }
                }
                
                // Cameras
                if(_Portal_Debug_Show_Camera && instance < 2) {
                    const float3 position = CameraPosition::decode(_Portal_State, instance);
                    const float4 rotation = instance == 0 ? _VRChatScreenCameraRot : _VRChatPhotoCameraRot;
                    
                    // Only display camera position if not the current one.
                    const float s = 0.1;
                    if(distance(position, _WorldSpaceCameraPos) > s) {
                        const bool in_portal = header.camera_in_portal[instance];
                        drawer.set_color(half3(in_portal, !in_portal, 0));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation, -float3(s, 0, 0)));
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation,  float3(s, 0, 0)));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation, -float3(0, s, 0)));
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation,  float3(0, s, 0)));
                        stream.RestartStrip();
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation, -float3(0, 0, s)));
                        drawer.solid_ws(stream, position + quaternion_rotate(rotation,  float3(0, 0, s)));
                    }
                }

                // Mesh Probes
                for(uint column = 0; column * 32 + instance < header.mesh_probe_count; column += 1) {
                    const MeshProbeState state = MeshProbeState::decode(_Portal_State[uint2(3 + column, instance)]);
                    const MeshProbeConfig config = MeshProbeConfig::decode(_Portal_State[uint2(3 + column, instance + 32)]);
                    if(config.parent != MeshProbeConfig::no_parent) {
                        const MeshProbeState parent_state = MeshProbeState::decode(_Portal_State, config.parent);
                        stream.RestartStrip();
                        drawer.solid_ws(stream, state.position, half3(state.in_portal, !state.in_portal, 0));
                        drawer.solid_ws(stream, parent_state.position, half3(parent_state.in_portal, !parent_state.in_portal, 0));
                    }
                }
            }
            ENDCG
        }
    }
}
