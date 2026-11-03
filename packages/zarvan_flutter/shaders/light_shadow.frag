#include <flutter/runtime_effect.glsl>

// GPU-based point light with real per-pixel shadow occlusion against a
// small set of line-segment occluders (converted on the CPU side from
// nearby solid TileMap tile edges / light-blocking Colliders — see
// EngineView._gpuLightSegmentsFor's doc comment for how that
// conversion works and why it's capped at maxSegments).
//
// This replaces the CPU per-ray raycastTileMap sweep (one DDA walk per
// sampled angle, up to shadowRayCount times per light per frame) with
// one ray-vs-segment intersection test per segment per PIXEL, run in
// parallel across every pixel on the GPU instead of sequentially per
// ray on the CPU -- the same "outline occluders as line segments"
// technique real-time engines use for cheap 2D point-light shadows.
//
// Draws an *additive* glow (BlendMode.plus against the real scene, see
// Light2D.useGpuShadows's doc comment) rather than replicating the CPU
// path's darkness-mask/reveal semantics exactly -- a deliberately
// simpler v1 composited as its own pass after the standard lighting
// pass, not a byte-for-byte replacement for it.

uniform vec2 uSize;
uniform vec2 uLightPos;
uniform float uRadius;
uniform float uIntensity;
uniform vec4 uColor;
uniform float uSegmentCount;
uniform vec4 uSegments[32];

out vec4 fragColor;

float falloff(float t) {
  if (t <= 0.6) return 1.0;
  if (t <= 0.8) return mix(1.0, 0.7, (t - 0.6) / 0.2);
  if (t <= 0.92) return mix(0.7, 0.25, (t - 0.8) / 0.12);
  if (t <= 1.0) return mix(0.25, 0.0, (t - 0.92) / 0.08);
  return 0.0;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 toFrag = fragCoord - uLightPos;
  float dist = length(toFrag);

  if (dist > uRadius || uRadius <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  vec2 rayDir = dist > 0.0001 ? toFrag / dist : vec2(1.0, 0.0);

  bool occluded = false;
  for (int i = 0; i < 32; i++) {
    if (float(i) >= uSegmentCount) break;
    vec2 a = uSegments[i].xy;
    vec2 b = uSegments[i].zw;
    vec2 segDir = b - a;

    float denom = rayDir.x * segDir.y - rayDir.y * segDir.x;
    if (abs(denom) < 0.0001) continue;

    vec2 diff = a - uLightPos;
    float t = (diff.x * segDir.y - diff.y * segDir.x) / denom;
    float s = (diff.x * rayDir.y - diff.y * rayDir.x) / denom;

    // t is the distance along the ray (rayDir is unit length); a small
    // epsilon on both ends avoids self-occlusion right at the light's
    // own position or right at the lit pixel itself.
    if (t > 0.5 && t < dist - 0.5 && s >= 0.0 && s <= 1.0) {
      occluded = true;
      break;
    }
  }

  if (occluded) {
    fragColor = vec4(0.0);
    return;
  }

  float strength = falloff(dist / uRadius) * uIntensity;
  fragColor = vec4(uColor.rgb * uColor.a * strength, uColor.a * strength);
}
