/// What an entity (usually the player) is carrying: item id -> count.
/// Plain data, mutated by `collectItem`/`dealPickupOnTouch` (see
/// `pickup_helpers.dart`) rather than a system — the same "helpers you
/// call explicitly, not hidden system behavior" approach `Health`'s
/// damage helpers take.
class Inventory {
  final Map<String, int> items;

  Inventory([Map<String, int>? items]) : items = items ?? <String, int>{};

  int count(String itemId) => items[itemId] ?? 0;
  bool has(String itemId, [int amount = 1]) => count(itemId) >= amount;

  Map<String, dynamic> toJson() => {'items': items};

  factory Inventory.fromJson(Map<String, dynamic> json) => Inventory(
        ((json['items'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ),
      );
}
