#include <flutter/runtime_effect.glsl>

// Single-pass ambient lighting shader — computes the combined darkness
// mask for all lights in one fragment shader invocation, replacing the
// saveLayer + dark rect + N light hole draws (BlendMode.dstOut) with
// one full-screen quad draw.
//
// Uniforms:
//   uSize              - viewport size (pixels)
//   uAmbientColor      - ARGB color of the ambient darkness (premultiplied alpha expected)
//   uAmbientBrightness - effective ambient brightness (0=fully dark, 1=fully bright)
//   uLightCount        - number of active lights
//   uLights[32]        - packed light data: vec4(pos.x, pos.y, radius, intensity)
//   uLightColors[32]   - light color ARGB (alpha = tint strength, 0 = no tint)
//   uLightFlags[32]    - bitfield: x=castsShadows, y=hasCone, z=coneAngle, w=coneDirection
//   uLightConeDirs[32] - cone direction (radians, 0=right, clockwise)
//
// The shader outputs a premultiplied-alpha color where:
//   - RGB = ambientColor.rgb * (1 - maxLightReveal)
//   - A   = ambientColor.a * (1 - maxLightReveal)
// This can be drawn with BlendMode.srcOver over the already-rendered scene
// to achieve the same effect as the multi-pass darkness mask.

uniform vec2 uSize;
uniform vec4 uAmbientColor;
uniform float uAmbientBrightness;
uniform int uLightCount;
uniform vec4 uLights[32];
uniform vec4 uLightColors[32];
uniform vec4 uLightFlags[32];
uniform float uLightConeDirs[32];

out vec4 fragColor;

float falloff(float t) {
  if (t <= 0.6) return 1.0;
  if (t <= 0.8) return mix(1.0, 0.7, (t - 0.6) / 0.2);
  if (t <= 0.92) return mix(0.7, 0.25, (t - 0.8) / 0.12);
  if (t <= 1.0) return mix(0.25, 0.0, (t - 0.92) / 0.08);
  return 0.0;
}

float coneFalloff(vec2 toFrag, float coneAngle, float coneDirection) {
  if (coneAngle <= 0.0) return 1.0;
  float rayAngle = atan(toFrag.y, toFrag.x);
  float diff = abs(rayAngle - coneDirection);
  if (diff > 3.14159265359) diff = 6.28318530718 - diff;
  float halfAngle = coneAngle * 0.5;
  if (diff > halfAngle) return 0.0;
  return 1.0 - (diff / halfAngle);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec4 ambient = uAmbientColor;
  float baseAlpha = ambient.a * (1.0 - uAmbientBrightness);

  // If no lights or fully bright ambient, just output ambient darkness
  if (uLightCount == 0 || uAmbientBrightness >= 1.0) {
    fragColor = vec4(ambient.rgb * baseAlpha, baseAlpha);
    return;
  }

  float maxReveal = 0.0;

  for (int i = 0; i < 32; i++) {
    if (i >= uLightCount) break;

    vec4 light = uLights[i];
    vec2 lightPos = light.xy;
    float radius = light.z;
    float intensity = light.w;

    if (radius <= 0.0 || intensity <= 0.0) continue;

    vec2 toFrag = fragCoord - lightPos;
    float dist = length(toFrag);

    if (dist > radius) continue;

    // Cone light check
    vec4 flags = uLightFlags[i];
    bool hasCone = flags.y > 0.5;
    if (hasCone) {
      float coneAngle = flags.z;
      float coneDir = uLightConeDirs[i];
      float coneFactor = coneFalloff(toFrag, coneAngle, coneDir);
      if (coneFactor <= 0.0) continue;
      intensity *= coneFactor;
    }

    // Note: shadow casting (flags.x) is not handled in this single-pass
    // shader — lights with castsShadows=true should fall back to the
    // CPU path or be handled separately. For now we treat them as
    // non-shadow-casting in this pass.

    float t = dist / radius;
    float strength = falloff(t) * intensity;
    maxReveal = max(maxReveal, strength);
  }

  // Clamp reveal to [0, 1]
  maxReveal = clamp(maxReveal, 0.0, 1.0);

  // Final darkness alpha: base darkness * (1 - maxReveal)
  // When maxReveal=1 (fully lit), alpha=0 (transparent, scene shows through)
  // When maxReveal=0 (no light), alpha=baseAlpha (full ambient darkness)
  float finalAlpha = baseAlpha * (1.0 - maxReveal);
  fragColor = vec4(ambient.rgb * finalAlpha, finalAlpha);
}