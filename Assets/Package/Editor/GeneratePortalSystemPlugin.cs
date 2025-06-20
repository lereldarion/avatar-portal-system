using System.Linq;
using System.Collections.Generic;
using AnimatorAsCode.V1;
using AnimatorAsCode.V1.VRC;
using nadena.dev.ndmf;
using UnityEngine;
using VRC.SDK3.Dynamics.Constraint.Components;
using VRC.SDK3.Dynamics.Contact.Components;
using VRC.SDK3.Dynamics.PhysBone.Components;

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
            var animator_controller = aac.NewAnimatorController();
            var animator_context = new AnimatorContext
            {
                Aac = aac,
            };

            foreach (var system in ctx.AvatarRootTransform.GetComponentsInChildren<PortalSystem>(true))
            {
                var mesh = SetupPortalSystem(system, animator_context);
                ctx.AssetSaver.SaveAsset(mesh); // Required for proper upload
            }

            var ma_object = new GameObject("Portal_Animator") { transform = { parent = ctx.AvatarRootTransform } };
            var ma = AnimatorAsCode.V1.ModularAvatar.MaAc.Create(ma_object);
            ma.NewMergeAnimator(animator_controller, VRC.SDK3.Avatars.Components.VRCAvatarDescriptor.AnimLayerType.FX);
        }

        /// <summary>
        /// System information is encoded into points that will be skinned to runtime locations.
        /// uv0.x is the type of object.
        /// 
        /// Portal : encode XY direction and lengths into normal / tangent.
        /// </summary>
        private class SystemMeshVertex
        {
            /// <summary>Position, bone assignment.</summary>
            public Transform transform;
            public Vector3 normal;
            public Vector3 tangent;
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
            var vertices = new List<SystemMeshVertex>();
            var context = new Context { Animator = animator, System = system, Vertices = vertices };
            SetupBoundVertices(context);
            SetupControlVertex(context);
            foreach (var portal in root.GetComponentsInChildren<QuadPortal>(true)) { SetupQuadPortal(portal, context); }

            // Make skinned mesh
            {
                mesh.vertices = vertices.Select(vertex => root.InverseTransformPoint(vertex.transform.position)).ToArray();
                mesh.SetNormals(vertices.Select(vertex => root.InverseTransformVector(vertex.transform.TransformVector(vertex.normal))).ToArray());
                mesh.SetTangents(vertices.Select(vertex =>
                {
                    Vector3 v = root.InverseTransformVector(vertex.transform.TransformVector(vertex.tangent));
                    return new Vector4(v.x, v.y, v.z, 1f);
                }).ToArray());
                mesh.SetUVs(0, vertices.Select(vertex => vertex.uv0).ToArray());
                mesh.SetIndices(Enumerable.Range(0, vertices.Count()).ToArray(), MeshTopology.Points, 0);

                Transform[] bones = vertices.Select(vertex => vertex.transform).ToArray();
                mesh.boneWeights = Enumerable.Range(0, vertices.Count()).Select(i =>
                {
                    var bw = new BoneWeight();
                    bw.boneIndex0 = i;
                    bw.weight0 = 1;
                    return bw;
                }).ToArray();
                mesh.bindposes = bones.Select(bone => bone.worldToLocalMatrix * root.localToWorldMatrix).ToArray();

                renderer.sharedMesh = mesh;
                renderer.bones = bones;
                renderer.material = system.GrabPassExport;
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
            public List<SystemMeshVertex> Vertices;
            public int PortalCount = 0;
        }
        private class AnimatorContext
        {
            public AacFlBase Aac;

            private int id = 0;
            public int UniqueId() { return id++; }
        }

        private void SetupControlVertex(Context context)
        {
            // Provide animator values to grabpass and then CRT
            // Other data is unused
            context.Vertices.Add(new SystemMeshVertex
            {
                transform = context.System.transform,
                normal = new Vector3(0, 0, 0),
                tangent = new Vector3(0, 0, 0),
                uv0 = new Vector2((float) VertexType.Control, 0),
            });
        }

        /// <summary>
        /// Creates vertices and animator used to setup occlusion bounds
        /// </summary>
        /// <param name="context">Data of the current portal system being built</param>
        private void SetupBoundVertices(Context context)
        {
            // TODO create gameobject + vertex bound to it. Add animator init to check update on skinned mesh and move bounds.
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

            context.Vertices.Add(new SystemMeshVertex
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