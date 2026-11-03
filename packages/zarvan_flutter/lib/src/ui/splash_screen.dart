import 'package:flutter/material.dart';

/// The engine build this game was compiled against, injected at build time
/// with `--dart-define=ZARVAN_COMMIT=<git describe>` (`zarvan build-release`
/// does it for you). Empty when the build did not pass one, which the
/// splash shows as `dev`.
const String kEngineCommit = String.fromEnvironment('ZARVAN_COMMIT');

/// How far the initial scene's load has got, for the splash screen.
///
/// The runner reports stages as it loads (`GameRunner` owns the numbers);
/// a game never has to. Fractions only move forward so a late, slow stage
/// cannot make the bar jump back.
class LoadingProgress extends ChangeNotifier {
  double _fraction = 0;
  String _label = '';

  /// Loaded share in `0.0..1.0`.
  double get fraction => _fraction;

  /// Short human text for the current stage, e.g. `Loading assets`.
  String get label => _label;

  /// Records a stage. [fraction] is clamped and never lowers the bar.
  void report(double fraction, String label) {
    final next = fraction.clamp(0.0, 1.0);
    if (next < _fraction) return;
    _fraction = next;
    _label = label;
    notifyListeners();
  }
}

/// What the splash screen shows. Every field has an engine default, so a
/// game only sets what it wants to change: usually [logo] and [title].
@immutable
class SplashConfig {
  /// The logo. Null shows the bundled ZARVAN logo.
  final ImageProvider? logo;

  /// Logo edge length in logical pixels (the logo is square-fitted).
  final double logoSize;

  /// Game name under the logo. Null shows nothing.
  final String? title;

  /// Splash background. Null uses `GameConfig.backgroundColor`.
  final Color? backgroundColor;

  /// Progress bar and label accent colour.
  final Color accentColor;

  /// Whether the footer shows the engine commit this build used.
  final bool showEngineVersion;

  /// Keeps the splash up at least this long, so a fast load does not flash
  /// it. Applies to the first scene only.
  final Duration minDuration;

  const SplashConfig({
    this.logo,
    this.logoSize = 160,
    this.title,
    this.backgroundColor,
    this.accentColor = const Color(0xFFC8A66A),
    this.showEngineVersion = true,
    this.minDuration = Duration.zero,
  });
}

/// The loading screen every game gets by default: logo, optional title, a
/// progress bar fed by [LoadingProgress], and the engine commit at the
/// bottom. Replace the artwork through [SplashConfig]; override
/// `Game.buildLoadingScreen` to replace the whole screen.
class SplashScreen extends StatelessWidget {
  final SplashConfig config;
  final LoadingProgress progress;

  /// Text for the footer; defaults to `ZARVAN engine · <commit>`.
  final String? footer;

  const SplashScreen({
    super.key,
    required this.config,
    required this.progress,
    this.footer,
  });

  static const _logoAsset = AssetImage(
    'assets/branding/zarvan_logo.png',
    package: 'zarvan_flutter',
  );

  /// Footer text for [commit] (`dev` when empty).
  static String footerFor(String commit) =>
      'ZARVAN engine · ${commit.isEmpty ? 'dev' : commit}';

  @override
  Widget build(BuildContext context) {
    final text = const TextStyle(
      color: Color(0xFFD8D2C4),
      fontSize: 13,
      decoration: TextDecoration.none,
      fontWeight: FontWeight.normal,
    );
    return ColoredBox(
      color: config.backgroundColor ?? const Color(0xFF101216),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image(
                        image: config.logo ?? _logoAsset,
                        width: config.logoSize,
                        height: config.logoSize,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            SizedBox(height: config.logoSize),
                      ),
                      if (config.title != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          config.title!,
                          textAlign: TextAlign.center,
                          style: text.copyWith(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      ListenableBuilder(
                        listenable: progress,
                        builder: (_, _) => Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress.fraction,
                                minHeight: 6,
                                color: config.accentColor,
                                backgroundColor: const Color(0x33FFFFFF),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(progress.label, style: text),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (config.showEngineVersion)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  footer ?? footerFor(kEngineCommit),
                  style: text.copyWith(fontSize: 11, color: config.accentColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
