using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Root of a portal system.
    /// Will generate a skinned mesh TODO.
    /// </summary>
    [DisallowMultipleComponent]
    public class PortalSystem : MonoBehaviour, IEditorOnly
    {
        [Header("Material")]
        public Material Material;
    }
}