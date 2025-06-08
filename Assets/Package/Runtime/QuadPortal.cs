using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Add a portal quad on XY axis of this transform.
    /// Size is given for X and Y.
    /// </summary>
    [DisallowMultipleComponent]
    public class QuadPortal : MonoBehaviour, IEditorOnly
    {
        [Tooltip("Portal size on X,Y")]
        public Vector2 Size = Vector2.one;

        public void OnDrawGizmosSelected()
        {
            if (Size.x > 0 && Size.y > 0)
            {
                Gizmos.color = Color.yellow;
                Vector3[] points = new Vector3[4];
                points[0] = transform.TransformPoint(new Vector3(-Size.x, -Size.y, 0));
                points[1] = transform.TransformPoint(new Vector3(Size.x, -Size.y, 0));
                points[2] = transform.TransformPoint(new Vector3(Size.x, Size.y, 0));
                points[3] = transform.TransformPoint(new Vector3(-Size.x, Size.y, 0));
                Gizmos.DrawLineStrip(points, true);
            }
        }
    }
}