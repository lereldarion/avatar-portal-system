#ifndef LERELDARION_PORTAL_H
#define LERELDARION_PORTAL_H

// Texture Encodings :
// Header at (0, 0).
// - r : bit0 = system enabled, bit[1,2] = main/photo camera state, bit[3,4] = stereo eye state derived from main
// - g : u32 is a bitmask of active portals for fast scan.
// Camera position pixels
// - pixel = uint4 as float3(wpos.xyz).
// - main camera as (0, 1), photo camera as (0, 2).
// Portal `i` is encoded by 2 f32x4 pixels
// - pixel0 at (1, i) = uint4 as float4(wpos.xyz, w = radius^2)
// - pixel1 at (2, i) = x/y axis as f16x6 in u16x6 in u32x3. is_ellipse as bit0 in w.
// Mesh probe : 1 pixel per probe state.

struct Header {
    bool is_enabled;
    bool camera_in_portal[2];
    bool stereo_eye_in_portal[2];
    uint portal_mask;
    uint mesh_probe_count;

    bool camera_portal_state(float vrc_camera_mode);

    uint4 encode();
    static Header decode(uint4 pixel);
    static Header decode(Texture2D<uint4> tex) { return decode(tex[uint2(0, 0)]); }
};

uint pop_active_portal(inout uint portal_mask) {
    const uint index = firstbitlow(portal_mask);
    portal_mask ^= 0x1 << index; // Mask as seen
    return index;
}

struct CameraPosition {
    static uint4 encode(float3 position) { return uint4(asuint(position), 0); }
    static float3 decode(uint4 pixel) { return asfloat(pixel.rgb); }
    static float3 decode(Texture2D<uint4> tex, uint index) { return decode(tex[uint2(0, 1 + index)]); }
};

struct PortalPixel0 {
    // Partial portal with data from pixel 0 of texture encodings.
    // Can provide a quick intersection test, to see if the precise test with data from pixel 1 is required.
    float3 position;
    float radius_sq;

    bool is_enabled() { return radius_sq > 0; }
    bool fast_intersect(float3 origin, float3 end);

    static PortalPixel0 decode(uint4 pixel);
    static PortalPixel0 decode(Texture2D<uint4> tex, uint index) { return decode(tex[uint2(1, index)]); }
};

struct Portal {
    float3 position;
    float3 x_axis;
    float3 y_axis;
    bool is_ellipse; // false = quad, true = ellipse

    // Only when finalized
    float3 normal;
    float radius_sq;

    void finalize() {
        normal = cross(x_axis, y_axis);
        radius_sq = dot(x_axis, x_axis) + dot(y_axis, y_axis); // Max distance is hypothenuse, then squared.
    }

    bool is_enabled() { return radius_sq > 0; }
    
    bool is_plane_point_in_shape(float3 p);
    bool segment_intersect(float3 origin, float3 end, out float intersection_ray_01);
    bool segment_intersect(float3 origin, float3 end);
    bool ray_intersect(float3 origin, float3 ray, out float ray_distance);
    static Portal lerp(Portal a, Portal b, float t);
    static uint movement_intersect(Portal p0, Portal p1, float3 v0, float3 v1);
    float distance_to_point(float3 p);
    
    void encode(out uint4 pixels[2]);
    static Portal decode(PortalPixel0 pixel0, uint4 pixel1);
    static Portal decode(uint4 pixels[2]) { return decode(PortalPixel0::decode(pixels[0]), pixels[1]); }
    static Portal decode(PortalPixel0 pixel0, Texture2D<uint4> tex, uint index) { return decode(pixel0, tex[uint2(2, index)]); }
    static Portal decode(Texture2D<uint4> tex, uint index) { return decode(PortalPixel0::decode(tex, index), tex, index); }
};

struct MeshProbeConfig {
    float3 position;
    float radius;
    uint parent; // 0xFFFF (u16::MAX) if no parent.

    static const uint no_parent = 0xFFFF;

    uint4 encode();
    static MeshProbeConfig decode(uint4 pixel);
};
struct MeshProbeState {
    float3 position;
    bool in_portal; // 31th bit of w.
    uint traversing_portal_mask; // supports 31 bits/portals only.
    
    uint4 encode();
    static MeshProbeState decode(uint4 pixel);
    static MeshProbeState decode(Texture2D<uint4> tex, uint id) { return decode(tex[uint2(3 + id / 32, id % 32)]); }
};

///////////////////////////////////////////////////////////////////////////

// Check if line intersect portal approximated by a sphere. Does not check ray distance.
// Fast and avoids loading the second pixel if rejected.
// On success use the full portal segment intersect below.
bool PortalPixel0::fast_intersect(float3 origin, float3 end) {
    const float3 ray = end - origin;
    const float3 portal_v = position - origin;

    const float3 projection = portal_v - dot(portal_v, ray) / dot(ray, ray) * ray;
    return dot(projection, projection) <= radius_sq;
}

