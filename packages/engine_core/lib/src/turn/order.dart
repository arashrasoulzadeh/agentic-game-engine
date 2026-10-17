/// Integer tile coordinates for grid-based games. Separate from
/// `Position` (world-space doubles) because turn-based rules reason in
/// whole cells -- ranges, occupancy, costs -- and mixing the two
/// invites off-by-half-cell bugs.
class GridPosition {
  int col;
  int row;
  GridPosition(this.col, this.row);

  /// Chebyshev distance: cells apart when diagonal steps count as one.
  int chebyshev(GridPosition o) =>
      (col - o.col).abs() > (row - o.row).abs() ? (col - o.col).abs() : (row - o.row).abs();

  Map<String, dynamic> toJson() => {'col': col, 'row': row};
  factory GridPosition.fromJson(Map<String, dynamic> json) =>
      GridPosition((json['col'] as num).toInt(), (json['row'] as num).toInt());
}

/// An intent an entity carries out over one or more turns. Orders are
/// plain JSON so a human UI and an AI agent submit them through the
/// exact same path.
abstract class Order {
  const Order();

  /// Discriminator used in JSON and to look up the executing handler.
  String get type;

  Map<String, dynamic> toJson();

  factory Order.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'move':
        return MoveOrder((json['col'] as num).toInt(), (json['row'] as num).toInt());
      case 'attack':
        return AttackOrder((json['target'] as num).toInt());
      default:
        throw FormatException('Unknown order type: ${json['type']}');
    }
  }
}

/// Walk to a destination cell, spending action points per step.
class MoveOrder extends Order {
  final int col;
  final int row;
  const MoveOrder(this.col, this.row);

  @override
  String get type => 'move';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'col': col, 'row': row};
}

/// Attack another entity by id.
class AttackOrder extends Order {
  final int target;
  const AttackOrder(this.target);

  @override
  String get type => 'attack';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'target': target};
}

/// Pending orders for one entity, executed front to back. An order that
/// can't be afforded this turn stays at the front and resumes next turn.
class OrderQueue {
  final List<Order> orders;
  OrderQueue([List<Order>? orders]) : orders = orders ?? [];

  Map<String, dynamic> toJson() => {'orders': [for (final o in orders) o.toJson()]};
  factory OrderQueue.fromJson(Map<String, dynamic> json) => OrderQueue([
        for (final o in (json['orders'] as List? ?? const []))
          Order.fromJson((o as Map).cast<String, dynamic>()),
      ]);
}

/// Why an order was dropped.
enum OrderFailure { blocked, outOfRange, invalidTarget }

/// Emitted when an order is dropped without completing.
class OrderFailedEvent {
  final int entity;
  final Order order;
  final OrderFailure reason;
  OrderFailedEvent(this.entity, this.order, this.reason);
}

/// Emitted when an entity steps into a new cell.
class MovedEvent {
  final int entity;
  final int col;
  final int row;
  MovedEvent(this.entity, this.col, this.row);
}

/// Emitted when an attack order resolves. Damage is applied by whatever
/// listens (phase 5), keeping order execution independent of any health
/// model.
class AttackResolvedEvent {
  final int attacker;
  final int target;
  AttackResolvedEvent(this.attacker, this.target);
}
