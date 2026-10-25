import 'package:engine_core/engine_core.dart';

import 'sprite.dart';

/// Default red modulate tint for a damage hit flash.
const kDefaultHitFlashTint = 0xFFFF3333;

/// Default flash length in seconds.
const kDefaultHitFlashSeconds = 0.15;

/// Remaining hit-flash time on an entity that also has a [Sprite].
///
/// [HitFlashSystem] counts [remaining] down and writes [Sprite.tintArgb]
/// while the flash is active — the usual red blink when something takes
/// damage. Attach an empty [HitFlash] at spawn (or call [flashHit]); combat
/// code only needs to set [remaining] (or call [flashHit]) on a hit.
class HitFlash {
  /// Seconds of tint left. `0` means clear.
  double remaining;

  /// ARGB modulate color while [remaining] > 0.
  int tintArgb;

  HitFlash({
    this.remaining = 0,
    this.tintArgb = kDefaultHitFlashTint,
  });

  Map<String, dynamic> toJson() => {
        'remaining': remaining,
        'tintArgb': tintArgb,
      };

  factory HitFlash.fromJson(Map<String, dynamic> json) => HitFlash(
        remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
        tintArgb: (json['tintArgb'] as num?)?.toInt() ?? kDefaultHitFlashTint,
      );
}

/// Starts (or refreshes) a hit flash on [entity]. No-op if the entity has
/// no [HitFlash] component — spawn with `HitFlash()` when you want flashes.
void flashHit(
  World world,
  EntityId entity, {
  double seconds = kDefaultHitFlashSeconds,
  int? tintArgb,
}) {
  final flash = world.storeOf<HitFlash>().get(entity);
  if (flash == null) return;
  flash.remaining = seconds;
  if (tintArgb != null) flash.tintArgb = tintArgb;
}

/// Syncs [Sprite.tintArgb] from every [HitFlash] each tick.
class HitFlashSystem implements System {
  @override
  String get name => 'hitFlash';

  @override
  void update(World world, double dt) {
    final flashes = world.storeOf<HitFlash>();
    final sprites = world.storeOf<Sprite>();
    for (var i = 0; i < flashes.length; i++) {
      final entity = flashes.entityAt(i);
      final flash = flashes.denseAt(i);
      if (flash.remaining > 0) {
        flash.remaining = (flash.remaining - dt).clamp(0.0, double.infinity);
      }
      final sprite = sprites.get(entity);
      if (sprite == null) continue;
      sprite.tintArgb = flash.remaining > 0 ? flash.tintArgb : null;
    }
  }
}
