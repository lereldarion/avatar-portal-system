using System.Linq;
using System.Collections.Generic;
using AnimatorAsCode.V1;
using nadena.dev.ndmf;
using UnityEngine;

[assembly: ExportsPlugin(typeof(Lereldarion.Portal.GeneratePortalSystemPlugin))]

namespace Lereldarion.Portal
{
    public class GeneratePortalSystemPlugin : Plugin<GeneratePortalSystemPlugin>
    {
        public override string DisplayName => "Lereldarion Portal System";

        protected override void Configure()
        {
            InPhase(BuildPhase.Generating).Run(DisplayName, Generate);
        }

        private void Generate(BuildContext ctx)
        {
            var aac = AacV1.Create(new AacConfiguration
            {
                SystemName = "Portal",
                AnimatorRoot = ctx.AvatarRootTransform,
                DefaultValueRoot = ctx.AvatarRootTransform,
                AssetKey = UnityEditor.GUID.Generate().ToString(),
                AssetContainer = ctx.AssetContainer,
                ContainerMode = AacConfiguration.Container.OnlyWhenPersistenceRequired,
                DefaultsProvider = new AacDefaultsProvider()
            });
            var animator_context = new AnimatorContext
            {
                Aac = aac,
                Controller = aac.NewAnimatorController(),
            };

            foreach (var system in ctx.AvatarRootTransform.GetComponentsInChildren<PortalSystem>(true))
            {
                var generated_meshes = SetupPortalSystem(system, animator_context);
                ctx.AssetSaver.SaveAssets(generated_meshes); // Required for proper upload
            }

            var ma_object = new GameObject("Portal_Animator") { transform = { parent = ctx.AvatarRootTransform } };
            var ma = AnimatorAsCode.V1.ModularAvatar.MaAc.Create(ma_object);
            ma.NewMergeAnimator(animator_context.Controller, VRC.SDK3.Avatars.Components.VRCAvatarDescriptor.AnimLayerType.FX);
        }

        /// <summary>
        /// System information is encoded into points that will be skinned to runtime locations.
        /// uv0.x is the type of object.
        /// 
        /// Portal : encode XY direction and lengths into normal / tangent.
        /// </summary>
        private class Vertex
        {
            /// <summary>Position, bone assignment.</summary>
            public Transform transform;
            /// <summary>Override for position within transform</summary>
            public Vector3 localPosition = Vector3.zero;
            public Vector3 normal = Vector3.forward;
            public Vector3 tangent = Vector3.right;
            /// <summary>x is the type of object (<see cref="VertexType"/>)</summary>
            public Vector3 uv0;
        };

        private enum VertexType
        {
            /// <summary>Point to force occlusion on update cameras</summary>
            Ignored = 0,
            QuadPortal = 1,
            EllipsePortal = 2,
            MeshProbe = 3,
        }

