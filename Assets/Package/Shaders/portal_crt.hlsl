#ifndef LERELDARION_PORTAL_CRT_H
#define LERELDARION_PORTAL_CRT_H

// Encodings :
// Portal `i` is encoded by 2 f32x4 pixels at (i, 0) and (i, 1)
// (i, 0) = float4(wpos.xyz, w = radius^2)
// (i, 1) = x/y axis as f16x6 in u16x6 in u32x3 in f32x3 xyz. is_ellipse bit in w.

struct PortalPixel0 {
    float3 position;
    float radius_sq;

    bool is_enabled() { return radius_sq > 0; }
    static PortalPixel0 decode(uint4 pixel) {
        float4 pixel_fp = asfloat(pixel);
        PortalPixel0 o;
        o.position = pixel_fp.xyz;
        o.radius_sq = pixel_fp.w;
        return o;
    }
    bool fast_intersect(float3 origin, float3 end);
};

struct Portal {
    float3 position;
    float3 x_axis;
    float3 y_axis;
    bool is_ellipse; // false = quad, true = ellipse TODO

    // Only when decoded
    float3 normal;
    
    void encode(out uint4 pixels[2]);
    static Portal decode(PortalPixel0 pixel0, uint4 pixel1);

    bool segment_intersect(float3 origin, float3 end);
};

///////////////////////////////////////////////////////////////////////////

bool PortalPixel0::fast_intersect(float3 origin, float3 end) {
    // Check if line intersect portal approximated by a sphere. Does not check ray distance.
    // Fast and avoids loading the second pixel if rejected.
    // On success use the full portal segment intersect below.

    float3 ray = end - origin;
    float3 portal_v = position - origin;

    float3 projection = portal_v - dot(portal_v, ray) / dot(ray, ray) * ray;
    return dot(projection, projection) <= radius_sq;
}

bool Portal::segment_intersect(float3 origin, float3 end) {
    // Note that we do not have to normalize normal, ray, or x/y axis at all.
    float3 ray = end - origin;
    // portal plane equation dot(p - position, normal) = 0
    // ray line p(t) = origin + ray * t
    float t = dot(position - origin, normal) / dot(ray, normal);
    // t in [0, 1] <=> intersect point between [origin, end].
    if(!all(t == saturate(t))) { return false; }
    float3 intersect = origin + ray * t;
    // Test if we are within the portal shape
    float3 v = intersect - position;
    float2 axis_projections = float2(dot(x_axis, v), dot(y_axis, v));
    float2 axis_length_sq = float2(dot(x_axis, x_axis), dot(y_axis, y_axis));
    if(is_ellipse) {
        float2 coords = axis_projections / axis_length_sq; // [-1, 1]
        return dot(coords, coords) <= 1;
    } else /* quad */ {
        return all(abs(axis_projections) <= axis_length_sq);
    }
}

///////////////////////////////////////////////////////////////////////////

void Portal::encode(out uint4 pixels[2]) {
    // Pixel 0
    float radius_sq = dot(x_axis, x_axis) + dot(y_axis, y_axis); // Max distance is hypothenuse, then squared.
    pixels[0] = asuint(float4(position, radius_sq));

    // Pixel 1
    uint3 axis_packed = (f32tof16(y_axis) << 16) | f32tof16(x_axis);
    pixels[1] = uint4(axis_packed, is_ellipse ? 0x1 : 0x0);
}
static Portal Portal::decode(PortalPixel0 pixel0, uint4 pixel1) {
    Portal p;
    p.position = pixel0.position;

    p.is_ellipse = pixel1.w & 0x1;
    p.x_axis = f16tof32(pixel1.xyz & 0xFFFF);
    p.y_axis = f16tof32(pixel1.xyz >> 16);

    p.normal = cross(p.x_axis, p.y_axis);
    return p;
}

#endif