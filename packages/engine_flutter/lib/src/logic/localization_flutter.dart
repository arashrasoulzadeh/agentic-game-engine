import 'dart:ui' as ui show TextAlign, TextDirection, TextStyle, Color, FontWeight, FontStyle;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// Flutter-specific localization integration.
/// Handles font loading, RTL layout, and text rendering with localization.
class LocalizationFlutter {
  static LocalizationManager get _manager => LocalizationManager.instance;

  /// Initialize with available locales from assets.
  static Future<void> initialize({
    List<String> supportedLocales = const ['en', 'es', 'fr', 'de', 'ja', 'ar', 'zh'],
    String? initialLocale,
  }) async {
    // Register common locales
    for (final code in supportedLocales) {
      final info = LocaleInfo.common[code];
      if (info != null) {
        LocalizationManager.instance.addLocale(info);
      }
    }

    // Load from assets if available
    // await _loadFromAssets(supportedLocales);

    if (initialLocale != null) {
      LocalizationManager.instance.setLocale(initialLocale);
    }
  }

  /// Get the current locale's font family.
  static String? get fontFamily => LocalizationManager.instance.currentLocaleInfo?.fontFamily;

  /// Whether current locale is RTL.
  static bool get isRTL => LocalizationManager.instance.isRTL;

  /// Get text direction for current locale.
  static ui.TextDirection get textDirection =>
      LocalizationManager.instance.isRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr;

  /// Get current locale code.
  static String get currentLocale => LocalizationManager.instance.currentLocale;

  /// Get available locale codes.
  static List<String> get availableLocales => LocalizationManager.instance.availableLocaleCodes;

  /// Set locale at runtime.
  static void setLocale(String localeCode) {
    LocalizationManager.instance.setLocale(localeCode);
  }

  /// Translate a key with optional args.
  static String tr(String key, [Map<String, dynamic>? args]) {
    return LocalizationManager.instance.tr(key, args: args);
  }

  /// Translate with pluralization.
  static String trPlural(String key, int count, [Map<String, dynamic>? args]) {
    return LocalizationManager.instance.trPlural(key, count, args: args);
  }

  /// Create a TextStyle with locale-appropriate font.
  static ui.TextStyle localeTextStyle({
    double fontSize = 16,
    ui.Color color = const ui.Color(0xFFFFFFFF),
    ui.FontWeight? fontWeight,
    ui.FontStyle? fontStyle,
  }) {
    final localeInfo = LocalizationManager.instance.currentLocaleInfo;
    return ui.TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );
  }

  /// Get RTL-aware text alignment.
  static ui.TextAlign rtlAwareAlign(ui.TextAlign align) {
    if (!isRTL) return align;
    switch (align) {
      case ui.TextAlign.left:
        return ui.TextAlign.right;
      case ui.TextAlign.right:
        return ui.TextAlign.left;
      case ui.TextAlign.start:
        return ui.TextAlign.end;
      case ui.TextAlign.end:
        return ui.TextAlign.start;
      default:
        return align;
    }
  }

  /// Get RTL-aware text direction for a specific locale.
  static ui.TextDirection textDirectionFor(String localeCode) {
    final info = LocaleInfo.common[localeCode];
    return info?.isRTL == true ? ui.TextDirection.rtl : ui.TextDirection.ltr;
  }

  /// Format a number for current locale.
  static String formatNumber(num number, {int? fractionDigits}) {
    return number.toStringAsFixed(fractionDigits ?? 0);
  }

  /// Format a date for current locale.
  static String formatDate(DateTime date, {String? format}) {
    return date.toIso8601String().split('T').first;
  }

  /// Format currency for current locale.
  static String formatCurrency(num amount, {String? currencyCode}) {
    return amount.toStringAsFixed(2);
  }

  /// Get plural category for a count in current locale.
  static String pluralCategory(int count) {
    if (count == 0) return 'zero';
    if (count == 1) return 'one';
    if (count == 2) return 'two';
    return 'other';
  }

  /// Load locale data from assets.
  static Future<void> _loadFromAssets(List<String> locales) async {
    // In a real implementation, load from assets/
    // For now, we just register the locale info
    for (final code in LocaleInfo.common.keys) {
      LocalizationManager.instance.addLocale(LocaleInfo.common[code]!);
    }
  }
}

/// Extension for easy translation on String.
extension LocalizedString on String {
  /// Translate this string using the current locale.
  String tr([Map<String, dynamic>? args]) {
    return LocalizationManager.instance.tr(this, args: args);
  }

  /// Translate with pluralization.
  String trPlural(int count, [Map<String, dynamic>? args]) {
    return LocalizationManager.instance.trPlural(this, count, args: args);
  }
}

/// Extension for RTL-aware widgets.
extension RTLWidgetExtension on Object {
  bool get isRTL => LocalizationFlutter.isRTL;

  ui.TextDirection get textDirection => LocalizationFlutter.textDirection;

  ui.TextAlign rtlAwareAlign(ui.TextAlign align) {
    if (!LocalizationFlutter.isRTL) return align;
    switch (align) {
      case ui.TextAlign.left:
        return ui.TextAlign.right;
      case ui.TextAlign.right:
        return ui.TextAlign.left;
      case ui.TextAlign.start:
        return ui.TextAlign.end;
      case ui.TextAlign.end:
        return ui.TextAlign.start;
      default:
        return align;
    }
  }
}

/// Mixin for RTL-aware widgets.
mixin RTLWidget {
  bool get isRTL => LocalizationFlutter.isRTL;

  ui.TextDirection get textDirection => LocalizationFlutter.textDirection;

  ui.TextAlign rtlAwareAlign(ui.TextAlign align) => LocalizationFlutter.rtlAwareAlign(align);

  ui.TextDirection get textDirectionForCurrentLocale => LocalizationFlutter.textDirection;
}