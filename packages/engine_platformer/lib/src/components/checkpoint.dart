/// Marks a level-authored entity (with `Position`) as a checkpoint a
/// player can activate by touching it — see `trackCheckpoints`. `id` is
/// for a game's own bookkeeping (e.g. deciding which checkpoints have
/// been seen for a completion percentage); the engine only cares about
/// `activated` and the entity's `Position`.
class Checkpoint {
  final String id;
  bool activated;

  Checkpoint(this.id, {this.activated = false});

  Map<String, dynamic> toJson() => {'id': id, 'activated': activated};

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
        json['id'] as String,
        activated: json['activated'] as bool? ?? false,
      );
}
