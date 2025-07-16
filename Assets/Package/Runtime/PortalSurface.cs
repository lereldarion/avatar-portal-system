using UnityEngine;
using IEditorOnly = VRC.SDKBase.IEditorOnly;

namespace Lereldarion.Portal
{
    /// <summary>
    /// Add a portal quad on XY axis of this transform.
    /// Size is given for X and Y.
    /// </summary>
    [DisallowMultipleComponent]
    public class PortalSurface : MonoBehaviour, IEditorOnly
    {
        [Tooltip("Portal size on X,Y"), Min(0.00001f)]
        public Vector2 Size = Vector2.one;

        [Tooltip("Portal shape")]
        public ShapeType Shape = ShapeType.Rectangle;

        public void OnDrawGizmosSelected()
        {
            if (Size.x > 0 && Size.y > 0)
            {
                Gizmos.color = Color.yellow;
                if (Shape == ShapeType.Rectangle)
                {
                    Vector3[] points = new Vector3[4];
                    points[0] = transform.TransformPoint(new Vector3(-Size.x, -Size.y, 0));
                    points[1] = transform.TransformPoint(new Vector3(Size.x, -Size.y, 0));
                    points[2] = transform.TransformPoint(new Vector3(Size.x, Size.y, 0));
                    points[3] = transform.TransformPoint(new Vector3(-Size.x, Size.y, 0));
                    Gizmos.DrawLineStrip(points, true);
                }
                else if (Shape == ShapeType.Ellipse)
                {
                    const int segments = 32;
                    Gizmos.color = Color.yellow;
                    Vector3[] points = new Vector3[segments];
                    for (int i = 0; i < segments; i += 1)
                    {
                        float angle = i * 2f * Mathf.PI / segments;
                        points[i] = transform.TransformPoint(new Vector3(Mathf.Cos(angle) * Size.x, Mathf.Sin(angle) * Size.y, 0));
                    }
                    Gizmos.DrawLineStrip(points, true);
                }
            }
        }

        public enum ShapeType
        {
            Rectangle,
            Ellipse,
        }
    }
}