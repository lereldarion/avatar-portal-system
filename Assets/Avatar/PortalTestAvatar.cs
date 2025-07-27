// Made by Lereldarion (https://github.com/lereldarion/avatar-portal-system). MIT license.

#if UNITY_EDITOR
using AnimatorAsCode.V1;
using AnimatorAsCode.V1.ModularAvatar;
using AnimatorAsCode.V1.VRC;
using IEditorOnly = VRC.SDKBase.IEditorOnly;
using nadena.dev.ndmf;
using nadena.dev.modular_avatar.core;
using UnityEditor;
using UnityEngine;
using VRC.SDK3.Avatars.Components;
using VRC.SDK3.Dynamics.Constraint.Components;
using VRC.SDK3.Avatars.ScriptableObjects;

[assembly: ExportsPlugin(typeof(Lereldarion.PortalTestAvatarPlugin))]


namespace Lereldarion
{
    /// <summary>
    /// Portal system demo avatar animator. Spawn up to 4 portals, toggle debug.
    /// </summary>
    [DisallowMultipleComponent]
    public class PortalTestAvatar : MonoBehaviour, IEditorOnly
    {
        public VRCExpressionsMenu menu_target;

        public GameObject SystemRoot;
        [Header("Portals")]
        public VRCParentConstraint[] MenuPortals;
        public VRCParentConstraint LeftHandPortal;
        public VRCParentConstraint RightHandPortal;
    }

    public class PortalTestAvatarPlugin : Plugin<PortalTestAvatarPlugin>
    {
        public override string DisplayName => "Portal Test Animator";

        public string SystemName => "Portal";

        protected override void Configure()
        {
            InPhase(BuildPhase.Generating)
            // Ensure portal scales are extracted before modifications, and root skinned mesh renderer has been created.
            .AfterPlugin("Lereldarion.Portal.GeneratePortalSystemPlugin")
            .Run(DisplayName, Generate);
        }

