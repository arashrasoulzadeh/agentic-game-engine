/// A polling [AssetSource] over a directory on disk, picked at compile time via
/// `dart.library.io` -- the same idiom as `debug_memory.dart`, so this package
/// still compiles for web, where there is no filesystem.
export 'directory_asset_source_stub.dart'
    if (dart.library.io) 'directory_asset_source_io.dart';
