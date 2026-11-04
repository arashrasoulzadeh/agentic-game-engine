#include <flutter/runtime_effect.glsl>

// One-pass post-processing over a captured frame: pixelate, chromatic
// aberration, bloom, CRT curvature + scanlines + phosphor mask, vignette,
// film grain. Every effect is off when its strength is 0, so the Dart side
// only sets what the game asked for.
//
//   uSize - viewport size in pixels
//   uA    - x bloom intensity, y bloom threshold, z bloom radius (px), w chromatic aberration (px)
//   uB    - x pixel size (px, 0 = off), y scanline strength, z CRT curvature, w vignette strength
//   uC    - x time (s), y grain strength, z phosphor mask strength, w scanline spacing (px)
//   uTex  - the captured frame

uniform vec2 uSize;
uniform vec4 uA;
uniform vec4 uB;
uniform vec4 uC;
uniform sampler2D uTex;

out vec4 fragColor;

vec3 grab(vec2 uv) {
  return texture(uTex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;

  // CRT barrel distortion
  float curve = uB.z;
  if (curve > 0.0) {
    vec2 c = uv * 2.0 - 1.0;
    c *= 1.0 + curve * dot(c, c) * 0.25;
    uv = c * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
      fragColor = vec4(0.0, 0.0, 0.0, 1.0);
      return;
    }
  }

  // pixelate
  if (uB.x > 0.0) {
    vec2 cells = uSize / uB.x;
    uv = (floor(uv * cells) + 0.5) / cells;
  }

  // chromatic aberration: split channels outward from the centre
  vec3 col;
  if (uA.w > 0.0) {
    vec2 off = (uv - 0.5) * (uA.w / uSize.x) * 2.0;
    col = vec3(grab(uv + off).r, grab(uv).g, grab(uv - off).b);
  } else {
    col = grab(uv);
  }

  // bloom: bright-pass of a two-ring blur added back on top
  if (uA.x > 0.0) {
    vec3 sum = vec3(0.0);
    float total = 0.0;
    for (int ring = 1; ring <= 2; ring++) {
      float r = uA.z * float(ring) * 0.5;
      for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398;
        vec2 o = vec2(cos(a), sin(a)) * r / uSize;
        vec3 s = grab(uv + o);
        float lum = dot(s, vec3(0.299, 0.587, 0.114));
        float w = smoothstep(uA.y, uA.y + 0.25, lum);
        sum += s * w;
        total += 1.0;
      }
    }
    col += sum / total * uA.x * 2.0;
  }

  // scanlines + phosphor mask
  if (uB.y > 0.0) {
    float line = 0.5 + 0.5 * sin(frag.y * 6.2831853 / max(uC.w, 1.5));
    col *= 1.0 - uB.y * (1.0 - line);
  }
  if (uC.z > 0.0) {
    float m = mod(floor(frag.x), 3.0);
    vec3 mask = vec3(m < 1.0 ? 1.0 : 1.0 - uC.z,
                     (m >= 1.0 && m < 2.0) ? 1.0 : 1.0 - uC.z,
                     m >= 2.0 ? 1.0 : 1.0 - uC.z);
    col *= mask;
  }

  // vignette
  if (uB.w > 0.0) {
    vec2 d = (frag / uSize) - 0.5;
    col *= 1.0 - uB.w * smoothstep(0.25, 0.75, dot(d, d) * 2.0);
  }

  // film grain
  if (uC.y > 0.0) {
    col += (hash(frag + uC.x * 61.0) - 0.5) * uC.y;
  }

  fragColor = vec4(col, 1.0);
}
