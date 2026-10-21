import 'package:flutter/widgets.dart';

/// The 4x5 colour matrix (the shape `ColorFilter.matrix` takes) that shows a scene as a person with the
/// given colour-vision deficiency sees it, or null for `"none"` and any unknown mode.
///
/// `protanopia` (no red cones), `deuteranopia` (no green) and `tritanopia` (no blue) use the widely
/// used RGB approximations of full dichromacy. It is a simulation to help developers and players check
/// that colour is not the only carrier of information, not a medical model.
List<double>? colorblindMatrix(String mode) {
  switch (mode) {
    case 'protanopia':
      return _rows(0.567, 0.433, 0, 0.558, 0.442, 0, 0, 0.242, 0.758);
    case 'deuteranopia':
      return _rows(0.625, 0.375, 0, 0.7, 0.3, 0, 0, 0.3, 0.7);
    case 'tritanopia':
      return _rows(0.95, 0.05, 0, 0, 0.433, 0.567, 0, 0.475, 0.525);
  }
  return null;
}

List<double> _rows(
  double rr,
  double rg,
  double rb,
  double gr,
  double gg,
  double gb,
  double br,
  double bg,
  double bb,
) => [rr, rg, rb, 0, 0, gr, gg, gb, 0, 0, br, bg, bb, 0, 0, 0, 0, 0, 1, 0];

/// [child] seen through [mode]'s colour-vision simulation; [child] itself for `"none"`.
Widget colorblindFiltered(String mode, Widget child) {
  final m = colorblindMatrix(mode);
  return m == null
      ? child
      : ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
}
