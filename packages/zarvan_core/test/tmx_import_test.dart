import 'dart:io' show GZipCodec, ZLibCodec;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

const _basicTmx = '''
<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" orientation="orthogonal" renderorder="right-down"
     width="3" height="2" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="tiles" tilewidth="16" tileheight="16" tilecount="3" columns="3">
  <image source="tiles.png" width="48" height="16"/>
  <tile id="0">
   <properties>
    <property name="solid" type="bool" value="true"/>
   </properties>
  </tile>
  <tile id="1">
   <properties>
    <property name="oneWay" type="bool" value="true"/>
   </properties>
  </tile>
  <tile id="2">
   <properties>
    <property name="slopeUpRight" type="bool" value="true"/>
   </properties>
  </tile>
 </tileset>
 <layer id="1" name="Tile Layer 1" width="3" height="2">
  <data encoding="csv">
1,1,3,
0,0,0
</data>
 </layer>
</map>
''';

void main() {
  test(
    'imports tile size, grid dimensions, and tile ids from an embedded-tileset TMX',
    () {
      final map = tileMapFromTmx(_basicTmx);

      expect(map.cols, 3);
      expect(map.rows, 2);
      expect(map.tileWidth, 16);
      expect(map.tileHeight, 16);
      expect(map.tileAt(0, 0), 1);
      expect(map.tileAt(1, 0), 1);
      expect(map.tileAt(2, 0), 3);
      expect(map.tileAt(0, 1), 0);
    },
  );

  test(
    'maps recognized bool tile properties onto the matching TileMap collision set',
    () {
      final map = tileMapFromTmx(_basicTmx);

      // firstgid=1, so tileset-local id 0/1/2 -> global gid 1/2/3.
      expect(map.solidTileIds, {1});
      expect(map.oneWayTileIds, {2});
      expect(map.slopeUpRightTileIds, {3});
      expect(map.slopeUpLeftTileIds, isEmpty);
    },
  );

  test('strips Tiled flip-flag bits from a gid, keeping the base tile id', () {
    // 0x80000000 (horizontal flip) | gid 1.
    final flippedTmx = _basicTmx.replaceFirst('1,1,3,', '2147483649,1,3,');
    final map = tileMapFromTmx(flippedTmx);

    expect(map.tileAt(0, 0), 1);
  });

  test('rejects a non-<map> root element', () {
    expect(() => tileMapFromTmx('<notamap></notamap>'), throwsUnsupportedError);
  });

  test('rejects an external tileset when no readTileset is given', () {
    const xml = '''
<map width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" source="tiles.tsx"/>
 <layer id="1" width="1" height="1"><data encoding="csv">1</data></layer>
</map>
''';
    expect(() => tileMapFromTmx(xml), throwsUnsupportedError);
  });

  test('several tilesets merge their collision properties by global id', () {
    const xml = '''
<map width="2" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="2" columns="2">
  <image source="a.png" width="32" height="16"/>
  <tile id="1"><properties><property name="solid" type="bool" value="true"/></properties></tile>
 </tileset>
 <tileset firstgid="3" name="b" tilewidth="16" tileheight="16" tilecount="2" columns="2">
  <image source="b.png" width="32" height="16"/>
  <tile id="0"><properties><property name="oneWay" type="bool" value="true"/></properties></tile>
 </tileset>
 <layer id="1" width="2" height="1"><data encoding="csv">2,3</data></layer>
</map>
''';
    final map = tileMapFromTmx(xml);
    expect(map.solidTileIds, {2});
    expect(map.oneWayTileIds, {3});
  });

  test(
    'an external tileset is read through readTileset, offset by firstgid',
    () {
      const tsx = '''
<tileset name="ext" tilewidth="16" tileheight="16" tilecount="2" columns="2">
 <image source="ext.png" width="32" height="16"/>
 <tile id="1"><properties><property name="solid" type="bool" value="true"/></properties></tile>
</tileset>
''';
      const xml = '''
<map width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="5" source="sub/ext.tsx"/>
 <layer id="1" width="1" height="1"><data encoding="csv">6</data></layer>
</map>
''';
      String? requested;
      final map = tileMapFromTmx(
        xml,
        readTileset: (source) {
          requested = source;
          return tsx;
        },
      );
      expect(requested, 'sub/ext.tsx');
      expect(map.solidTileIds, {6});
    },
  );

  test('an external tileset that cannot be read is an error naming it', () {
    const xml = '''
<map width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" source="gone.tsx"/>
 <layer id="1" width="1" height="1"><data encoding="csv">1</data></layer>
</map>
''';
    expect(
      () => tileMapFromTmx(xml, readTileset: (_) => null),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('gone.tsx'),
        ),
      ),
    );
  });

  test('zlib and gzip layer data import through decompress', () {
    String xmlFor(String compression, String data) =>
        '''
<map width="2" height="2" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="3" columns="3">
  <image source="a.png" width="48" height="16"/>
 </tileset>
 <layer id="1" width="2" height="2"><data encoding="base64" compression="$compression">$data</data></layer>
</map>
''';
    List<int> inflate(List<int> bytes, String compression) =>
        compression == 'gzip'
        ? GZipCodec().decode(bytes)
        : ZLibCodec().decode(bytes);
    for (final (compression, data) in [
      ('zlib', 'eJxjZGBgYGKAAGYgBgAARAAH'),
      ('gzip', 'H4sIAAAAAAAC/2NkYGBgYoAAZiAGALXrXbwQAAAA'),
    ]) {
      final map = tileMapFromTmx(
        xmlFor(compression, data),
        decompress: inflate,
      );
      expect(
        [
          map.tileAt(0, 0),
          map.tileAt(1, 0),
          map.tileAt(0, 1),
          map.tileAt(1, 1),
        ],
        [1, 2, 0, 3],
        reason: compression,
      );
    }
  });

  test('rejects more than one layer', () {
    const xml = '''
<map width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="1" columns="1">
  <image source="a.png" width="16" height="16"/>
 </tileset>
 <layer id="1" width="1" height="1"><data encoding="csv">1</data></layer>
 <layer id="2" width="1" height="1"><data encoding="csv">1</data></layer>
</map>
''';
    expect(() => tileMapFromTmx(xml), throwsUnsupportedError);
  });

  String twoLayers() => '''
<map width="2" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="2" columns="2">
  <image source="a.png" width="32" height="16"/>
  <tile id="0"><properties><property name="solid" type="bool" value="true"/></properties></tile>
 </tileset>
 <layer id="1" name="background" width="2" height="1"><data encoding="csv">2,2</data></layer>
 <layer id="2" name="ground" width="2" height="1"><data encoding="csv">1,0</data></layer>
</map>
''';

  test('layer: picks the named layer from a multi-layer map', () {
    final map = tileMapFromTmx(twoLayers(), layer: 'ground');
    expect([map.tileAt(0, 0), map.tileAt(1, 0)], [1, 0]);
    expect(map.solidTileIds, {1});
  });

  test('several layers without layer: fails and lists the names', () {
    expect(
      () => tileMapFromTmx(twoLayers()),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          allOf(contains('background'), contains('ground')),
        ),
      ),
    );
  });

  test('an unknown layer name lists the real ones', () {
    expect(
      () => tileMapFromTmx(twoLayers(), layer: 'grund'),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('Layers: background, ground'),
        ),
      ),
    );
  });

  test(
    'uncompressed base64 layer data imports (little-endian uint32 tiles)',
    () {
      // gids 1, 0, 2 -> 01000000 00000000 02000000
      const xml = '''
<map width="3" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="2" columns="2">
  <image source="a.png" width="32" height="16"/>
 </tileset>
 <layer id="1" width="3" height="1"><data encoding="base64">AQAAAAAAAAACAAAA</data></layer>
</map>
''';
      final map = tileMapFromTmx(xml);
      expect([for (var c = 0; c < 3; c++) map.tileAt(c, 0)], [1, 0, 2]);
    },
  );

  test('base64 flip bits in the top of the uint32 are stripped', () {
    // 0x80000001: horizontal flip of gid 1 -> 01 00 00 80
    const xml = '''
<map width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="1" columns="1">
  <image source="a.png" width="16" height="16"/>
 </tileset>
 <layer id="1" width="1" height="1"><data encoding="base64">AQAAgA==</data></layer>
</map>
''';
    expect(tileMapFromTmx(xml).tileAt(0, 0), 1);
  });

  test(
    'compressed base64 without decompress is rejected, naming the setting to change',
    () {
      const xml = '''
<map width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="1" columns="1">
  <image source="a.png" width="16" height="16"/>
 </tileset>
 <layer id="1" width="1" height="1"><data encoding="base64" compression="zlib">eJxjYAAAAAYAAQ==</data></layer>
</map>
''';
      expect(
        () => tileMapFromTmx(xml),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('zlib'),
              contains('decompress'),
              contains('Base64 (uncompressed)'),
            ),
          ),
        ),
      );
    },
  );

  test('rejects uncompressed XML tile elements (no encoding)', () {
    const xml = '''
<map width="1" height="1" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="1" columns="1">
  <image source="a.png" width="16" height="16"/>
 </tileset>
 <layer id="1" width="1" height="1"><data><tile gid="1"/></data></layer>
</map>
''';
    expect(() => tileMapFromTmx(xml), throwsUnsupportedError);
  });

  test('rejects layer data whose tile count does not match width*height', () {
    const xml = '''
<map width="2" height="2" tilewidth="16" tileheight="16">
 <tileset firstgid="1" name="a" tilewidth="16" tileheight="16" tilecount="1" columns="1">
  <image source="a.png" width="16" height="16"/>
 </tileset>
 <layer id="1" width="2" height="2"><data encoding="csv">1,1,1</data></layer>
</map>
''';
    expect(() => tileMapFromTmx(xml), throwsUnsupportedError);
  });
}