// Assuming p is within the plane of the portal, do the precise shape test.
bool Portal::is_plane_point_in_shape(float3 p) {
    const float3 v = p - position;
    const float2 axis_projections = float2(dot(x_axis, v), dot(y_axis, v));
    const float2 axis_length_sq = float2(dot(x_axis, x_axis), dot(y_axis, y_axis));
    if(is_ellipse) {
        const float2 coords = axis_projections / axis_length_sq; // [-1, 1]
        return dot(coords, coords) <= 1;
    } else /* quad */ {
        return all(abs(axis_projections) <= axis_length_sq);
    }
}

// Does segment / ray intersects portal precise surface (with its shape).
// Note that we do not have to normalize normal, ray, or x/y axis at all.
bool Portal::segment_intersect(float3 origin, float3 end, out float intersection_ray_01) {
    const float3 ray = end - origin;
    // portal plane equation dot(p - position, normal) = 0
    // ray line p(t) = origin + ray * t
    const float t = dot(position - origin, normal) / dot(ray, normal);
    // t in [0, 1] <=> intersect point between [origin, end].
    if(t == saturate(t)) {
        intersection_ray_01 = t;
        return is_plane_point_in_shape(origin + ray * t);
    } else {
        return false;
    }
}
bool Portal::segment_intersect(float3 origin, float3 end) {
    float dummy;
    return segment_intersect(origin, end, dummy);
}
bool Portal::ray_intersect(float3 origin, float3 ray, out float ray_distance) {
    // portal plane equation dot(p - position, normal) = 0
    // ray line p(t) = origin + ray * t
    const float t = dot(position - origin, normal) / dot(ray, normal);
    if(t >= 0) {
        ray_distance = t;
        return is_plane_point_in_shape(origin + ray * t);
    } else {
        return false;
    }
}

static Portal Portal::lerp(Portal a, Portal b, float t) {
    Portal interpolated;
    interpolated.position = lerp(a.position, b.position, t);
    interpolated.x_axis = lerp(a.x_axis, b.x_axis, t);
    interpolated.y_axis = lerp(a.y_axis, b.y_axis, t);
    interpolated.is_ellipse = a.is_ellipse;
    interpolated.finalize();
    return interpolated;
}

// Assuming portal moves (lerp) from p0 to p1 and a point from v0 to v1,
// how many times does the point crosses the portal surface ? 0 to 2.
// Shape is assumed constant.
static uint Portal::movement_intersect(Portal p0, Portal p1, float3 v0, float3 v1) {
    // For 0 <= t <= 1 lerp coefficient
    // Interpolated point : v(t) = lerp(v0, v1, t) = v0 (1-t) + v1 t
    // Plane equation of interpolated portal : dot(v(t) - (p0 (1-t) + p1 t), n0 (1-t) + n1 t) = 0
    // Strategy is to first find t with plane intersects, restrict to solutions with t in [0,1], and check shape intersect at t.
    const float3 pv0 = v0 - p0.position;
    const float3 pv1 = v1 - p1.position;
    const float dot_pv0_n0 = dot(pv0, p0.normal);
    const float dot_pv0_n1 = dot(pv0, p1.normal);
    const float dot_pv1_n0 = dot(pv1, p0.normal);
    const float dot_pv1_n1 = dot(pv1, p1.normal);
    const float mixed_dots = dot_pv0_n1 + dot_pv1_n0;
    // Plane intersect t are solution of the 2nd order equation a t^2 + b t + c = 0 with
    const float a = dot_pv0_n0 + dot_pv1_n1 - mixed_dots;
    const float b = mixed_dots - 2 * dot_pv0_n0;
    const float c = dot_pv0_n0;
    // Gather t candidates
    float2 t_candidates = float2(-1, -1); // Invalid solutions
    if(a == 0) {
        // degree 1 equation, very common in desktop if some of the entities do not move (n, p, v)
        t_candidates[0] = -c / b;
    } else {
        // Full quadratic equation
        const float b2_m_4ac = mixed_dots * mixed_dots - 4 * dot_pv0_n0 * dot_pv1_n1; // Simpler expression with lots of cancellations applied.
        if(b2_m_4ac == 0) {
            t_candidates[0] = -b / (2 * a);
        } else if(b2_m_4ac > 0) {
            t_candidates = (-b + float2(-1, 1) * sqrt(b2_m_4ac)) / (2 * a);
        }
    }
    // Scan both solutions
    uint intersect_count = 0;
    [unroll]
    for(uint i = 0; i < 2; i += 1) {
        const float t = t_candidates[i];
        if(t == saturate(t)) {
            // t in [0, 1]    
            const Portal interpolated = Portal::lerp(p0, p1, t);
            intersect_count += interpolated.is_plane_point_in_shape(lerp(v0, v1, t)) ? 1 : 0;
        }
    }
    return intersect_count;
}

