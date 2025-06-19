using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Root of a portal system.
    /// </summary>
    [DisallowMultipleComponent]
    public class PortalSystem : MonoBehaviour, IEditorOnly
    {
        [Min(1f), Tooltip("Force occlusion bounds of the system to this size")]
        public float OcclusionBoxSize = 100f;

        [Header("Material")]
        public Material GrabPassExport;
        public Material SealPortals;
    }
}