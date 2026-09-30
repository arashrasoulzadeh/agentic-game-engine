#include <flutter/runtime_effect.glsl>

// Colorblind simulation shader.
// Applies color vision deficiency simulation to the rendered scene.
// Based on the standard colorblind simulation matrices.

uniform sampler2D uTexture;
uniform vec2 uSize;
uniform int uColorblindType; // 0=none, 1=protanopia, 2=deuteranopia, 3=tritanopia
uniform float uSeverity; // 0.0 to 1.0

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  
  vec4 color = texture(uTexture, uv);
  
  if (uColorblindType == 0 || uSeverity <= 0.0) {
    fragColor = color;
    return;
  }
  
  // Colorblind simulation matrices (from Viénot et al. 1999)
  // These transform normal vision to colorblind vision
  mat3 protanopiaMatrix = mat3(
    0.567, 0.433, 0.000,
    0.558, 0.442, 0.000,
    0.000, 0.242, 0.758
  );
  
  mat3 deuteranopiaMatrix = mat3(
    0.625, 0.375, 0.000,
    0.700, 0.300, 0.000,
    0.000, 0.300, 0.700
  );
  
  mat3 tritanopiaMatrix = mat3(
    0.950, 0.050, 0.000,
    0.000, 0.433, 0.567,
    0.000, 0.475, 0.525
  );
  
  mat3 matrix;
  if (uColorblindType == 1) {
    matrix = protanopiaMatrix;
  } else if (uColorblindType == 2) {
    matrix = deuteranopiaMatrix;
  } else {
    matrix = tritanopiaMatrix;
  }
  
  // Apply severity (lerp between normal and colorblind)
  vec3 rgb = color.rgb;
  vec3 simulated = matrix * rgb;
  rgb = mix(rgb, simulated, uSeverity);
  
  fragColor = vec4(rgb, color.a);
}