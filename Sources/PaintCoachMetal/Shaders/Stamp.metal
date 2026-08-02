#include <metal_stdlib>
using namespace metal;

// One brush stamp, expanded to a quad in the vertex shader.
struct StampInstance {
    float2 position;      // centre, canvas pixels
    float  diameter;      // canvas pixels
    float  opacity;
    float  rotation;      // radians
    float  eccentricity;  // width/height ratio
};

struct StampVertex {
    float4 clipPosition [[position]];
    float2 unitCoord;     // -1...1 across the stamp, for the falloff
    float  opacity;
};

// Expands each instance into a unit quad. Two triangles from four corners.
vertex StampVertex stamp_vertex(
    uint vertexID                        [[vertex_id]],
    uint instanceID                      [[instance_id]],
    constant StampInstance *instances    [[buffer(0)]],
    constant float2 &canvasSize          [[buffer(1)]]
) {
    // Triangle-strip corner order: BL, BR, TL, TR.
    const float2 corners[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    float2 corner = corners[vertexID];
    StampInstance stamp = instances[instanceID];

    // Scale to the stamp's ellipse, then rotate.
    float radius = stamp.diameter * 0.5;
    float2 scaled = float2(corner.x * radius * stamp.eccentricity, corner.y * radius);

    float c = cos(stamp.rotation);
    float s = sin(stamp.rotation);
    float2 rotated = float2(scaled.x * c - scaled.y * s, scaled.x * s + scaled.y * c);

    float2 canvasPoint = stamp.position + rotated;

    // Canvas pixels -> clip space. Y is flipped so canvas y grows downward.
    float2 normalized = canvasPoint / canvasSize;
    float2 clip = float2(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0);

    StampVertex out;
    out.clipPosition = float4(clip, 0.0, 1.0);
    out.unitCoord = corner;
    out.opacity = stamp.opacity;
    return out;
}

// Soft round tip. `hardness` shapes the edge: 1 is nearly hard, 0 is very soft.
fragment float4 stamp_fragment(
    StampVertex in                [[stage_in]],
    constant float4 &color        [[buffer(0)]],
    constant float  &hardness     [[buffer(1)]]
) {
    float distance = length(in.unitCoord);
    // Discard outside the circle so the quad corners stay transparent.
    if (distance > 1.0) {
        discard_fragment();
    }
    float edge = mix(0.35, 0.98, saturate(hardness));
    float coverage = 1.0 - smoothstep(edge, 1.0, distance);
    float alpha = coverage * in.opacity * color.a;

    // Premultiplied output, matching the blend state set on the pipeline.
    return float4(color.rgb * alpha, alpha);
}

// MARK: - Compositing

struct CompositeVertex {
    float4 clipPosition [[position]];
    float2 texCoord;
};

// Fullscreen triangle-strip quad for layer compositing.
vertex CompositeVertex composite_vertex(uint vertexID [[vertex_id]]) {
    const float2 corners[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    float2 corner = corners[vertexID];

    CompositeVertex out;
    out.clipPosition = float4(corner, 0.0, 1.0);
    // Flip V so texture row 0 is the top of the canvas.
    out.texCoord = float2((corner.x + 1.0) * 0.5, 1.0 - (corner.y + 1.0) * 0.5);
    return out;
}

// Composites a layer cache at a given opacity.
fragment float4 composite_fragment(
    CompositeVertex in            [[stage_in]],
    texture2d<float> cache        [[texture(0)]],
    constant float &opacity       [[buffer(0)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    // Cache is already premultiplied, so scaling all four channels is correct.
    return cache.sample(linearSampler, in.texCoord) * opacity;
}

// Writes transparent with blending disabled, erasing a scissored region.
fragment float4 erase_fragment(CompositeVertex in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 0.0);
}

// Fills the frame with a flat colour — the Background Color layer.
fragment float4 color_fragment(
    CompositeVertex in            [[stage_in]],
    constant float4 &color        [[buffer(0)]],
    constant float &opacity       [[buffer(1)]]
) {
    float alpha = color.a * opacity;
    return float4(color.rgb * alpha, alpha);
}
