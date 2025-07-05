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
        public override string DisplayName => "Lereldarion Portal System: Generate Mesh";

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
                var mesh = SetupPortalSystem(system, animator_context);
                ctx.AssetSaver.SaveAsset(mesh); // Required for proper upload
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
            Control = 1,
            QuadPortal = 2,
            EllipsePortal = 3,
        }

        /// <summary>
        /// Create portal mesh renderer, animator layers, gameobjects from descriptor components.
        /// Remove descriptors from the ndmf copy, to allow d4rkAvatarOptimizer to see no reference to gameobjects and merge properly.
        /// </summary>
        /// <param name="system">Controller root component : start of search for descriptors, and location where renderer is added</param>
        /// <returns>Reference to the created mesh, to be saved as asset by ndmf</returns>
        private Mesh SetupPortalSystem(PortalSystem system, AnimatorContext animator)
        {
            Transform root = system.transform;
            Mesh mesh = new Mesh();
            SkinnedMeshRenderer renderer = root.gameObject.AddComponent<SkinnedMeshRenderer>();

            // Scan portal system components
            var vertices = new List<Vertex>();
            var context = new Context { Animator = animator, System = system, Vertices = vertices };
            SetupOcclusionBounds(context, renderer);
            SetupControlVertex(context);
            foreach (var portal in root.GetComponentsInChildren<QuadPortal>(true)) { SetupQuadPortal(portal, context); }

            // Make skinned mesh
            {
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
                for (int i = 0; i < bones.Length; i += 1) {
                    bone_to_bone_id.Add(bones[i], i);
                }
                mesh.boneWeights = vertices.Select(vertex =>
                {
                    var bw = new BoneWeight();
                    bw.boneIndex0 = bone_to_bone_id[vertex.transform];
                    bw.weight0 = 1;
                    return bw;
                }).ToArray();

                renderer.sharedMesh = mesh;
                renderer.bones = bones;
                renderer.sharedMaterials = new Material[] { system.GrabPassExport, system.SealPortals };
            }

            // Set CRT parameters
            system.Crt.material.SetInteger("_GrabPass_Portal_Count", context.PortalCount);

            Object.DestroyImmediate(system); // Cleanup components
            return mesh;
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

        private void SetupControlVertex(Context context) 
        {
            // Provide animator values to grabpass and then CRT
            // Other data is unused
            context.Vertices.Add(new Vertex
            {
                transform = context.System.transform,
                uv0 = new Vector2((float) VertexType.Control, 0),
            });
        }

        /// <summary>
        /// Setup occlusion bounds using box corners and update mesh.
        /// </summary>
        /// <param name="context">Data of the current portal system being built</param>
        private void SetupOcclusionBounds(Context context, SkinnedMeshRenderer renderer)
        {
            var layer = context.Animator.Controller.NewLayer("Occlusion Setup");
            var clip = context.Animator.Aac.NewClip();

            Transform[] corners = new Transform[4];
            for (int i = 0; i < 4; i += 1)
            {
                var corner = new GameObject($"Occlusion Corner {i}")
                {
                    transform = {
                        parent = context.System.transform,
                        position = context.System.transform.position,
                    }
                };
                corners[i] = corner.transform;
                context.Vertices.Add(new Vertex
                {
                    transform = corner.transform,
                    normal = Vector3.zero,
                    tangent = Vector3.zero,
                    uv0 = new Vector2((float)VertexType.Ignored, 0),
                });
            }

            // 4 corners of a cube.
            float size = context.System.OcclusionBoxSize;
            clip.Positioning(corners[0], new Vector3( size,  size,  size));
            clip.Positioning(corners[1], new Vector3(-size, -size,  size));
            clip.Positioning(corners[2], new Vector3(-size,  size, -size));
            clip.Positioning(corners[3], new Vector3( size, -size, -size));

            // Force update bound on. Must be enabled by animator as VRChat disable them by default.
            // https://github.com/pema99/shader-knowledge/blob/main/tips-and-tricks.md#update-when-offscreen-setting-for-skinned-mesh-renderer
            clip.Animating(edit => edit.Animates(renderer, "m_UpdateWhenOffscreen").WithOneFrame(1));

            // Use small bounds for export
            renderer.localBounds = new Bounds { center = Vector3.up, extents = Vector3.one };

            layer.NewState("Setup").WithAnimation(clip);
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