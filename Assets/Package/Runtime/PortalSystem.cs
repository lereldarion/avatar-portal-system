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
        [Tooltip("Update loop material")]
        public Material Update;
        public Camera Camera0;
        public Camera Camera1;

        [Header("Visuals")]
        public Renderer Visuals;
        [Min(1f), Tooltip("Force occlusion bounds of the system to this size")]
        public float OcclusionBoxSize = 1000f;
    }
}