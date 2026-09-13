/// Where `respawnPlayer` sends an entity back to — the world position
/// of the most recently activated `Checkpoint` it has touched, kept on
/// the entity itself (rather than tracked separately by the game) so it
/// serializes and reloads along with everything else via
/// `World.toJson`/`applyPatch`.
class LastCheckpoint {
  double x, y;
  LastCheckpoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory LastCheckpoint.fromJson(Map<String, dynamic> json) => LastCheckpoint(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      );
}
