#ifndef LERELDARION_PORTAL_H
#define LERELDARION_PORTAL_H

// CRT Encodings :
// Header at (0, 0).
// - x : u32 is a bitmask of active portals for fast scan.
// - w : system is active
// Camera pixels
// - pixel = uint4 as float3(wpos.xyz), in_portal as bit0 of w.
// - main camera as (0, 1), photo camera as (0, 2).
// Portal `i` is encoded by 2 f32x4 pixels
// - pixel0 at (1, i) = uint4 as float4(wpos.xyz, w = radius^2)
// - pixel1 at (2, i) = x/y axis as f16x6 in u16x6 in u32x3. is_ellipse as bit0 in w.

struct Header {
    uint portal_mask;
    bool is_enabled;

    bool has_portals() { return portal_mask != 0x0; }
    uint pop_active_portal() {
        uint index = firstbitlow(portal_mask);
        portal_mask ^= 0x1 << index; // Mask as seen
        return index;
    }

    uint4 encode_crt() { return uint4(portal_mask, 0, 0, is_enabled ? 0x1 : 0x0); }
    static Header decode_crt(uint4 pixel) { 
        Header h;
        h.portal_mask = pixel.r;
        h.is_enabled = pixel.a & 0x1;
        return h;
    }
    static Header decode_crt(Texture2D<uint4> crt) { return decode_crt(crt[uint2(0, 0)]); }
};

struct Camera {
    float3 position;
    bool in_portal; // Only present in CRT ; state of the camera.

    uint4 encode_crt() { return uint4(asuint(position), in_portal ? 0x1 : 0x0) ; }
    static Camera decode_crt(uint4 pixel) {
        Camera c;
        c.position = asfloat(pixel.rgb);
        c.in_portal = pixel.a & 0x1;
        return c;
    }
    static Camera decode_crt(Texture2D<uint4> crt, uint index) { return decode_crt(crt[uint2(0, 1 + index)]); }
};

struct PortalPixel0 {
    // Partial portal with data from pixel 0 of CRT.
    // Can provide a quick intersection test, to see if the precise test with data from pixel 1 is required.
    float3 position;
    float radius_sq;

    bool is_enabled() { return radius_sq > 0; }
    bool fast_intersect(float3 origin, float3 end);

    static PortalPixel0 decode_crt(uint4 pixel) {
        float4 pixel_fp = asfloat(pixel);
        PortalPixel0 o;
        o.position = pixel_fp.xyz;
        o.radius_sq = pixel_fp.w;
        return o;
    }
    static PortalPixel0 decode_crt(Texture2D<uint4> crt, uint index) { return decode_crt(crt[uint2(1, index)]); }
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
    bool segment_intersect(float3 origin, float3 end);
    
    void encode_crt(out uint4 pixels[2]);
    static Portal decode_crt(PortalPixel0 pixel0, uint4 pixel1);
    static Portal decode_crt(PortalPixel0 pixel0, Texture2D<uint4> crt, uint index) { return decode_crt(pixel0, crt[uint2(2, index)]); }

    void encode_grabpass(out float4 pixels[4]);
    static Portal decode_grabpass(float4 pixels[4]);
    static Portal decode_grabpass(Texture2D<float4> grabpass, uint index);
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
// CRT encodings

void Portal::encode_crt(out uint4 pixels[2]) {
    // Pixel 0
    pixels[0] = asuint(float4(position, radius_sq));

    // Pixel 1
    uint3 axis_packed = (f32tof16(y_axis) << 16) | f32tof16(x_axis);
    pixels[1] = uint4(axis_packed, is_ellipse ? 0x1 : 0x0);
}
static Portal Portal::decode_crt(PortalPixel0 pixel0, uint4 pixel1) {
    Portal p;
    p.position = pixel0.position;

    p.is_ellipse = pixel1.w & 0x1;
    p.x_axis = f16tof32(pixel1.xyz & 0xFFFF);
    p.y_axis = f16tof32(pixel1.xyz >> 16);

    p.finalize();
    return p;
}

///////////////////////////////////////////////////////////////////////////
// Grabpass encodings
// Use more pixels as grabpass are f16x4.

// https://github.com/pema99/shader-knowledge/blob/main/tips-and-tricks.md#encoding-and-decoding-data-in-a-grabpass
// The two bits are probably due to unauthorised encodings / denorm floats.
uint f16_to_u14(float input) { return f32tof16(input) & 0x00003fff; }
uint3 f16_to_u14(float3 input) { return f32tof16(input) & 0x00003fff; }
float u14_to_f16(uint input) { return f16tof32(input & 0x00003fff); }
float3 u14_to_f16(uint3 input) { return  f16tof32(input & 0x00003fff); }

struct Control {
    bool system_valid; // Decode only
    // TODO encode some animator values

    // f16 sentinel value (>1) to check if system is enabled & grabpass is RGBA16_FLOAT and not RGBA8_UNORM.
    static const float sentinel = 3.141592653589793;
    
    float4 encode_grabpass() {
        return float4(
            sentinel, 
            0,
            0,
            0
        );
    }
    static Control decode_grabpass(float4 pixel) {
        Control c;
        c.system_valid = abs(pixel[0] - sentinel) < 0.001;
        return c;
    }
    static Control decode_grabpass(Texture2D<float4> grabpass) { return decode_grabpass(grabpass[uint2(0, 0)]); }
};

void Portal::encode_grabpass(out float4 pixels[4]) {
    // World position needs full f32 => 9 x f16
    // axis can use f16 as they are not huge. 6 x f16.
    // last f16 is used for is_ellipse, for now float encoded.
    uint3 position_bits = asuint(position);
    pixels[0] = float4(u14_to_f16(position_bits)      , x_axis[0]);
    pixels[1] = float4(u14_to_f16(position_bits >> 14), x_axis[1]);
    pixels[2] = float4(u14_to_f16(position_bits >> 28), x_axis[2]);
    pixels[3] = float4(y_axis                         , is_ellipse);
}
static Portal Portal::decode_grabpass(float4 pixels[4]) {
    Portal p;
    uint3 position_bits = f16_to_u14(pixels[0].rgb) | (f16_to_u14(pixels[1].rgb) << 14) | (f16_to_u14(pixels[2].rgb) << 28);
    p.position = asfloat(position_bits);
    p.x_axis = float3(pixels[0].a, pixels[1].a, pixels[2].a);
    p.y_axis = pixels[3].rgb;
    p.is_ellipse = pixels[3].a;

    p.finalize();
    return p;
}
static Portal Portal::decode_grabpass(Texture2D<float4> grabpass, uint index) {
    float4 pixels[4] = {
        grabpass[uint2(1 + 4 * index, 0)],
        grabpass[uint2(2 + 4 * index, 0)],
        grabpass[uint2(3 + 4 * index, 0)],
        grabpass[uint2(4 + 4 * index, 0)],
    };
    return decode_grabpass(pixels);
}

///////////////////////////////////////////////////////////////////////////

float4 target_pixel_to_cs(uint2 position, float2 target_resolution) {
    float2 position_cs = (position * 2 - target_resolution + 1) / target_resolution; // +1 = center of pixels
    // https://docs.unity3d.com/Manual/SL-PlatformDifferences.html
    if (_ProjectionParams.x < 0) { position_cs.y = -position_cs.y; }
    return float4(position_cs, UNITY_NEAR_CLIP_VALUE, 1);
}

#endif