import 'asset_hot_reload.dart';

/// Web has no filesystem to poll, so there is no source to return.
AssetSource? directoryAssetSource(String path) => null;