float Portal::distance_to_point(float3 p) {
    const float3 v = p - position;
    const float2 axis_projections = float2(dot(x_axis, v), dot(y_axis, v));
    const float2 axis_length_sq = float2(dot(x_axis, x_axis), dot(y_axis, y_axis));
    const float2 normalized_axis_projections = axis_projections / axis_length_sq;
    if(is_ellipse) {
        const float ellipse_radius_factor = length(normalized_axis_projections); // 1 on ellipse, <1 interior, >1 exterior
        const float clamp_to_ellipse = ellipse_radius_factor > 1 ? 1 / ellipse_radius_factor : 1;
        const float3 closest_portal_point = clamp_to_ellipse * (normalized_axis_projections.x * x_axis + normalized_axis_projections.y * y_axis);
        return distance(closest_portal_point, v);
    } else /* quad */ {
        const float2 clamped_axis_coords = clamp(normalized_axis_projections, -1, 1);
        const float3 closest_portal_point = clamped_axis_coords.x * x_axis + clamped_axis_coords.y * y_axis;
        return distance(closest_portal_point, v);
    }
}

///////////////////////////////////////////////////////////////////////////
// CRT encodings

uint4 Header::encode() {
    return uint4(
        (is_enabled ? 0x1 : 0x0) |
        (camera_in_portal[0] ? 0x2 : 0x0) | (camera_in_portal[1] ? 0x4 : 0x0) |
        (stereo_eye_in_portal[0] ? 0x8 : 0x0) | (stereo_eye_in_portal[1] ? 0x10 : 0x0),
        portal_mask,
        0,
        mesh_probe_count
    );
}
static Header Header::decode(uint4 pixel) { 
    Header h;
    h.is_enabled = pixel.x & 0x1;
    h.camera_in_portal[0] = pixel.x & 0x2;
    h.camera_in_portal[1] = pixel.x & 0x4;
    h.stereo_eye_in_portal[0] = pixel.x & 0x8;
    h.stereo_eye_in_portal[1] = pixel.x & 0x10;
    h.portal_mask = pixel.y;
    h.mesh_probe_count = pixel.w;
    return h;
}

static PortalPixel0 PortalPixel0::decode(uint4 pixel) {
    const float4 pixel_fp = asfloat(pixel);
    PortalPixel0 o;
    o.position = pixel_fp.xyz;
    o.radius_sq = pixel_fp.w;
    return o;
}

void Portal::encode(out uint4 pixels[2]) {
    // Pixel 0
    pixels[0] = asuint(float4(position, radius_sq));

    // Pixel 1
    const uint3 axis_packed = (f32tof16(y_axis) << 16) | f32tof16(x_axis);
    pixels[1] = uint4(axis_packed, is_ellipse ? 0x1 : 0x0);
}
static Portal Portal::decode(PortalPixel0 pixel0, uint4 pixel1) {
    Portal p;
    p.position = pixel0.position;

    p.is_ellipse = pixel1.w & 0x1;
    p.x_axis = f16tof32(pixel1.xyz & 0xFFFF);
    p.y_axis = f16tof32(pixel1.xyz >> 16);

    p.finalize();
    return p;
}

uint4 MeshProbeConfig::encode() {
    const uint radius_and_parent = f32tof16(radius) | ((parent & 0xFFFF) << 16);
    return uint4(asuint(position), radius_and_parent);
}
static MeshProbeConfig MeshProbeConfig::decode(uint4 pixel) {
    MeshProbeConfig probe;
    probe.position = asfloat(pixel.xyz);
    probe.radius = f16tof32(pixel.w & 0xFFFF);
    probe.parent = (pixel.w >> 16) & 0xFFFF;
    return probe;
}

uint4 MeshProbeState::encode() {
    const uint bits = (traversing_portal_mask & 0x7FFFFFFF) | (in_portal ? 0x80000000 : 0x0);
    return uint4(asuint(position), bits);
}
static MeshProbeState MeshProbeState::decode(uint4 pixel) {
    MeshProbeState probe;
    probe.position = asfloat(pixel.xyz);
    probe.traversing_portal_mask = pixel.w & 0x7FFFFFFF;
    probe.in_portal = pixel.w & 0x80000000;
    return probe;
}

///////////////////////////////////////////////////////////////////////////

bool Header::camera_portal_state(float vrc_camera_mode) {
    #ifdef USING_STEREO_MATRICES
    if(vrc_camera_mode == 0) {
        // VR mode: only the main one is tracked with stereo offsets.
        return stereo_eye_in_portal[unity_StereoEyeIndex];
    } else {
        // For all other assume this is photo camera. Maybe restrict to 1-2 (VR or desktop handheld camera)
        return camera_in_portal[1];
    }
    #else
    // Assume desktop centered or photo camera ; these are the only 2 we track.
    return camera_in_portal[vrc_camera_mode == 0 ? 0 : 1];
    #endif
}

// Render function

bool pixel_get_depth_portal_id(float4 pixel, out uint portal_id) {
    if(pixel.a <= -1) {
        portal_id = -(1 + pixel.a);
        return true;
    } else {
        return false;
    }
}

#endif