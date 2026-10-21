import '../../engine_core.dart';

/// The standard analytics events of an idle game, sent through [AnalyticsManager] (so the player's
/// consent setting applies) or any other sink a test or game supplies.
///
/// Payload amounts are plain numbers (`BigNumber.toDouble`) so providers that cannot store 1e300 still
/// get something chartable; `infinity` is possible for astronomic values and is the provider's problem.
class IdleAnalytics {
  IdleAnalytics({Future<void> Function(AnalyticsEvent event)? sink})
    : _sink = sink ?? AnalyticsManager.instance.logEvent;

  final Future<void> Function(AnalyticsEvent event) _sink;

  /// Event name for a generator or upgrade bought with in-game currency (not a real-money purchase).
  static const purchaseEvent = 'idle_purchase';

  /// Event name for a prestige.
  static const prestigeEvent = 'idle_prestige';

  /// Event name for the player returning after being away long enough to earn something.
  static const offlineReturnEvent = 'idle_offline_return';

  void _log(String name, Map<String, dynamic> payload) =>
      _sink(AnalyticsEvent(name: name, payload: payload));

  /// A generator or upgrade [id] was bought: [count] units for [spent] (by resource).
  void purchase(String id, int count, Map<String, BigNumber> spent) =>
      _log(purchaseEvent, {
        'id': id,
        'count': count,
        'spent': {for (final e in spent.entries) e.key: e.value.toDouble()},
      });

  /// The player prestiged for [gain], their [prestigeCount]th time.
  void prestige(BigNumber gain, int prestigeCount) =>
      _log(prestigeEvent, {'gain': gain.toDouble(), 'count': prestigeCount});

  /// The player came back after [OfflineSummary.credit] away time and earned [OfflineSummary.gained].
  void offlineReturn(OfflineSummary summary) => _log(offlineReturnEvent, {
    'awaySeconds': summary.credit.away.inSeconds,
    'capped': summary.credit.capped,
    'gained': {
      for (final e in summary.gained.entries) e.key: e.value.toDouble(),
    },
  });
}
