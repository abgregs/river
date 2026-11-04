// Glass, the kawa indicator (docs/design/kawa-identity.md): a pane of frost over
// the strokes that the voice ripples and clears. Ported from the Glass study's WebGL fragment
// shader (docs/design/studies/kawa/kawa-glass.template-r1.html, `FRAG`, its proposal branch) to a
// SwiftUI layer effect.
//
// The layer is the strokes at full strength, drawn by `GlassRenderer` at the muted strokes'
// presence. One height field per pixel, from the drops: the layer is sampled through its slope
// (refraction), blurred by the frost the drops' windows have not cleared, set to its ink
// strength, veiled with a fine grain, and lit by the same slope. The veil and the light are
// overlays on the layer, so the panel's own surface shows through between the strokes.
//
// Built by the Makefile (`xcrun metal`, `xcrun metallib`) into KawaGlass.metallib in the
// bundle's Resources; SwiftPM excludes this file.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Floats per drop in `drops`: x, y, time, ring strength, window radius (`GlassRenderer.dropStride`).
constant int STRIDE = 5;

// A ripple's tuning, from `GlassRenderer.arguments`: its size, its front's speed, its rings'
// wavelength and how long it lasts.
struct Ripple {
    float size, speed, wavelength, life;
};

// GLSL's smoothstep with the edges reversed, which the study relies on and Metal leaves undefined.
static float ramp(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// One drop's ring at p: a wave leaving the drop, as strong as the drop's tier.
static float wave(float2 p, float3 d, float strength, float time, Ripple rp) {
    float age = time - d.z;
    if (age < 0.0 || age > rp.life) return 0.0;
    float r = length(p - d.xy), front = rp.speed * sqrt(rp.size) * age, w = (1.5 + 2.6 * strength) * rp.size, u = r - front;
    return strength * exp(-age / (0.55 * sqrt(rp.size))) * sin(6.2831853 * u / (rp.wavelength * rp.size)) * exp(-(u * u) / (w * w));
}

// How much one drop has cleared the frost at p. A window opens behind the ring's front out to
// the tier's radius, holds, then fades back to frost. Its clock stops at release, so the frost
// never returns before it lifts.
static float cleared(float2 p, float3 d, float window, float clearTime, Ripple rp, float hold, float fade) {
    float ageC = clearTime - d.z;
    if (ageC < 0.0) return 0.0;
    float r = length(p - d.xy), radius = min(rp.speed * sqrt(rp.size) * ageC, window);
    return ramp(radius + 2.0, radius - 2.0, r) * clamp(radius / 2.0, 0.0, 1.0) * (1.0 - ramp(hold, hold + fade, ageC));
}

static float height(float2 p, device const float *drops, int count, float time, Ripple rp) {
    float h = 0.0;
    for (int i = 0; i + STRIDE <= count; i += STRIDE) {
        h += wave(p, float3(drops[i], drops[i + 1], drops[i + 2]), drops[i + 3], time, rp);
    }
    return h;
}

// A still grain, one cell per pixel at 2x, so the frost reads as frosted glass, not soft focus.
static float grain(float2 p) {
    float2 q = floor(p * 2.0);
    return fract(sin(dot(q, float2(12.9898, 78.233))) * 43758.5453);
}

// Positions are in the panel's points. The parameters after the layer are `GlassRenderer.arguments`,
// name for name and in its order; a test holds the two together. `light` points toward the light
// the panel's surface shares. `drops` holds x, y, time, ring strength and window radius per drop.
// `flat` is 1 under Reduce Motion: no ripples, and `clearing`, the level held from release, alone
// clears the frost.
[[ stitchable ]] half4 kawaGlass(float2 position, SwiftUI::Layer layer,
                                 float time, float clearTime, float form, float inkUp,
                                 float frost, float blur, float veilAmount, float grainAmount,
                                 float muted, float inkFrost, float inkClear,
                                 float refract, float spec, float2 light,
                                 float size, float speed, float wavelength, float life, float hold, float fade,
                                 float flat, float clearing,
                                 half4 veil, half4 highlight, float highlightAmount, half4 shade, float shadeAmount,
                                 device const float *drops, int count) {
    float2 p = position;
    Ripple rp = { size, speed, wavelength, life };
    // Windows overlap as a union, not a sum: two drops never clear more than one.
    float clear = 0.0;
    for (int i = 0; i + STRIDE <= count; i += STRIDE) {
        clear = max(clear, cleared(p, float3(drops[i], drops[i + 1], drops[i + 2]), drops[i + 4], clearTime, rp, hold, fade));
    }
    const float e = 0.08;
    float2 g = float2(height(p + float2(e, 0.0), drops, count, time, rp) - height(p - float2(e, 0.0), drops, count, time, rp),
                      height(p + float2(0.0, e), drops, count, time, rp) - height(p - float2(0.0, e), drops, count, time, rp))
               / (2.0 * e);
    g *= (1.0 - flat);
    clear = mix(clear, clearing * 1.4, flat);
    float2 at = p - g * refract;

    // Frost is a blur that grows: its radius and its veil scale with how far the glass has formed
    // and how much of it the voice has cleared here. At radius 0 the strokes are sharp.
    float open = clamp(clear, 0.0, 1.0);
    float fro = form * frost * (1.0 - open);
    float radius = blur * fro;
    half4 col = half4(0.0);
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 2.39996, rr = radius * sqrt((float(i) + 0.5) / 12.0);
        col += layer.sample(at + float2(cos(a), sin(a)) * rr);
    }
    col /= 12.0;

    // Ink: muted at first, rising with the frost to its strength, which is dimmer under the
    // frost than where the voice has cleared it.
    float target = mix(inkClear, inkFrost, form * (1.0 - open));
    col *= half(muted + (target - muted) * inkUp);

    // Overlays, premultiplied: the grained veil, then the light catching each ripple's slope,
    // and the shade on the far side.
    half v = half(veilAmount * fro * (1.0 + grainAmount * (grain(p) - 0.5) * 2.0));
    col = col * (1.0h - v) + half4(veil.rgb, 1.0h) * v;
    float lit = dot(g, light);
    half s = half(clamp(lit * spec, 0.0, 1.0) * form * highlightAmount);
    col = col * (1.0h - s) + half4(highlight.rgb, 1.0h) * s;
    half d = half(clamp(-lit * spec * 0.6, 0.0, 1.0) * form * shadeAmount);
    col = col * (1.0h - d) + half4(shade.rgb, 1.0h) * d;
    return col;
}
