import 'package:engine_core/engine_core.dart';

/// Attached to a `HudBar` entity to point it at whichever entity's
/// `Health` it should mirror — the "wire a health bar to a Health
/// component" glue `HealthHudSystem` reads each tick, so a game never
/// hand-writes `hudBar.value = health.current` itself.
class HealthHudLink {
  final EntityId source;
  HealthHudLink(this.source);

  Map<String, dynamic> toJson() => {'source': source};

  factory HealthHudLink.fromJson(Map<String, dynamic> json) =>
      HealthHudLink(json['source'] as int);
}
