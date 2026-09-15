/// Optional rectangular hit area for a `Button` entity, centered on its
/// `Position` — an alternative to the circular `Collider`-based area
/// `hitTestButton` checks by default. A wide/short button (an ornate
/// bar, a long nameplate) fits a rectangle far better than a circle,
/// which either leaves dead corners (sized to the short axis) or
/// extends tappable area past the visible art on the long axis (sized
/// to the diagonal). `hitTestButton` checks this first when present,
/// falling back to `Collider` otherwise — existing menus (circular
/// `Collider`-only, no `ButtonHitBox`) are completely unaffected.
class ButtonHitBox {
  double width;
  double height;

  ButtonHitBox(this.width, this.height);

  Map<String, dynamic> toJson() => {'width': width, 'height': height};

  factory ButtonHitBox.fromJson(Map<String, dynamic> json) => ButtonHitBox(
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
      );
}
