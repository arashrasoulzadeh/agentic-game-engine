// The day/night samples in docs/concepts/lighting.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('noon is bright, midnight dark, and the hour wraps around the day', () {
    final noon = DayNightCycle(hour: 12);
    final midnight = DayNightCycle(hour: 0);
    expect(noon.ambientBrightness, greaterThan(midnight.ambientBrightness));
    expect(noon.ambientBrightness, closeTo(1.0, 0.01));
    expect(midnight.ambientBrightness, lessThan(0.5));

    final late = DayNightCycle(hour: 23.5, dayLengthSeconds: 24); // 1 s per game hour
    late.advance(1.0);
    expect(late.hour, closeTo(0.5, 1e-9), reason: 'wrapped past midnight');
  });

  test('weather dims the ambient light, scaled by its intensity', () {
    final clear = DayNightCycle(hour: 12);
    final rain = DayNightCycle(hour: 12, weather: Weather.rain);
    final drizzle = DayNightCycle(hour: 12, weather: Weather.rain, weatherIntensity: 0.5);
    expect(rain.ambientBrightness, lessThan(clear.ambientBrightness));
    expect(drizzle.ambientBrightness, inExclusiveRange(rain.ambientBrightness, clear.ambientBrightness));
  });

  test('a zero-length day never advances (a frozen clock)', () {
    final frozen = DayNightCycle(hour: 6, dayLengthSeconds: 0);
    frozen.advance(100);
    expect(frozen.hour, 6);
  });

  test('the ambient colour is a packed ARGB int that changes through the day', () {
    final dawn = DayNightCycle(hour: 6).ambientColorArgb;
    final noon = DayNightCycle(hour: 12).ambientColorArgb;
    expect(dawn, isNot(noon));
    expect(noon >>> 24, 0xFF, reason: 'opaque');
  });
}
