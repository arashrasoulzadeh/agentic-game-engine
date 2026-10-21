import 'big_number.dart';

/// Named bonuses applied to a base value: the answer to "why is my output X".
///
/// The result is `(base + sum of additive) * product of multiplicative`. Every bonus has a **source
/// name** (an upgrade id, `"prestige"`, `"golden_cookie"`), so a source can be replaced or removed
/// when it changes or expires, and the whole thing can be explained to the player. Both operations
/// commute, so the order bonuses were added never changes the result.
class ModifierStack {
  ModifierStack();

  final Map<String, BigNumber> _additive = {};
  final Map<String, BigNumber> _multiplicative = {};

  /// Adds (or replaces) a flat bonus from [source].
  void setAdditive(String source, BigNumber amount) =>
      _additive[source] = amount;

  /// Adds (or replaces) a multiplier from [source] (`2` doubles, `1.5` is +50%).
  void setMultiplier(String source, BigNumber factor) =>
      _multiplicative[source] = factor;

  /// Removes everything [source] contributed. False if it contributed nothing.
  bool remove(String source) {
    final a = _additive.remove(source) != null;
    final m = _multiplicative.remove(source) != null;
    return a || m;
  }

  /// Every source name currently contributing.
  Set<String> get sources => {..._additive.keys, ..._multiplicative.keys};

  /// The combined multiplier alone.
  BigNumber get totalMultiplier =>
      _multiplicative.values.fold(BigNumber.one, (a, b) => a * b);

  /// `(base + additive) * multiplicative`.
  BigNumber apply(BigNumber base) {
    final flat = _additive.values.fold(base, (a, b) => a + b);
    return flat * totalMultiplier;
  }

  /// The steps of [apply] in a stable order (additive sources by name, then multipliers by name),
  /// each with the running value after it - for a "breakdown" tooltip.
  List<ModifierStep> breakdown(BigNumber base) {
    final steps = <ModifierStep>[ModifierStep('base', '=', base, base)];
    var running = base;
    for (final name in _additive.keys.toList()..sort()) {
      running = running + _additive[name]!;
      steps.add(ModifierStep(name, '+', _additive[name]!, running));
    }
    for (final name in _multiplicative.keys.toList()..sort()) {
      running = running * _multiplicative[name]!;
      steps.add(ModifierStep(name, '*', _multiplicative[name]!, running));
    }
    return steps;
  }

  Map<String, dynamic> toJson() => {
    'additive': {for (final e in _additive.entries) e.key: e.value.toJson()},
    'multiplicative': {
      for (final e in _multiplicative.entries) e.key: e.value.toJson(),
    },
  };

  factory ModifierStack.fromJson(Map<String, dynamic> json) {
    final s = ModifierStack();
    for (final e in ((json['additive'] as Map?) ?? const {}).entries) {
      s._additive[e.key as String] = BigNumber.fromJson(e.value as Object);
    }
    for (final e in ((json['multiplicative'] as Map?) ?? const {}).entries) {
      s._multiplicative[e.key as String] = BigNumber.fromJson(
        e.value as Object,
      );
    }
    return s;
  }
}

/// One line of a [ModifierStack.breakdown].
class ModifierStep {
  const ModifierStep(this.source, this.operation, this.value, this.running);

  final String source;

  /// `=` for the base, `+` for a flat bonus, `*` for a multiplier.
  final String operation;
  final BigNumber value;

  /// The total after this step.
  final BigNumber running;
}
