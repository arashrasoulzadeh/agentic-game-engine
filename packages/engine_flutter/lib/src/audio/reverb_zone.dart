import 'dart:math' as math;

/// A reverb zone that applies reverb to sounds within its bounds.
/// Can be used for caves, halls, outdoor spaces, etc.
class ReverbZone {
  final double x;
  final double y;
  final double width;
  final double height;
  
  /// Reverb decay time in seconds (RT60)
  final double decayTime;
  
  /// Pre-delay in milliseconds
  final double preDelay;
  
  /// Wet/dry mix (0 = dry, 1 = fully wet)
  final double wetLevel;
  
  /// Damping (0 = no damping, 1 = heavy damping)
  final double damping;
  
  /// Room size (0..1) - affects reverb density
  final double roomSize;
  
  /// Fade distance - reverb fades in/out over this distance at zone edges
  final double fadeDistance;

  ReverbZone({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.decayTime = 2.0,
    this.preDelay = 20.0,
    this.wetLevel = 0.3,
    this.damping = 0.5,
    this.roomSize = 0.5,
    this.fadeDistance = 50.0,
  });

  /// Checks if a point is inside the reverb zone (with fade distance)
  bool contains(double px, double py) {
    return px >= x - fadeDistance &&
           px <= x + width + fadeDistance &&
           py >= y - fadeDistance &&
           py <= y + height + fadeDistance;
  }

  /// Gets the reverb intensity at a point (0..1, with fade at edges)
  double getIntensity(double px, double py) {
    if (!contains(px, py)) return 0.0;
    
    // Full intensity in the core
    final coreLeft = x + fadeDistance;
    final coreRight = x + width - fadeDistance;
    final coreTop = y + fadeDistance;
    final coreBottom = y + height - fadeDistance;
    
    if (px >= coreLeft && px <= coreRight && py >= coreTop && py <= coreBottom) {
      return 1.0;
    }
    
    // Fade at edges
    double dist = 0;
    if (px < coreLeft) dist = math.max(dist, coreLeft - px);
    if (px > coreRight) dist = math.max(dist, px - coreRight);
    if (py < coreTop) dist = math.max(dist, coreTop - py);
    if (py > coreBottom) dist = math.max(dist, py - coreBottom);
    
    return (1.0 - dist / fadeDistance).clamp(0.0, 1.0);
  }

  /// Gets reverb parameters for a given intensity (0..1)
  ReverbParameters getParameters(double intensity) {
    return ReverbParameters(
      decayTime: decayTime,
      preDelay: preDelay,
      wetLevel: wetLevel * intensity,
      damping: damping,
      roomSize: roomSize,
    );
  }
}

/// Reverb parameters for audio engine integration.
class ReverbParameters {
  final double decayTime;
  final double preDelay;
  final double wetLevel;
  final double damping;
  final double roomSize;

  ReverbParameters({
    required this.decayTime,
    required this.preDelay,
    required this.wetLevel,
    required this.damping,
    required this.roomSize,
  });
}

/// Manages reverb zones for a scene.
class ReverbZoneManager {
  final List<ReverbZone> _zones = [];

  void addZone(ReverbZone zone) => _zones.add(zone);
  void removeZone(ReverbZone zone) => _zones.remove(zone);
  void clear() => _zones.clear();

  /// Gets combined reverb parameters for a position.
  ReverbParameters getParametersAt(double x, double y) {
    ReverbParameters? combined;
    double maxIntensity = 0;

    for (final zone in _zones) {
      final intensity = zone.getIntensity(x, y);
      if (intensity > 0) {
        final params = zone.getParameters(intensity);
        if (combined == null) {
          combined = params;
        } else {
          // Blend parameters based on intensity
          combined = _blendReverb(combined, params, intensity);
        }
        maxIntensity = math.max(maxIntensity, intensity);
      }
    }

    return combined ?? ReverbParameters(
      decayTime: 0,
      preDelay: 0,
      wetLevel: 0,
      damping: 0,
      roomSize: 0,
    );
  }

  ReverbParameters _blendReverb(ReverbParameters a, ReverbParameters b, double bWeight) {
    final aWeight = 1.0 - bWeight;
    return ReverbParameters(
      decayTime: a.decayTime * aWeight + b.decayTime * bWeight,
      preDelay: a.preDelay * aWeight + b.preDelay * bWeight,
      wetLevel: math.min(1.0, a.wetLevel * aWeight + b.wetLevel * bWeight),
      damping: a.damping * aWeight + b.damping * bWeight,
      roomSize: a.roomSize * aWeight + b.roomSize * bWeight,
    );
  }
}