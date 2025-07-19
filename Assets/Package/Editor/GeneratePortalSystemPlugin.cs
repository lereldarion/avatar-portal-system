using System.Linq;
using System.Collections.Generic;
using AnimatorAsCode.V1;
using nadena.dev.ndmf;
using UnityEngine;
using AnimatorAsCode.V1.VRC;

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

                Dictionary<Transform, int> bone_id_mapping = Enumerable.Range(0, bones.Length).ToDictionary(i => bones[i], i => i);
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
                SkinnedMeshRenderer camera_loop_renderer = root.GetComponent<SkinnedMeshRenderer>();

                var layer = animator.Controller.NewLayer("Portal Init");

                var start = layer.NewState("Start");

                var set_local = layer.NewState("Set Local").WithAnimation(animator.Aac.NewClip()
                    .Animating(edit => edit.Animates(camera_loop_renderer, "material._IsLocal").WithOneFrame(1))
                );

                var clip = animator.Aac.NewClip();

                // Extend bounding box with animator.
                clip.Scaling(context.System.Visuals.transform, context.System.OcclusionBoxSize * Vector3.one);

                // Disable cameras and enable at runtime for VRC rules. Tested
                context.System.Camera0.enabled = false;
                context.System.Camera1.enabled = false;
                clip.TogglingComponent(context.System.Camera0, true);
                clip.TogglingComponent(context.System.Camera1, true);

                var setup = layer.NewState("Init").WithAnimation(clip);

                start.TransitionsTo(set_local).When(layer.Av3().IsLocal.IsTrue());
                set_local.AutomaticallyMovesTo(setup);
                start.TransitionsTo(setup).When(layer.Av3().IsLocal.IsFalse());
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

        private class MeshProbe
        {
            public int index;
            public Transform transform;
            /// <summary>List of vertices local positions with respect to bone</summary>
            public List<Vector3> vertices = new List<Vector3>();
            /// <summary>Filled in a second phase</summary>
            public MeshProbe parent = null;
        };

        /// <summary>
        /// Generate a system mesh point for every mesh probe.
        /// Organise the mesh probe tree(s).
        /// Tag head children to recreate head chop. TODO read headchop components for fine control ?
        /// </summary>
        /// <param name="scan_root">Transform to start scanning from</param>
        /// <param name="context">Data of the current portal system being built</param>
        private void SetupMeshProbes(Context context)
        {
            var probe_list = new List<MeshProbe>(); // List of unique probes
            var probe_mapping = new Dictionary<Transform, MeshProbe>(); // Duplicates with bone merges

            MeshProbe probe_for_transform(Transform transform)
            {
                if (probe_mapping.TryGetValue(transform, out MeshProbe existing_probe))
                {
                    return existing_probe;
                }
                else
                {
                    var merged = transform.GetComponentInParent<PortalMeshProbeMergeChildren>(true);
                    if (merged != null)
                    {
                        Transform target = merged.Target;
                        if (target != transform && target.IsChildOf(context.System.ScanRoot))
                        {
                            var probe = probe_for_transform(target);
                            probe_mapping.Add(transform, probe);
                            return probe;
                        }
                    }

                    // Actually create a probe
                    var new_probe = new MeshProbe { index = probe_list.Count, transform = transform };
                    probe_list.Add(new_probe);
                    probe_mapping.Add(transform, new_probe);
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

                    Vector2[] uv = new Vector2[mesh.vertexCount];

                    // Pre-compute probe relations to bones
                    Transform[] bones = skinned_mesh_renderer.bones;
                    Matrix4x4[] bindposes = mesh.bindposes;
                    Dictionary<Transform, int> bone_id_mapping = Enumerable.Range(0, bones.Length).ToDictionary(i => bones[i], i => i);
                    bool[] use_head_chop = bones.Select(bone => bone.IsChildOf(context.System.HeadBone)).ToArray();
                    int associate_to_probe(int bone_id, Vector3 vertex)
                    {
                        // Defer creating probe to here, to only create probe for bones that are used.
                        MeshProbe probe = probe_for_transform(bones[bone_id]);
                        probe.vertices.Add(bindposes[bone_id_mapping[probe.transform]].MultiplyPoint3x4(vertex));
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

                        // Vertex weights in decreasing order of influence ; use first 1 only.
                        if (influence_count > 0) {
                            int bone_id = bone_weights[bw_array_offset].boneIndex;
                            uv[vertex_id] = new Vector2(
                                associate_to_probe(bone_id, vertex),
                                use_head_chop[bone_id] ? 1f : 0f
                            );
                        } else {
                            uv[vertex_id] = new Vector2(-1f, 0f);
                        }
                        bw_array_offset += influence_count;
                    }

                    // Edit mesh in place. No save to assets & swap so it will not be persistent, but sufficient for upload.
                    mesh.SetUVs(context.System.MeshProbeUvChannel, uv);
                }
                else if (mesh_renderer != null)
                {
                    Mesh mesh = mesh_renderer.GetComponent<MeshFilter>().sharedMesh;
                    Vector3[] vertices = mesh.vertices;
                    MeshProbe probe = probe_for_transform(mesh_renderer.transform);
                    bool use_head_chop = mesh_renderer.transform.IsChildOf(context.System.HeadBone);
                    float use_head_chop_value = use_head_chop ? 1f : 0f;

                    Vector2[] uv = new Vector2[mesh.vertexCount];
                    for (int vertex_id = 0; vertex_id < mesh.vertexCount; vertex_id += 1)
                    {
                        probe.vertices.Add(vertices[vertex_id]);
                        uv[vertex_id] = new Vector2(probe.index, use_head_chop_value);
                    }
                    mesh.SetUVs(context.System.MeshProbeUvChannel, uv);
                }
            }

            // Now that all probes are created, set parent links
            Dictionary<Transform, MeshProbe> bone_to_probe = probe_list.ToDictionary(probe => probe.transform, probe => probe);
            foreach (MeshProbe probe in probe_list)
            {
                Transform t = probe.transform.parent;
                while (t != null)
                {
                    if (bone_to_probe.TryGetValue(t, out MeshProbe parent_probe))
                    {
                        probe.parent = parent_probe;
                        break;
                    }
                    t = t.parent;
                }
            }

            // Invert links to make head the root
            if (bone_to_probe.TryGetValue(context.System.HeadBone, out MeshProbe root_probe))
            {
                MeshProbe next = root_probe.parent;
                root_probe.parent = null;
                MeshProbe done = root_probe;
                while (next != null)
                {
                    MeshProbe current = next;
                    next = current.parent;
                    current.parent = done;
                    done = current;
                }
            }

            // Generate probes
            foreach (MeshProbe probe in probe_list)
            {
                Vector3 a = Vector3.zero;
                foreach (Vector3 pos in probe.vertices) { a += pos; }
                Vector3 barycenter = a / Mathf.Max(1f, probe.vertices.Count);

                float radius_sq = probe.vertices.Select(vertex => { Vector3 v = vertex - barycenter; return Vector3.Dot(v, v); }).Max();
                float radius = Mathf.Sqrt(radius_sq); // TODO margin ?

                float parent_index = probe.parent != null ? probe.parent.index : -1;

                context.Vertices.Add(new Vertex
                {
                    transform = probe.transform,
                    localPosition = barycenter,
                    // Retrieve scaled radius from normal length
                    normal = new Vector3(radius, 0, 0),
                    uv0 = new Vector3((float)VertexType.MeshProbe, probe.index, parent_index),
                });
            }
            context.MeshProbeCount = probe_list.Count;

            // Cleanup components. Need to search them first.
            foreach (var merger in context.System.ScanRoot.GetComponentsInChildren<PortalMeshProbeMergeChildren>(true))
            {
                Object.DestroyImmediate(merger);
            }
        }
    }
}