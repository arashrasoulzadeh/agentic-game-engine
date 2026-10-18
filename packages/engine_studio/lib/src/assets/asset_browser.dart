import 'package:flutter/material.dart';

import 'asset_index.dart';

/// The project's art, sound and data in one list: sprite sheets (with how many sprites
/// each holds), other images, audio, data files and prefabs. Tapping a sprite sheet
/// shows its sprites; tapping any other file opens it.
class AssetBrowserPanel extends StatelessWidget {
  final AssetIndex index;
  final ValueChanged<AtlasInfo> onOpenAtlas;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onClose;

  const AssetBrowserPanel({
    super.key,
    required this.index,
    required this.onOpenAtlas,
    required this.onOpenFile,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <(String, List<Widget>)>[
      (
        'Sprite sheets',
        [
          for (final a in index.atlases)
            ListTile(
              key: Key('asset-atlas-${a.id}'),
              dense: true,
              leading: const Icon(Icons.grid_view, size: 18),
              title: Text(a.id),
              subtitle: Text(
                '${a.regions.length} sprites${a.declared ? '' : ' · not declared'}',
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onOpenAtlas(a),
            ),
        ],
      ),
      ('Images', _files(index.images, Icons.image_outlined)),
      ('Audio', _files(index.audio, Icons.audiotrack_outlined)),
      ('Data', _files(index.data, Icons.data_object)),
      ('Prefabs', _files(index.prefabs, Icons.widgets_outlined)),
    ];
    final total = sections.fold<int>(0, (n, s) => n + s.$2.length);
    return Column(
      key: const Key('asset-browser'),
      children: [
        ListTile(
          dense: true,
          title: Text(
            total == 0 ? 'No assets yet' : 'Assets ($total)',
            key: const Key('asset-summary'),
          ),
          trailing: IconButton(
            key: const Key('asset-browser-close'),
            tooltip: 'Close',
            iconSize: 16,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final (title, tiles) in sections)
                if (tiles.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  ...tiles,
                ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _files(List<String> paths, IconData icon) => [
    for (final path in paths)
      ListTile(
        key: Key('asset-file-$path'),
        dense: true,
        leading: Icon(icon, size: 18),
        title: Text(path, overflow: TextOverflow.ellipsis),
        onTap: () => onOpenFile(path),
      ),
  ];
}