        /// <summary>
        /// Create portal mesh renderer, animator layers, gameobjects from descriptor components.
        /// Remove descriptors from the ndmf copy, to allow d4rkAvatarOptimizer to see no reference to gameobjects and merge properly.
        /// </summary>
        /// <param name="system">Controller root component : start of search for descriptors, and location where renderer is added</param>
        /// <returns>Reference to the created mesh, to be saved as asset by ndmf</returns>
        private Mesh[] SetupPortalSystem(PortalSystem system, AnimatorContext animator)
        {
            List<Mesh> generated_meshes = new List<Mesh>();
            Transform root = system.transform;

            // Scan portal system components
            var vertices = new List<Vertex>();
            var context = new Context { System = system, Vertices = vertices };
            foreach (var portal in system.ScanRoot.GetComponentsInChildren<PortalSurface>(true)) { SetupPortalSurface(portal, context); }
            SetupMeshProbes(context);

            // Make system skinned mesh
            {
                // Add a vertex inside update loop cameras to ensure that they will see the system mesh
                vertices.Add(new Vertex
                {
                    transform = context.System.transform,
                    uv0 = new Vector3((float)VertexType.Ignored, 0, 0),
                });

                Mesh mesh = new Mesh();
                mesh.vertices = vertices.Select(vertex => root.InverseTransformPoint(vertex.transform.TransformPoint(vertex.localPosition))).ToArray();
                mesh.SetNormals(vertices.Select(vertex => root.InverseTransformVector(vertex.transform.TransformVector(vertex.normal))).ToArray());
                mesh.SetTangents(vertices.Select(vertex =>
                {
                    Vector3 v = root.InverseTransformVector(vertex.transform.TransformVector(vertex.tangent));
                    return new Vector4(v.x, v.y, v.z, 1f);
                }).ToArray());
                mesh.SetUVs(0, vertices.Select(vertex => vertex.uv0).ToArray());
                mesh.SetIndices(Enumerable.Range(0, vertices.Count()).ToArray(), MeshTopology.Points, 0);

                // Merge identical transforms
                Transform[] bones = vertices.Select(vertex => vertex.transform).Distinct().ToArray();
                mesh.bindposes = bones.Select(bone => bone.worldToLocalMatrix * root.localToWorldMatrix).ToArray();

                Dictionary<Transform, int> bone_id_mapping = Enumerable.Range(0, bones.Length).ToDictionary(id => bones[id], id => id);
                mesh.boneWeights = vertices.Select(vertex =>
                {
                    var bw = new BoneWeight();
                    bw.boneIndex0 = bone_id_mapping[vertex.transform];
                    bw.weight0 = 1;
                    return bw;
                }).ToArray();

                SkinnedMeshRenderer renderer = root.gameObject.AddComponent<SkinnedMeshRenderer>();
                renderer.sharedMesh = mesh;
                renderer.bones = bones;
                renderer.sharedMaterial = system.Update;

                // The system renderer only needs to be seen by update cameras, so make its bounds small
                renderer.localBounds = new Bounds { center = Vector3.zero, extents = 0.01f * Vector3.one };

                generated_meshes.Add(mesh);
            }

            system.Update.SetInteger("_Portal_Count", context.PortalCount);
            system.Update.SetInteger("_Mesh_Probe_Count", context.MeshProbeCount);
            system.Update.SetFloat("_Camera0_FarPlane", context.System.Camera0.farClipPlane);
            system.Update.SetFloat("_Camera1_FarPlane", context.System.Camera1.farClipPlane);

            // Make single point mesh for visuals.
            {
                // MeshRenderer is already set ; just add a mesh filter with generated mesh
                Mesh mesh = new Mesh();
                mesh.vertices = new Vector3[] { Vector3.zero };
                mesh.SetIndices(new int[] { 0 }, MeshTopology.Points, 0);
                mesh.bounds = new Bounds { center = Vector3.zero, extents = Vector3.one };

                MeshFilter filter = context.System.Visuals.gameObject.AddComponent<MeshFilter>();
                filter.sharedMesh = mesh;

                generated_meshes.Add(mesh);
            }

            // Init animation
            {
                var layer = animator.Controller.NewLayer("Portal Init");
                var clip = animator.Aac.NewClip();

                // Extend bounding box with animator.
                clip.Scaling(context.System.Visuals.transform, context.System.OcclusionBoxSize * Vector3.one);

                // Disable cameras and enable at runtime for VRC rules. Tested
                context.System.Camera0.enabled = false;
                context.System.Camera1.enabled = false;
                clip.TogglingComponent(context.System.Camera0, true);
                clip.TogglingComponent(context.System.Camera1, true);

                layer.NewState("Init").WithAnimation(clip);
            }

            Object.DestroyImmediate(system); // Cleanup components
            return generated_meshes.ToArray();
        }

        private class Context
        {
            public PortalSystem System;
            public List<Vertex> Vertices;
            public int PortalCount = 0;
            public int MeshProbeCount = 0;
        }
        private class AnimatorContext
        {
            public AacFlBase Aac;
            public AacFlController Controller;
        }

        /// <summary>
        /// Generate a system mesh point for the portal
        /// </summary>
        /// <param name="portal">Portal descriptor</param>
        /// <param name="context">Data of the current portal system being built</param>
        private void SetupPortalSurface(PortalSurface portal, Context context)
        {
            VertexType vertex_type = portal.Shape == PortalSurface.ShapeType.Rectangle ? VertexType.QuadPortal : VertexType.EllipsePortal;
            int portal_id = context.PortalCount; context.PortalCount += 1;

            context.Vertices.Add(new Vertex
            {
                transform = portal.transform,
                normal = new Vector3(portal.Size.x, 0, 0),
                tangent = new Vector3(0, portal.Size.y, 0),
                uv0 = new Vector3((float)vertex_type, (float)portal_id, 0),
            });

            Object.DestroyImmediate(portal); // Cleanup components
        }

        private class MeshProbeCandidate
        {
            public int index;
            public Transform bone;
            /// <summary>List of vertices local positions with respect to bone</summary>
            public List<Vector3> vertices = new List<Vector3>();
        };

