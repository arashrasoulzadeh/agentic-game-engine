import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Shows one image file, at its own size, with pan and zoom so a large sprite sheet
/// can be inspected. The image is read from disk, so the file stays the source of
/// truth and nothing is copied into the project.
class ImageView extends StatelessWidget {
  final String filePath;

  const ImageView({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(p.basename(filePath), key: const Key('image-name')),
        ),
        Expanded(
          child: file.existsSync()
              ? InteractiveViewer(
                  minScale: 0.1,
                  maxScale: 8,
                  child: Center(
                    child: Image.file(
                      file,
                      key: const Key('image-view'),
                      errorBuilder: (context, error, stack) => const Text(
                        'This image could not be shown.',
                        key: Key('image-error'),
                      ),
                    ),
                  ),
                )
              : const Center(child: Text('That image no longer exists.')),
        ),
      ],
    );
  }
}