        private void Generate(BuildContext ctx)
        {
            var config = ctx.AvatarRootTransform.GetComponentInChildren<PortalTestAvatar>(false);
            if (config == null) { return; }

            var aac = AacV1.Create(new AacConfiguration
            {
                SystemName = SystemName,
                AnimatorRoot = ctx.AvatarRootTransform,
                DefaultValueRoot = ctx.AvatarRootTransform,
                AssetKey = GUID.Generate().ToString(),
                AssetContainer = ctx.AssetContainer,
                ContainerMode = AacConfiguration.Container.OnlyWhenPersistenceRequired,
                DefaultsProvider = new AacDefaultsProvider()
            });

            var ma_object = new GameObject(SystemName) { transform = { parent = ctx.AvatarRootTransform } };
            var ma = MaAc.Create(ma_object);
            MaacMenuItem new_installed_menu_item()
            {
                var menu = new GameObject { transform = { parent = ma_object.transform } };
                var installer = menu.AddComponent<ModularAvatarMenuInstaller>();
                installer.installTargetMenu = config.menu_target;
                return ma.EditMenuItem(menu);
            }

            var ctrl = aac.NewAnimatorController();

            const string global_toggle_name = "Portal/System";
            {
                var layer = ctrl.NewLayer("System");

                var parameter = layer.BoolParameter(global_toggle_name);
                ma.NewParameter(parameter).WithDefaultValue(false);
                new_installed_menu_item().Name("System").Toggle(parameter);

                var renderer = config.SystemRoot.GetComponent<SkinnedMeshRenderer>();

                // Need system shader disabled for 1 frame to update texture.
                var disabling = layer.NewState("Disabling").WithAnimation(aac.NewClip()
                    .Toggling(config.SystemRoot, true)
                    .Animating(edit => edit.Animates(renderer, "material._Portal_System_Enabled").WithOneFrame(0))
                );

                var disabled = layer.NewState("Disabled").WithAnimation(aac.NewClip()
                    .Toggling(config.SystemRoot, false)
                    .Animating(edit => edit.Animates(renderer, "material._Portal_System_Enabled").WithOneFrame(0))
                );
                var enabled = layer.NewState("Enabled").WithAnimation(aac.NewClip()
                    .Toggling(config.SystemRoot, true)
                    .Animating(edit => edit.Animates(renderer, "material._Portal_System_Enabled").WithOneFrame(1))
                );

                disabled.TransitionsTo(enabled).When(parameter.IsTrue());
                enabled.TransitionsTo(disabling).When(parameter.IsFalse());
                disabling.AutomaticallyMovesTo(disabled);

                // Disable system at export. Required for cameras.
                config.SystemRoot.SetActive(false);
            }

            {
                var layer = ctrl.NewLayer("Debug");

                var parameter = layer.BoolParameter("Portal/Debug");
                ma.NewParameter(parameter).WithDefaultValue(false);
                new_installed_menu_item().Name("Debug").Toggle(parameter);

                var renderer = config.SystemRoot.transform.Find("Visuals").GetComponent<MeshRenderer>();

                var disabled = layer.NewState("Disabled").WithAnimation(aac.NewClip()
                    .Animating(edit => edit.Animates(renderer, "material._Portal_Debug_Show").WithOneFrame(0))
                );
                var enabled = layer.NewState("Enabled").WithAnimation(aac.NewClip()
                    .Animating(edit => edit.Animates(renderer, "material._Portal_Debug_Show").WithOneFrame(1))
                );

                disabled.TransitionsTo(enabled).When(parameter.IsTrue());
                enabled.TransitionsTo(disabled).When(parameter.IsFalse());
            }

            for (int i = 0; i < config.MenuPortals.Length; i += 1)
            {
                var layer = ctrl.NewLayer($"Menu{i}");

                var parameter = layer.BoolParameter($"Portal/Menu{i}");
                ma.NewParameter(parameter).WithDefaultValue(false).NotSaved();
                new_installed_menu_item().Name($"Portal{i}").Toggle(parameter);

                var global_toggle = layer.BoolParameter(global_toggle_name);

                var disabled = layer.NewState("Disabled").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.MenuPortals[i].transform, Vector3.zero)
                    .Animating(SetConstraintWorldFixed(config.MenuPortals[i], false))
                );
                var enabled = layer.NewState("Enabled").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.MenuPortals[i].transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(config.MenuPortals[i], true))
                );

                // Set scale to 0 for upload
                config.MenuPortals[i].transform.localScale = Vector3.zero;

                disabled.DrivingLocally().Drives(parameter, false);
                disabled.TransitionsTo(enabled).WithTransitionDurationSeconds(0.3f)
                    .When(parameter.IsTrue())
                    .And(global_toggle.IsTrue());
                enabled.TransitionsTo(disabled).WithTransitionDurationSeconds(0.3f)
                    .When(parameter.IsFalse())
                    .Or().When(global_toggle.IsFalse());
            }

            void setup_hand_portal(string name, VRCParentConstraint anchor, System.Func<AacAv3, AacFlEnumIntParameter<AacAv3.Av3Gesture>> gesture)
            {
                var layer = ctrl.NewLayer(name);

                var contact = layer.BoolParameter($"Portal/{name}/Contact");
                var global_toggle = layer.BoolParameter(global_toggle_name);
                var portal = anchor.transform.Find("Portal").GetComponent<VRCParentConstraint>();

                var disabled = layer.NewState("Disabled").WithAnimation(
                    aac.NewClip()
                    .Scaling(portal.transform, Vector3.zero)
                    .Animating(SetConstraintWorldFixed(anchor, false))
                    .Animating(SetConstraintActiveSource(portal, 0))
                    .Animating(SetConstraintWorldFixed(portal, false))
                );
                var in_hand = layer.NewState("In Hand").WithAnimation(
                    aac.NewClip()
                    .Scaling(portal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(anchor, false))
                    .Animating(SetConstraintActiveSource(portal, 0))
                    .Animating(SetConstraintWorldFixed(portal, false))
                );
                var world = layer.NewState("World").WithAnimation(
                    aac.NewClip()
                    .Scaling(portal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(anchor, true))
                    .Animating(SetConstraintActiveSource(portal, 1))
                    .Animating(SetConstraintWorldFixed(portal, true))
                );
                var world_to_hand = layer.NewState("World2Hand").WithAnimation(
                    aac.NewClip()
                    .Scaling(portal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(anchor, true))
                    .Animating(SetConstraintWorldFixed(portal, false))
                    .Animating(edit =>
                    {
                        for (int i = 0; i < portal.Sources.Count; i += 1) {
                            edit.Animates(portal, $"Sources.source{i}.Weight").WithSecondsUnit(curve => curve.Linear(0f, i == 0 ? 0 : 1).Linear(0.3f, i == 0 ? 1 : 0));
                        }
                    })
                );

                // TODO interrupt stuff or wait times to avoid spawning portal by error.
                disabled.TransitionsTo(in_hand).WithTransitionDurationSeconds(0.3f)
                    .When(gesture(layer.Av3()).IsEqualTo(AacAv3.Av3Gesture.Victory))
                    .And(global_toggle.IsTrue());
                in_hand.TransitionsTo(disabled).WithTransitionDurationSeconds(0.3f)
                    .When(gesture(layer.Av3()).IsEqualTo(AacAv3.Av3Gesture.Fist));

                in_hand.TransitionsTo(world).When(gesture(layer.Av3()).IsEqualTo(AacAv3.Av3Gesture.HandOpen));
                world.TransitionsTo(world_to_hand)
                    .When(gesture(layer.Av3()).IsEqualTo(AacAv3.Av3Gesture.Victory))
                    .And(contact.IsTrue());
                world_to_hand.AutomaticallyMovesTo(in_hand);

                layer.AnyTransitionsTo(disabled).WithNoTransitionToSelf().When(global_toggle.IsFalse());

                portal.transform.localScale = Vector3.zero;
            }
            setup_hand_portal("LeftHand", config.LeftHandPortal, av3 => av3.GestureLeft);
            setup_hand_portal("RightHand", config.RightHandPortal, av3 => av3.GestureRight);

            ma.NewMergeAnimator(ctrl.AnimatorController, VRCAvatarDescriptor.AnimLayerType.FX);
            Object.DestroyImmediate(config);
        }

        // Most constraint animations have only one source active at a time. Provide a quick setter for that.
        static private System.Action<AacFlEditClip> SetConstraintActiveSource(VRCParentConstraint constraint, int active_source) {
            return clip => {
                for (int i = 0; i < constraint.Sources.Count; i += 1) {
                    clip.Animates(constraint, $"Sources.source{i}.Weight").WithOneFrame(i == active_source ? 1 : 0);
                }
            };
        }

        static private System.Action<AacFlEditClip> SetConstraintWorldFixed(VRCParentConstraint constraint, bool fixed_to_world)
        {
            return clip =>
            {
                clip.Animates(constraint, "FreezeToWorld").WithOneFrame(fixed_to_world ? 1 : 0);
            };
        }
    }
}
#endif