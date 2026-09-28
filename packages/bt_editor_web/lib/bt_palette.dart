import 'package:flutter/material.dart';
import 'bt_nodes.dart';

typedef OnNodeTypeSelected = void Function(BTNodeType type);

class BTPalettePanel extends StatelessWidget {
  final OnNodeTypeSelected onNodeSelected;

  const BTPalettePanel({
    super.key,
    required this.onNodeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final categories = _groupByCategory();
    
    return Container(
      width: 280,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Node Palette',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: categories.entries.map((entry) {
                return _CategorySection(
                  category: entry.key,
                  types: entry.value,
                  onNodeSelected: onNodeSelected,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<BTNodeType>> _groupByCategory() {
    final map = <String, List<BTNodeType>>{};
    for (final type in BTNodeType.values) {
      map.putIfAbsent(type.category, () => []).add(type);
    }
    return map;
  }
}

class _CategorySection extends StatelessWidget {
  final String category;
  final List<BTNodeType> types;
  final OnNodeTypeSelected onNodeSelected;

  const _CategorySection({
    required this.category,
    required this.types,
    required this.onNodeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            category.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...types.map((type) => _PaletteItem(
              type: type,
              onTap: () => onNodeSelected(type),
            )),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PaletteItem extends StatelessWidget {
  final BTNodeType type;
  final VoidCallback onTap;

  const _PaletteItem({
    required this.type,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: type.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: type.color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  type.icon,
                  color: type.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  type.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}