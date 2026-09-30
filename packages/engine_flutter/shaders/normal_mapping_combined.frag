#include <flutter/runtime_effect.glsl>

// Normal mapping shader for 2D sprites using a COMBINED TEXTURE.
// The combined texture contains the diffuse map in the LEFT HALF and the
// normal map in the RIGHT HALF (side by side). This works around Flutter's
// single-texture FragmentShader limitation.
//
// Uniforms:
//   uCombinedTexture   - combined texture (diffuse left half, normal right half)
//   uSize              - viewport size (pixels)
//   uLightCount        - number of active lights (max 8 for performance)
//   uLights[8]         - packed light data: vec4(pos.x, pos.y, radius, intensity)
//   uLightColors[8]    - light color ARGB (alpha = tint strength, 0 = no tint)
//   uLightFalloff[8]   - light falloff type: 0=smooth, 1=linear, 2=inverse square
//   uCameraPos         - camera position in world space
//   uCameraZoom        - camera zoom factor
//   uSpriteWorldPos    - sprite world position (center)
//   uSpriteScale       - sprite scale (X, Y)
//   uSpriteRotation    - sprite rotation in radians
//   uIsScreenSpace     - whether the sprite is screen-space (no camera transform)
//   uSpriteScreenRect  - sprite screen rect: vec4(left, top, right, bottom)
//
// Normal map encoding (standard tangent space):
//   R = X (-1..1, tangent U direction)
//   G = Y (-1..1, tangent V direction)
//   B = Z (0..1, facing viewer, stored as 0..1 mapped from -1..1)
//   A = unused (often 1 or height/occlusion)
//
// Lighting model: Lambertian diffuse with distance falloff
//   L = normalize(lightPos - fragWorldPos)
//   N = unpackNormal(normalMapSample)
//   diffuse = max(dot(N, L), 0.0) * lightColor * lightIntensity * falloff(dist/radius)

uniform sampler2D uCombinedTexture;
uniform vec2 uSize;
uniform float uLightCount;
uniform vec4 uLights[8];
uniform vec4 uLightColors[8];
uniform float uLightFalloff[8];
uniform vec2 uCameraPos;
uniform float uCameraZoom;
uniform vec2 uSpriteWorldPos;
uniform vec2 uSpriteScale;
uniform float uSpriteRotation;
uniform float uIsScreenSpace; // 0.0 = world space, 1.0 = screen space
uniform vec4 uSpriteScreenRect; // left, top, right, bottom in screen pixels

out vec4 fragColor;

vec3 unpackNormal(vec3 packed) {
  // Packed normal: R=X(-1..1), G=Y(-1..1), B=Z(0..1 mapped from -1..1)
  // Standard encoding maps -1..1 to 0..1, so unpack: val * 2.0 - 1.0
  return vec3(packed.xy * 2.0 - 1.0, packed.z * 2.0 - 1.0);
}

float falloff(float t, float falloffType) {
  if (falloffType == 0.0) {
    // Smooth falloff (same as ambient_lighting.frag)
    if (t <= 0.6) return 1.0;
    if (t <= 0.8) return mix(1.0, 0.7, (t - 0.6) / 0.2);
    if (t <= 0.92) return mix(0.7, 0.25, (t - 0.8) / 0.12);
    if (t <= 1.0) return mix(0.25, 0.0, (t - 0.92) / 0.08);
    return 0.0;
  } else if (falloffType == 1.0) {
    // Linear falloff
    return max(1.0 - t, 0.0);
  } else {
    // Inverse square falloff
    return max(1.0 / (1.0 + t * t), 0.0);
  }
}

void main() {
  // FlutterFragCoord().xy gives screen-space pixel coordinates
  vec2 fragCoord = FlutterFragCoord().xy;

  // Compute UV coordinates from sprite screen rect
  // uSpriteScreenRect = vec4(left, top, right, bottom)
  vec2 spriteScreenSize = vec2(uSpriteScreenRect.z - uSpriteScreenRect.x, uSpriteScreenRect.w - uSpriteScreenRect.y);
  vec2 localCoord = vec2(0.0);
  if (spriteScreenSize.x > 0.0 && spriteScreenSize.y > 0.0) {
    localCoord = (fragCoord - uSpriteScreenRect.xy) / spriteScreenSize;
  }

  // Sample from combined texture: diffuse in left half (0.0-0.5), normal in right half (0.5-1.0)
  vec2 diffuseUV = localCoord * 0.5;
  vec2 normalUV = localCoord * 0.5 + vec2(0.5, 0.0);

  // Sample diffuse texture
  vec4 diffuse = texture(uCombinedTexture, diffuseUV);

  // Sample normal map
  vec3 normalPacked = texture(uCombinedTexture, normalUV).rgb;
  vec3 normal = unpackNormal(normalPacked);

  // If normal is flat (0,0,1) i.e. unpacked from (0.5, 0.5, 1.0),
  // the normal map has no data - just output diffuse
  if (normal.x == 0.0 && normal.y == 0.0 && normal.z == 1.0) {
    fragColor = diffuse;
    return;
  }

  // Transform normal by sprite rotation if needed
  // For 2D, rotation is in the XY plane (around Z axis)
  if (uSpriteRotation != 0.0) {
    float c = cos(uSpriteRotation);
    float s = sin(uSpriteRotation);
    mat2 rot = mat2(c, -s, s, c);
    normal.xy = rot * normal.xy;
  }

  // Scale normal by sprite scale (for non-uniform scaling)
  // Note: we don't scale Z, only XY
  normal.xy *= uSpriteScale;
  normal = normalize(normal);

  // Calculate fragment world position
  vec2 fragWorldPos;
  if (uIsScreenSpace > 0.5) {
    // Screen-space sprite
    fragWorldPos = uSpriteWorldPos;
  } else {
    // World-space sprite: reconstruct world position
    // Approximation: use sprite world pos + local offset
    vec2 spriteWorldSize = uSpriteScale * uSize / uCameraZoom;
    fragWorldPos = uSpriteWorldPos + (localCoord - 0.5) * spriteWorldSize;
  }

  vec3 totalLight = vec3(0.0);

  for (int i = 0; i < 8; i++) {
    if (i >= uLightCount) break;

    vec4 light = uLights[i];
    vec2 lightPos = light.xy;
    float radius = light.z;
    float intensity = light.w;

    if (radius <= 0.0 || intensity <= 0.0) continue;

    vec2 toLight = lightPos - fragWorldPos;
    float dist = length(toLight);

    if (dist > radius) continue;

    // Light direction in 2D (XY plane), normal is 3D (XY tangent, Z facing)
    // For 2D Lambertian: dot(normal.xy, normalize(toLight))
    vec2 lightDir2D = normalize(toLight);
    float ndotl = max(dot(normal.xy, lightDir2D), 0.0);

    if (ndotl <= 0.0) continue;

    vec4 lightColor = uLightColors[i];
    float falloffType = uLightFalloff[i];
    float t = dist / radius;
    float attenuation = falloff(t, falloffType) * intensity;

    vec3 lightRGB = lightColor.rgb * lightColor.a;
    totalLight += ndotl * lightRGB * attenuation;
  }

  // Apply lighting: diffuse * (ambient + totalLight)
  // Ambient is 0.2 (base visibility without lights)
  float ambient = 0.2;
  vec3 finalColor = diffuse.rgb * (ambient + totalLight);

  // Clamp and output
  finalColor = clamp(finalColor, 0.0, 1.0);
  fragColor = vec4(finalColor, diffuse.a);
}