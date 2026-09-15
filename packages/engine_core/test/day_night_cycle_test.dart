import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('DayNightCycle.advance', () {
    test('defaults to noon, full daylight', () {
      final cycle = DayNightCycle();
      expect(cycle.hour, 12);
      expect(cycle.ambientBrightness, 1.0);
    });

    test('advances hour proportionally to dt/dayLengthSeconds', () {
      final cycle = DayNightCycle(hour: 0, dayLengthSeconds: 240);
      cycle.advance(60); // a quarter of a 240s day -> 6 hours
      expect(cycle.hour, closeTo(6, 0.001));
    });

    test('wraps at 24 back to 0', () {
      final cycle = DayNightCycle(hour: 23, dayLengthSeconds: 24);
      cycle.advance(2); // 2/24 of a day -> +2 hours -> 25 -> wraps to 1
      expect(cycle.hour, closeTo(1, 0.001));
    });

    test('dayLengthSeconds of 0 freezes the clock', () {
      final cycle = DayNightCycle(hour: 10, dayLengthSeconds: 0);
      cycle.advance(1000);
      expect(cycle.hour, 10);
    });
  });

  group('DayNightCycle.timeOfDayBrightness/ambientBrightness', () {
    test('deep night sits at a dim floor, not pure black', () {
      final cycle = DayNightCycle(hour: 2);
      expect(cycle.timeOfDayBrightness, 0.18);
    });

    test('midday is fully bright', () {
      final cycle = DayNightCycle(hour: 12);
      expect(cycle.timeOfDayBrightness, 1.0);
    });

    test('dawn ramps smoothly between the night floor and day plateau', () {
      final beforeDawn = DayNightCycle(hour: 5).timeOfDayBrightness;
      final midDawn = DayNightCycle(hour: 6.5).timeOfDayBrightness;
      final afterDawn = DayNightCycle(hour: 8).timeOfDayBrightness;
      expect(beforeDawn, 0.18);
      expect(afterDawn, 1.0);
      expect(midDawn, greaterThan(beforeDawn));
      expect(midDawn, lessThan(afterDawn));
    });

    test('dusk ramps smoothly from the day plateau back to the night floor', () {
      final beforeDusk = DayNightCycle(hour: 18).timeOfDayBrightness;
      final midDusk = DayNightCycle(hour: 20).timeOfDayBrightness;
      final afterDusk = DayNightCycle(hour: 22).timeOfDayBrightness;
      expect(beforeDusk, 1.0);
      expect(afterDusk, closeTo(0.18, 0.001));
      expect(midDusk, lessThan(beforeDusk));
      expect(midDusk, greaterThan(afterDusk));
    });

    test('clear weather at weatherIntensity 1 does not dim beyond time of day', () {
      final cycle = DayNightCycle(hour: 12, weather: Weather.clear, weatherIntensity: 1);
      expect(cycle.ambientBrightness, cycle.timeOfDayBrightness);
    });

    test('rain dims the scene proportional to weatherIntensity', () {
      final noRain = DayNightCycle(hour: 12, weather: Weather.rain, weatherIntensity: 0);
      final fullRain = DayNightCycle(hour: 12, weather: Weather.rain, weatherIntensity: 1);
      final halfRain = DayNightCycle(hour: 12, weather: Weather.rain, weatherIntensity: 0.5);
      expect(noRain.ambientBrightness, 1.0);
      expect(fullRain.ambientBrightness, closeTo(0.5, 0.001));
      expect(halfRain.ambientBrightness, closeTo(0.75, 0.001));
    });

    test('overcast and fog each dim less than rain at full intensity', () {
      final rain =
          DayNightCycle(hour: 12, weather: Weather.rain, weatherIntensity: 1).ambientBrightness;
      final overcast = DayNightCycle(hour: 12, weather: Weather.overcast, weatherIntensity: 1)
          .ambientBrightness;
      final fog =
          DayNightCycle(hour: 12, weather: Weather.fog, weatherIntensity: 1).ambientBrightness;
      expect(rain, lessThan(overcast));
      expect(overcast, lessThan(fog));
      expect(fog, lessThan(1.0));
    });
  });

  group('DayNightCycle.ambientColorArgb', () {
    int alpha(int argb) => (argb >> 24) & 0xFF;
    int red(int argb) => (argb >> 16) & 0xFF;
    int green(int argb) => (argb >> 8) & 0xFF;
    int blue(int argb) => argb & 0xFF;

    test('midday has no tint (pure white, fully opaque)', () {
      final color = DayNightCycle(hour: 12).ambientColorArgb;
      expect(color, 0xFFFFFFFF);
    });

    test('deep night is a dark, blue-leaning tint', () {
      final color = DayNightCycle(hour: 2).ambientColorArgb;
      expect(alpha(color), 255);
      expect(blue(color), greaterThan(red(color)));
      expect(red(color), lessThan(100), reason: 'night should read as dark, not washed out');
    });

    test('dawn is warm (red/orange channel dominant over blue)', () {
      final color = DayNightCycle(hour: 6.5).ambientColorArgb;
      expect(red(color), greaterThan(blue(color)));
    });

    test('fog blends the time-of-day tint toward light grey', () {
      final clearNight = DayNightCycle(hour: 2, weather: Weather.clear).ambientColorArgb;
      final foggyNight =
          DayNightCycle(hour: 2, weather: Weather.fog, weatherIntensity: 1).ambientColorArgb;
      // Fog should brighten/desaturate the deep-night blue toward grey --
      // every channel should end up closer together (less blue-dominant)
      // and generally lighter than the unfogged night tint.
      expect(red(foggyNight), greaterThan(red(clearNight)));
      expect(green(foggyNight), greaterThan(green(clearNight)));
    });

    test('weatherIntensity 0 leaves the time-of-day color untouched regardless of weather', () {
      final clear = DayNightCycle(hour: 6.5, weather: Weather.clear).ambientColorArgb;
      final rainAtZero =
          DayNightCycle(hour: 6.5, weather: Weather.rain, weatherIntensity: 0).ambientColorArgb;
      expect(rainAtZero, clear);
    });

    test(
        'color magnitude tracks timeOfDayBrightness, not just how far through the hue '
        'ramp the hour is -- regression test for a real bug where the color and '
        'brightness curves desynced', () {
      // Hour 19 sits only halfway through the 18-22 *color* ramp
      // (roughly 50% of the way from white to the dusk hue) while
      // timeOfDayBrightness there is already well past its own halfway
      // point (~0.8 -> ~0.2 of the way *down* from 1.0). Before this was
      // fixed, ambientColorArgb returned that still-bright ~50% hue
      // untouched, so a caller compositing it at the alpha
      // (1 - brightness) implies would show a brighter-than-expected
      // wash for how dark this hour actually is. Now the color itself
      // is scaled toward black by timeOfDayBrightness, so its magnitude
      // can never exceed "how lit this hour already is".
      final cycle = DayNightCycle(hour: 19);
      final color = cycle.ambientColorArgb;
      final maxChannel = [
        (color >> 16) & 0xFF,
        (color >> 8) & 0xFF,
        color & 0xFF,
      ].reduce((a, b) => a > b ? a : b);
      expect(maxChannel / 255, lessThanOrEqualTo(cycle.timeOfDayBrightness + 0.01),
          reason: 'no channel of the tint should read brighter than timeOfDayBrightness '
              'itself -- that is the whole point of scaling the hue by it');
    });
  });
}
