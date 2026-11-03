# Build-time asset optimisation

Image conversion and atlas packing happen **during the build**. Nobody runs
them by hand, and your source art is never modified.

## PNG to lossless WebP

`zarvan_cli` is a Flutter [asset transformer](https://docs.flutter.dev/ui/assets/asset-transformation).
Add it to the assets you want shrunk:

```yaml
dev_dependencies:
  zarvan_cli: ...        # same dependency as the CLI

flutter:
  assets:
    - path: assets/art/
      transformers:
        - package: zarvan_cli
```

Every `.png` in that entry is re-encoded as lossless WebP while Flutter bundles
the app. The asset keeps its `.png` name: Flutter detects the image format from
the bytes, so no code or manifest changes. A file is left as-is when it is not a
PNG, when `cwebp` is not installed, or when WebP would not be smaller, so the
step never fails a build or makes it bigger. Install the encoder with
`brew install webp` or `apt install webp`.

Every conversion is checked before it is kept: the WebP is decoded and compared
with the PNG pixel by pixel, and if anything visible differs the original PNG is
used instead. 8-bit PNGs must match exactly (the hidden colour of fully
transparent pixels aside); 16-bit PNGs are compared at 8 bits, which is what
Flutter decodes them to and all WebP can hold. Encoding uses cwebp's maximum
lossless effort (`-z 9`).

Projects made with `zarvan create` already have the transformer on
`assets/images/`; drop PNGs there.

Measured on mobarez: 124 PNG assets became WebP and the release APK went from
24.4 MB to 21.3 MB, with identical rendering on a phone.

## Sprite atlas packing

Add the source folder to `assets/game_config.json`:

```json
{
  "packedAtlasId": "art",
  "packedAtlasSource": "art",
  "packedAtlasImage": "assets/packed/atlas.png",
  "packedAtlasManifest": "assets/packed/atlas.json"
}
```

`zarvan build-release` then runs `zarvan pack-assets` on `art/` before building
(`--dry-run` only reports it). `packedAtlasSource` is ignored at runtime.
Plain `flutter run` does not pack; use `zarvan pack-assets` or `build-release`
when the art changes.
