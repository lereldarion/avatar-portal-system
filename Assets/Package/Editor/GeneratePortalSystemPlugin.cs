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
        /// We will generate one point per portal.
        /// Gather data from portal components here.
        /// </summary>
        private class PortalEncoding
        {
            /// <summary>
            /// Position, bone assignment of portal point.
            /// </summary>
            public Transform transform;
            // For now only Quad portal, encode XY direction and lengths into normal / tangent
            public Vector3 normal;
            public Vector3 tangent;
        };

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
            var portal_encodings = new List<PortalEncoding>();
            var context = new Context { Animator = animator, System = system, portal_encodings = portal_encodings };

            foreach (var portal in root.GetComponentsInChildren<QuadPortal>(true)) { SetupPortal(portal, context); }

            mesh.vertices = portal_encodings.Select(portal => root.InverseTransformPoint(portal.transform.position)).ToArray();
            mesh.SetNormals(portal_encodings.Select(portal => root.InverseTransformVector(portal.transform.TransformVector(portal.normal))).ToArray());
            mesh.SetTangents(portal_encodings.Select(portal =>
            {
                Vector3 v = root.InverseTransformVector(portal.transform.TransformVector(portal.tangent));
                return new Vector4(v.x, v.y, v.z, 1f);
            }).ToArray());
            mesh.SetIndices(Enumerable.Range(0, portal_encodings.Count()).ToArray(), MeshTopology.Points, 0);

            Transform[] bones = portal_encodings.Select(vertex => vertex.transform).ToArray();
            mesh.boneWeights = Enumerable.Range(0, portal_encodings.Count()).Select(i =>
            {
                var bw = new BoneWeight();
                bw.boneIndex0 = i;
                bw.weight0 = 1;
                return bw;
            }).ToArray();
            mesh.bindposes = bones.Select(bone => bone.worldToLocalMatrix * root.localToWorldMatrix).ToArray();

            var renderer = root.gameObject.AddComponent<SkinnedMeshRenderer>();
            renderer.sharedMesh = mesh;
            renderer.bones = bones;
            renderer.material = system.Material;

            Object.DestroyImmediate(system); // Cleanup components
            return mesh;
        }

        private class Context
        {
            public AnimatorContext Animator;
            public PortalSystem System;
            public List<PortalEncoding> portal_encodings;
        }
        private class AnimatorContext
        {
            public AacFlBase Aac;

            private int id = 0;
            public int UniqueId() { return id++; }
        }

        /// <summary>
        /// Add a portal to the system.
        /// </summary>
        /// <param name="portal">Portal descriptor</param>
        /// <param name="context">Data of the current portal system being built</param>
        /// <exception cref="System.ArgumentException"></exception>
        private void SetupPortal(QuadPortal portal, Context context)
        {
            context.portal_encodings.Add(new PortalEncoding
            {
                transform = portal.transform,
                normal = new Vector3(portal.Size.x, 0, 0),
                tangent = new Vector3(0, portal.Size.y, 0),
            });

            Object.DestroyImmediate(portal); // Remove items before upload
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