        /// <summary>
        /// Generate a system mesh point for every mesh probe.
        /// This is 2-pass to establish parent links properly.
        /// </summary>
        /// <param name="scan_root">Transform to start scanning from</param>
        /// <param name="context">Data of the current portal system being built</param>
        private void SetupMeshProbes(Context context)
        {
            var probe_list = new List<MeshProbeCandidate>();
            var probe_mapping = new Dictionary<Transform, MeshProbeCandidate>();
            MeshProbeCandidate probe_for_bone(Transform bone)
            {
                if (probe_mapping.TryGetValue(bone, out MeshProbeCandidate probe))
                {
                    return probe;
                }
                else
                {
                    var merged_to_parent = bone.parent.GetComponentInParent<PortalMeshProbeMergeChildren>(true);
                    if (merged_to_parent != null && merged_to_parent.transform.IsChildOf(context.System.ScanRoot))
                    {
                        var merged_probe = probe_for_bone(merged_to_parent.transform);
                        probe_mapping.Add(bone, merged_probe);
                        return merged_probe;
                    }

                    // Actually create a probe
                    var new_probe = new MeshProbeCandidate { index = probe_list.Count, bone = bone };
                    probe_list.Add(new_probe);
                    probe_mapping.Add(bone, new_probe);
                    return new_probe;
                }
            }

            // Scan all renderer vertices, generate probes and UV tags
            foreach (Renderer renderer in context.System.ScanRoot.GetComponentsInChildren<Renderer>(true))
            {
                // Only touch non system renderers.
                // TODO add blacklist ?
                if (renderer == context.System.Visuals) { continue; }

                SkinnedMeshRenderer skinned_mesh_renderer = renderer as SkinnedMeshRenderer;
                MeshRenderer mesh_renderer = renderer as MeshRenderer;
                if (skinned_mesh_renderer != null)
                {
                    Mesh mesh = skinned_mesh_renderer.sharedMesh;
                    Vector3[] vertices = mesh.vertices;

                    Vector2[] uv_probe_tag = new Vector2[mesh.vertexCount];

                    // Pre-compute probe relations to bones
                    Transform[] bones = skinned_mesh_renderer.bones;
                    Matrix4x4[] bindposes = mesh.bindposes;
                    Dictionary<Transform, int> bone_id_mapping = Enumerable.Range(0, bones.Length).ToDictionary(id => bones[id], id => id);
                    int associate_to_probe(int bone_id, Vector3 vertex)
                    {
                        // Defer creating probe to here, to only create probe for bones that are used.
                        MeshProbeCandidate probe = probe_for_bone(bones[bone_id]);
                        probe.vertices.Add(bindposes[bone_id_mapping[probe.bone]].MultiplyPoint3x4(vertex));
                        return probe.index;
                    }

                    // https://docs.unity3d.com/ScriptReference/Mesh.GetAllBoneWeights.html iteration scheme
                    var bone_per_vertex = mesh.GetBonesPerVertex();
                    var bone_weights = mesh.GetAllBoneWeights();
                    int bw_array_offset = 0;
                    for (int vertex_id = 0; vertex_id < mesh.vertexCount; vertex_id += 1)
                    {
                        int influence_count = bone_per_vertex[vertex_id];
                        Vector3 vertex = vertices[vertex_id];

                        // Vertex weights in decreasing order of influence ; use first 2.
                        uv_probe_tag[vertex_id] = new Vector2(
                            influence_count >= 1 ? associate_to_probe(bone_weights[bw_array_offset].boneIndex, vertex) : -1,
                            influence_count >= 2 ? associate_to_probe(bone_weights[bw_array_offset + 1].boneIndex, vertex) : -1
                        );
                        bw_array_offset += influence_count;
                    }

                    // Edit mesh in place. No save to assets & swap so it will not be persistent, but sufficient for upload.
                    mesh.SetUVs(context.System.MeshProbeUvChannel, uv_probe_tag);
                }
                else if (mesh_renderer != null)
                {
                    // TODO
                }
            }

            Debug.Log(probe_list.Count);
            Debug.Log($"Probe transforms: {string.Join(", ", probe_list.Select(probe => probe.bone.name).ToArray())}");

            /*
            // Initial scan, create vertices without defined parents.
            foreach (PortalMeshProbeOverride probe in context.System.ScanRoot.GetComponentsInChildren<PortalMeshProbeOverride>(true))
            {
                int probe_id = context.MeshProbeCount; context.MeshProbeCount += 1;

                probe_vertex_ids.Add(probe, context.Vertices.Count);
                context.Vertices.Add(new Vertex
                {
                    transform = probe.transform,
                    localPosition = probe.LocalPosition,
                    // Retrieve scaled radius from normal length
                    normal = new Vector3(probe.Radius, 0, 0),
                    // Start with "null" (-1) parent id. Will be filled later when all probes have been seen.
                    uv0 = new Vector3((float)VertexType.MeshProbe, (float)probe_id, -1f),
                });
            }
            
            // Finalize parent links
            foreach (var (probe, vertex_id) in probe_vertex_ids)
            {
                PortalMeshProbeOverride parent = probe.Parent;
                if (parent != null)
                {
                    int parent_probe_vertex_id = probe_vertex_ids[parent];
                    float parent_probe_id = context.Vertices[parent_probe_vertex_id].uv0.y;
                    context.Vertices[vertex_id].uv0.z = parent_probe_id;
                }
            }

            // Cleanup components
            foreach (var probe in probe_vertex_ids.Keys)
            {
                Object.DestroyImmediate(probe);
            }
            */
        }
    }
}