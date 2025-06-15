#ifndef LERELDARION_PORTAL_H
#define LERELDARION_PORTAL_H

namespace LPortal {
    // Encoding :
    // 1 system control pixel at (0, 0) :
    // - R = f16 sentinel value (>1) to check if system is enabled & grabpass is RGBA16_FLOAT and not RGBA8_UNORM.
    static const float sentinel = 3.141592653589793;
    // - G = u14 bitmask for enabled portals
    // Portal i : 3 pixels at ([1..3]+3*i, 0).
    // - Pixel 1 : xyzw as u14[0..3]
    // - Pixel 2 : xyz = normal f16, w as u14[4]
    // - Pixel 3 : xyz = tangent f16, w as u14[5]
    // World pos is encoded as a `world_position_bits` fixed point integer stuck into u14[01, 23, 45]
    static const int world_position_bits = 26;
    static const float world_position_precision = 0.001;
    // Range of 67km for millimeter precision.

    struct System {
        uint mask; // Enabled portal ids
        
        float4 encode();
        static System decode(float4 pixel);

        bool has_portal() { return mask != 0; }
        uint next_portal() {
            uint index = firstbitlow(mask);
            mask ^= 0x1 << index; // Mark as seen
            return index;
        }
    };
    
    struct Portal {
        float3 position;
        float3 x_axis;
        float3 y_axis;
        bool is_ellipse; // false = quad, true = ellipse TODO

        float3 normal; // Only when decoded
        
        void encode(out float4 pixels[3]);
        static Portal decode(float4 pixels[3]);

        bool segment_intersect(float3 origin, float3 end);
    };
    
    ///////////////////////////////////////////////////////////////////////////

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

    // https://github.com/pema99/shader-knowledge/blob/main/tips-and-tricks.md#encoding-and-decoding-data-in-a-grabpass
    uint f16_to_u14(precise float input) { return f32tof16(input) & 0x00003fff; }
    uint3 f16_to_u14(precise float3 input) { return f32tof16(input) & 0x00003fff; }
    precise float u14_to_f16(uint input) { return f16tof32(input & 0x00003fff); }
    precise float3 u14_to_f16(uint3 input) { return f16tof32(input & 0x00003fff); }
    
    float4 System::encode() {
        return float4(sentinel, u14_to_f16(mask), 0, 0);
    }
    static System System::decode(float4 pixel) {
        System system;
        system.mask = 0x0;
        // If sentinel is wrong, just return system with empty portal mask
        if (abs(pixel[0] - sentinel) < 0.001) {
            system.mask = f16_to_u14(pixel[1]);
        }
        return system;
    }

    void Portal::encode(out float4 pixels[3]) {
        // World pos
        int3 signed_fp_pos = int3(position * (1.0 / world_position_precision));
        uint3 unsigned_fp_pos = uint3(signed_fp_pos + int(0x1 << (world_position_bits - 1)));
        unsigned_fp_pos &= (0x1 << world_position_bits) - 1; // Mask to world_position_bits, unlikely to trigger

        // Use one of the unused bits to fit is_ellipse
        if(is_ellipse) {
            unsigned_fp_pos[0] ^= 0x1 << world_position_bits;
        }

        float3 upper_bits = u14_to_f16(unsigned_fp_pos >> 14);
        float3 lower_bits = u14_to_f16(unsigned_fp_pos);

        pixels[0] = float4(upper_bits, lower_bits.x);
        pixels[1] = float4(x_axis, lower_bits.y);
        pixels[2] = float4(y_axis, lower_bits.z);
    }
    static Portal Portal::decode(float4 pixels[3]) {
        Portal p;

        float3 lower_bits = float3(pixels[0][3], pixels[1][3], pixels[2][3]);
        uint3 unsigned_fp_pos = (f16_to_u14(pixels[0].xyz) << 14) | f16_to_u14(lower_bits);
        
        p.is_ellipse = unsigned_fp_pos[0] & 0x1 << world_position_bits;
        
        unsigned_fp_pos &= (0x1 << world_position_bits) - 1; // Sanitize bits
        int3 signed_fp_pos = int3(unsigned_fp_pos) - int(0x1 << (world_position_bits - 1));
        p.position = signed_fp_pos * world_position_precision;

        p.x_axis = pixels[1].xyz;
        p.y_axis = pixels[2].xyz;

        p.normal = cross(p.x_axis, p.y_axis);
        return p;
    }
}

#endif