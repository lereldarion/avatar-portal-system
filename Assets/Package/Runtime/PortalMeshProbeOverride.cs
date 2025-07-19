using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Override automatic mesh probe position for bone.
    /// TODO find the right semantics. Potentially list of localpos + radius, or just auto compute radius
    /// Or count of probes and use clustering algorithm ?
    /// Could be used to split parenting by overriding parent to null or something
    /// </summary>
    public class PortalMeshProbeOverride : MonoBehaviour, IEditorOnly
    {
        [Tooltip("Radius of effect (detection, mesh influence)"), Min(0.00001f)]
        public float Radius = 0.1f;

        [Tooltip("Optional offset from current transform")]
        public Vector3 LocalPosition = Vector3.zero;
        public Vector3 Position {
            get => transform.TransformPoint(LocalPosition);
        }

        [Tooltip("Parent override ; if not defined take the first probe found on parent transforms")]
        public PortalMeshProbeOverride OverrideParent = null;
        public PortalMeshProbeOverride Parent {
            get => OverrideParent ?? transform.parent.GetComponentInParent<PortalMeshProbeOverride>(true);
        }

        public void OnDrawGizmosSelected()
        {
            Gizmos.color = new Color(0f, 1f, 1f, 0.1f);
            Gizmos.DrawSphere(Position, Radius);

            PortalMeshProbeOverride parent = Parent;
            if (parent != null)
            {
                Gizmos.color = Color.cyan;
                Gizmos.DrawLine(Position, parent.Position);
            }
        }
    }
}