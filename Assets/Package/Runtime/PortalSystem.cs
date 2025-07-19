using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Root of a portal system.
    /// Upload-time hooks will generate a system control <c>SkinnedMeshRenderer</c> at this transform.
    /// </summary>
    [DisallowMultipleComponent]
    public class PortalSystem : MonoBehaviour, IEditorOnly
    {
        [Tooltip("Override root of component scan ; if not defined use the portal system transform")]
        public Transform ScanRootOverride = null;
        public Transform ScanRoot
        {
            get => ScanRootOverride ?? transform;
        }

        [Header("System update elements")]
        [Tooltip("Update loop material")]
        public Material Update;
        public Camera Camera0;
        public Camera Camera1;

        [Header("Visuals")]
        public Renderer Visuals;
        [Min(1f), Tooltip("Force occlusion bounds of the system to this size")]
        public float OcclusionBoxSize = 1000f;

        [Header("Mesh probes")]
        [Tooltip("Head bone used to root the mesh probe tree and recreate head chop")]
        public Transform HeadBone;
        [Range(0, 7)]
        public int MeshProbeUvChannel = 7;
    }
}