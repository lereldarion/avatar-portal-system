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
using Lereldarion.Portal;

[assembly: ExportsPlugin(typeof(Lereldarion.PortalTestAvatarPlugin))]


namespace Lereldarion
{
    /// <summary>
    /// Root of a portal system.
    /// </summary>
    [DisallowMultipleComponent]
    public class PortalTestAvatar : MonoBehaviour, IEditorOnly
    {
        public VRCExpressionsMenu menu_target;

        public GameObject SystemRoot;
        [Header("Portals")]
        public VRCParentConstraint MenuPortal;
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
            // Ensure portal scales are extracted before modifications
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

            {
                var layer = ctrl.NewLayer("System");

                var parameter = layer.BoolParameter("Portal/System");
                ma.NewParameter(parameter).WithDefaultValue(false);
                new_installed_menu_item().Name("System").Toggle(parameter);

                var disabled = layer.NewState("Disabled").WithAnimation(aac.NewClip().Toggling(config.SystemRoot, false));
                var enabled = layer.NewState("Enabled").WithAnimation(aac.NewClip().Toggling(config.SystemRoot, true));

                disabled.TransitionsTo(enabled).When(parameter.IsTrue());
                enabled.TransitionsTo(disabled).When(parameter.IsFalse());
            }
            {
                var layer = ctrl.NewLayer("Menu");

                var parameter = layer.BoolParameter("Portal/Menu");
                ma.NewParameter(parameter).WithDefaultValue(false).NotSaved();
                new_installed_menu_item().Name("Menu Portal").Toggle(parameter);

                var disabled = layer.NewState("Disabled").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.MenuPortal.transform, Vector3.zero)
                    .Animating(SetConstraintWorldFixed(config.MenuPortal, false))
                );
                var enabled = layer.NewState("Enabled").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.MenuPortal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(config.MenuPortal, true))
                );

                // Set scale to 0 for upload
                config.MenuPortal.transform.localScale = Vector3.zero;

                disabled.TransitionsTo(enabled).WithTransitionDurationSeconds(0.3f)
                    .When(parameter.IsTrue());
                enabled.TransitionsTo(disabled).WithTransitionDurationSeconds(0.3f)
                    .When(parameter.IsFalse());
            }

            {
                var layer = ctrl.NewLayer("Left Hand");

                var contact = layer.BoolParameter("Portal/LeftHand/Contact");

                var disabled = layer.NewState("Disabled").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.LeftHandPortal.transform, Vector3.zero)
                    .Animating(SetConstraintWorldFixed(config.LeftHandPortal, false))
                );
                var in_hand = layer.NewState("In Hand").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.LeftHandPortal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(config.LeftHandPortal, false))
                );
                var world = layer.NewState("World").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.LeftHandPortal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(config.LeftHandPortal, true))
                );

                // TODO interrupt stuff or wait times to avoid spawning portal by error.
                disabled.TransitionsTo(in_hand).WithTransitionDurationSeconds(0.3f)
                    .When(layer.Av3().GestureLeft.IsEqualTo(AacAv3.Av3Gesture.HandGun));
                in_hand.TransitionsTo(disabled).WithTransitionDurationSeconds(0.3f)
                    .When(layer.Av3().GestureLeft.IsEqualTo(AacAv3.Av3Gesture.Fist));

                in_hand.TransitionsTo(world).When(layer.Av3().GestureLeft.IsEqualTo(AacAv3.Av3Gesture.HandOpen));
                // TODO smooth reparenting from world.
                world.TransitionsTo(in_hand)
                    .When(layer.Av3().GestureLeft.IsEqualTo(AacAv3.Av3Gesture.HandGun))
                    .And(contact.IsTrue());

                config.LeftHandPortal.transform.localScale = Vector3.zero;
            }
            {
                var layer = ctrl.NewLayer("Right Hand");

                var contact = layer.BoolParameter("Portal/RightHand/Contact");

                var disabled = layer.NewState("Disabled").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.RightHandPortal.transform, Vector3.zero)
                    .Animating(SetConstraintWorldFixed(config.RightHandPortal, false))
                );
                var in_hand = layer.NewState("In Hand").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.RightHandPortal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(config.RightHandPortal, false))
                );
                var world = layer.NewState("World").WithAnimation(
                    aac.NewClip()
                    .Scaling(config.RightHandPortal.transform, Vector3.one)
                    .Animating(SetConstraintWorldFixed(config.RightHandPortal, true))
                );

                // TODO copy improvements to left here

                disabled.TransitionsTo(in_hand).WithTransitionDurationSeconds(0.3f)
                    .When(layer.Av3().GestureRight.IsEqualTo(AacAv3.Av3Gesture.HandGun));
                in_hand.TransitionsTo(disabled).WithTransitionDurationSeconds(0.3f)
                    .When(layer.Av3().GestureRight.IsEqualTo(AacAv3.Av3Gesture.Fist));

                in_hand.TransitionsTo(world).When(layer.Av3().GestureRight.IsEqualTo(AacAv3.Av3Gesture.HandOpen));
                world.TransitionsTo(in_hand)
                    .When(layer.Av3().GestureRight.IsEqualTo(AacAv3.Av3Gesture.HandGun))
                    .And(contact.IsTrue());

                config.RightHandPortal.transform.localScale = Vector3.zero;
            }

            ma.NewMergeAnimator(ctrl.AnimatorController, VRCAvatarDescriptor.AnimLayerType.FX);
            Object.DestroyImmediate(config);
        }

        static private System.Action<AacFlEditClip> SetConstraintWorldFixed(VRCParentConstraint constraint, bool fixed_to_world) {
            return clip => {
                clip.Animates(constraint, "FreezeToWorld").WithOneFrame(fixed_to_world ? 1 : 0);
            };
        }
    }
}
#endif