/// Which enemy is up next: [wave] in order, then [boss].
class WaveProgress {
  WaveProgress({required this.wave, required this.boss});

  final List<String> wave;
  final String boss;
  int index = 0;

  bool get isBoss => index >= wave.length;
  String get currentId => isBoss ? boss : wave[index];

  /// HUD caption for the current encounter.
  String get label =>
      isBoss ? 'Boss — Kakuy' : 'Wave ${index + 1}/${wave.length}';

  void advance() => index++;
}
