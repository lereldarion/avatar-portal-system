using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Root of a portal system.
    /// 
    /// TODO handle link to animator, portal ordering, etc...
    /// </summary>
    [DisallowMultipleComponent]
    public class PortalSystem : MonoBehaviour, IEditorOnly
    {
        [Header("Material")]
        public Material Material;
    }
}