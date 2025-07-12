using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Add a portal quad on XY axis of this transform.
    /// Size is given for X and Y.
    /// </summary>
    public class PortalMeshProbe : MonoBehaviour, IEditorOnly
    {
        [Tooltip("Radius of effect (detection, mesh influence)"), Min(0.00001f)]
        public float Radius = 0.1f;

        [Tooltip("Optional offset from current transform")]
        public Vector3 Position = Vector3.zero;

        [Tooltip("Parent override ; if not defined take the first probe found on parent transforms")]
        public PortalMeshProbe Parent = null;

        // TODO mesh list to filter ?

        public void OnDrawGizmosSelected()
        {
            Gizmos.color = new Color(0f, 1f, 1f, 0.1f);
            Gizmos.DrawSphere(transform.TransformPoint(Position), Radius);
        }
    }
}