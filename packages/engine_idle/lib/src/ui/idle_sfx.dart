/// Optional one-shot feedback hooks for idle player actions.
///
/// The engine never loads audio assets; wire these to [AudioManager.playSound]
/// (or haptics). Null callbacks are no-ops so games opt in per event.
class IdleSfx {
  /// Creates hooks; omit any callback to skip that event.
  const IdleSfx({
    this.onBuy,
    this.onUpgrade,
    this.onTap,
    this.onPrestige,
    this.onGolden,
  });

  /// After a successful generator purchase.
  final void Function()? onBuy;

  /// After a successful upgrade purchase.
  final void Function()? onUpgrade;

  /// After a manual tap.
  final void Function()? onTap;

  /// After a successful prestige.
  final void Function()? onPrestige;

  /// After claiming a golden offer.
  final void Function()? onGolden;
}
