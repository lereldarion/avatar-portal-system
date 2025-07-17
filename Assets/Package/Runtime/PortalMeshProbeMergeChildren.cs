using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Stop automatic generation at this bone and merge all children bone probes into this one.
    /// </summary>
    public class PortalMeshProbeMergeChildren : MonoBehaviour, IEditorOnly
    {
        public MergeTarget MergeInto = MergeTarget.Self;

        public Transform Target
        {
            get => MergeInto == MergeTarget.Parent ? transform.parent : transform;
        }

        public enum MergeTarget
        {
            Self,
            Parent,
        }
    }
}