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
            public Vector3 normal = Vector3.zero;
            public Vector3 tangent = Vector3.zero;
            /// <summary>
            /// x is the type of object. See VertexType.
            /// </summary>
            public Vector2 uv0;
        };

        private enum VertexType
        {
            /// <summary>For points that force mesh bounds</summary>
            Ignored = 0,
            QuadPortal = 1,
            EllipsePortal = 2,
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
            var context = new Context { Animator = animator, System = system, Vertices = vertices };
            foreach (var portal in root.GetComponentsInChildren<QuadPortal>(true)) { SetupQuadPortal(portal, context); }

            // Make system skinned mesh
            {
                // Add a vertex inside update loop cameras to ensure that they will see the system mesh
                vertices.Add(new Vertex
                {
                    transform = context.System.transform,
                    uv0 = new Vector2((float) VertexType.Ignored, 0),
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

                var bone_to_bone_id = new Dictionary<Transform, int>();
                for (int i = 0; i < bones.Length; i += 1)
                {
                    bone_to_bone_id.Add(bones[i], i);
                }
                mesh.boneWeights = vertices.Select(vertex =>
                {
                    var bw = new BoneWeight();
                    bw.boneIndex0 = bone_to_bone_id[vertex.transform];
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
            system.Update.SetFloat("_Camera0_FarPlane", context.System.Camera0.farClipPlane);
            system.Update.SetFloat("_Camera1_FarPlane", context.System.Camera1.farClipPlane);

            // Make single point mesh for visuals.
            {
                // MeshRenderer is already set ; just add a mesh filter with generated mesh
                Renderer renderer = context.System.Visuals;

                Mesh mesh = new Mesh();
                mesh.vertices = new Vector3[] { Vector3.zero };
                mesh.SetIndices(new int[] { 0 }, MeshTopology.Points, 0);
                mesh.bounds = new Bounds { center = Vector3.zero, extents = Vector3.one };

                MeshFilter filter = renderer.gameObject.AddComponent<MeshFilter>();
                filter.sharedMesh = mesh;

                // Extend bounding box with animator.
                var layer = context.Animator.Controller.NewLayer("Portal Init");
                var clip = context.Animator.Aac.NewClip();
                clip.Scaling(renderer.transform, context.System.OcclusionBoxSize * Vector3.one);
                layer.NewState("Init").WithAnimation(clip);

                generated_meshes.Add(mesh);
            }

            Object.DestroyImmediate(system); // Cleanup components
            return generated_meshes.ToArray();
        }

        private class Context
        {
            public AnimatorContext Animator;
            public PortalSystem System;
            public List<Vertex> Vertices;
            public int PortalCount = 0;
        }
        private class AnimatorContext
        {
            public AacFlBase Aac;
            public AacFlController Controller;

            private int id = 0;
            public int UniqueId() { return id++; }
        }

        /// <summary>
        /// Add a portal to the system.
        /// </summary>
        /// <param name="portal">Portal descriptor</param>
        /// <param name="context">Data of the current portal system being built</param>
        private void SetupQuadPortal(QuadPortal portal, Context context)
        {
            VertexType vertex_type = portal.Shape == QuadPortal.ShapeType.Rectangle ? VertexType.QuadPortal : VertexType.EllipsePortal;
            int portal_id = context.PortalCount; context.PortalCount += 1;

            context.Vertices.Add(new Vertex
            {
                transform = portal.transform,
                normal = new Vector3(portal.Size.x, 0, 0),
                tangent = new Vector3(0, portal.Size.y, 0),
                uv0 = new Vector2((float)vertex_type, (float)portal_id),
            });

            Object.DestroyImmediate(portal); // Cleanup components
        }

        static private System.Action<AacFlEditClip> SetConstraintActive(VRC.Dynamics.VRCConstraintBase constraint, bool active)
        {
            return clip => { clip.Animates(constraint, "IsActive").WithOneFrame(active ? 1 : 0); };
        }

        static private System.Action<AacFlEditClip> SetConstraintActiveSource(VRC.Dynamics.VRCConstraintBase constraint, int active_source)
        {
            return clip =>
            {
                for (int i = 0; i < constraint.Sources.Count; i += 1)
                {
                    clip.Animates(constraint, $"Sources.source{i}.Weight").WithOneFrame(i == active_source ? 1 : 0);
                }
            };
        }
    }
}