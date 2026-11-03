import 'dart:typed_data';

import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('LoadingProgress', () {
    test('only moves forward and clamps', () {
      final p = LoadingProgress();
      p.report(0.5, 'half');
      p.report(0.2, 'back');
      expect(p.fraction, 0.5);
      expect(p.label, 'half');
      p.report(3, 'done');
      expect(p.fraction, 1);
    });

    test('notifies listeners on advance', () {
      final p = LoadingProgress();
      var n = 0;
      p.addListener(() => n++);
      p.report(0.3, 'a');
      p.report(0.1, 'ignored');
      expect(n, 1);
    });
  });

  testWidgets('SplashScreen shows title, stage label, progress and footer', (
    tester,
  ) async {
    final progress = LoadingProgress()..report(0.4, 'Loading assets');
    await tester.pumpWidget(
      _host(
        SplashScreen(
          config: const SplashConfig(title: 'My Game'),
          progress: progress,
          footer: 'ZARVAN engine · abc1234',
        ),
      ),
    );
    expect(find.text('My Game'), findsOneWidget);
    expect(find.text('Loading assets'), findsOneWidget);
    expect(find.text('ZARVAN engine · abc1234'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.4);

    progress.report(0.9, 'Almost');
    await tester.pump();
    expect(find.text('Almost'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.9,
    );
  });

  testWidgets('showEngineVersion: false hides the footer', (tester) async {
    await tester.pumpWidget(
      _host(
        SplashScreen(
          config: const SplashConfig(showEngineVersion: false),
          progress: LoadingProgress(),
        ),
      ),
    );
    expect(find.textContaining('ZARVAN engine'), findsNothing);
  });

  test('footerFor falls back to dev without a commit', () {
    expect(SplashScreen.footerFor(''), 'ZARVAN engine · dev');
    expect(
      SplashScreen.footerFor('v0.1.0-3-gabc'),
      'ZARVAN engine · v0.1.0-3-gabc',
    );
  });

  testWidgets('a custom logo replaces the bundled one', (tester) async {
    final logo = MemoryImage(_pixel);
    await tester.pumpWidget(
      _host(
        SplashScreen(
          config: SplashConfig(logo: logo),
          progress: LoadingProgress(),
        ),
      ),
    );
    expect(tester.widget<Image>(find.byType(Image)).image, same(logo));
  });
}

final _pixel = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0xf8,
  0xff,
  0xff,
  0x3f,
  0x00,
  0x05,
  0xfe,
  0x02,
  0xfe,
  0xa7,
  0x35,
  0x81,
  0x84,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);
