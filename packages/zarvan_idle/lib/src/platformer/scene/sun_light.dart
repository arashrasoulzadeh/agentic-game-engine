/// A small warm light standing in for the sun, optionally dimming the rest of
/// the scene so it reads. Set on `WaveCombatConfig.sun`; null means no
/// lighting at all (the default).
class SunLight {
  const SunLight({
    this.x = 90,
    this.y = 70,
    this.radius = 200,
    this.intensity = 0.6,
    this.colorArgb = 0x14FFE2A0,
    this.ambientBrightness = 0.88,
  });

  /// World position of the light.
  final double x;
  final double y;

  /// Reach in world units.
  final double radius;

  /// `Light2D.intensity` (0..1): how much of the ambient darkness it lifts.
  final double intensity;

  /// Additive tint as ARGB; alpha 0 gives plain light with no colour.
  final int colorArgb;

  /// Scene brightness away from the light (1 = no darkening).
  final double ambientBrightness;
}
