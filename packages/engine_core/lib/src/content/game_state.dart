/// Free-form, JSON-serializable data a `Game` carries across scene
/// switches — score, inventory, which rooms are unlocked, a
/// checkpoint. Exists because `SceneController.loadScene` deliberately
/// builds a brand-new `World` per scene (see `Scene`'s doc comment in
/// engine_flutter): that's correct for level geometry/entities, but a
/// game still needs *something* that survives the swap, the same way
/// `AIState.memory` is a per-entity blackboard a `Behavior` can carry
/// state in between ticks without a dedicated component type.
///
/// One instance is created once per running game (`Game.createInitialState`)
/// and handed to every `Scene.populate` call for that game's lifetime —
/// a scene reads whatever it needs from [data] on entry and writes
/// back before switching away. Nothing here is engine-enforced beyond
/// "it's a plain JSON-compatible map": what keys exist and what they
/// mean is entirely up to the game.
class GameState {
  final Map<String, dynamic> data;

  /// Schema migration version for save/load. Increment this when
  /// [data] changes shape in a way that breaks old saves.
  /// [SaveGame.load] will call [migrate] if the save's version differs
  /// from this value.
  final int migrationVersion;

  GameState([Map<String, dynamic>? data, this.migrationVersion = 1])
      : data = data ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'data': data,
        'migrationVersion': migrationVersion,
      };

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      json['migrationVersion'] as int? ?? 1,
    );
  }
}
