/// What `build-release` will do, worked out without touching the disk or running anything, so the
/// exact commands and files can be tested.
class ReleasePlan {
  ReleasePlan({
    this.command = const [],
    this.writes = const {},
    this.errors = const [],
    this.warnings = const [],
  });

  /// The `flutter` command line (empty when there are errors).
  final List<String> command;

  /// Files to create before the build, project-relative path -> content. Removed again afterwards,
  /// since they can hold secrets.
  final Map<String, String> writes;
  final List<String> errors;
  final List<String> warnings;

  bool get ok => errors.isEmpty;
}

/// Flutter has no `--keystore` flag. Android release signing is read by Gradle from
/// `android/key.properties`; the project's `android/app/build.gradle(.kts)` must say so once.
const androidSigningSnippet = '''
// android/app/build.gradle.kts - above `android { ... }`:
import java.util.Properties
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}

// ... and inside `android { ... }`:
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String?
        keyPassword = keystoreProperties["keyPassword"] as String?
        storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
        storePassword = keystoreProperties["storePassword"] as String?
    }
}
buildTypes {
    release { signingConfig = signingConfigs.getByName("release") }
}''';

/// The `flutter build appbundle` plan.
///
/// With a complete keystore (path, store password, alias, key password) it writes
/// `android/key.properties` and requires that the project's Gradle file already reads it;
/// otherwise Flutter would silently sign with the **debug** key, which Google Play rejects.
/// Without a keystore the build proceeds and the warning says exactly that.
ReleasePlan planAndroid({
  required String target,
  required String buildName,
  required String buildNumber,
  String? flavor,
  String? keystorePath,
  String? keystorePassword,
  String? keyAlias,
  String? keyPassword,
  bool splitPerAbi = false,
  bool verbose = false,
  bool keystoreExists = true,
  String? gradleText,
}) {
  final command = [
    'flutter',
    'build',
    'appbundle',
    '--target=$target',
    '--build-name=$buildName',
    '--build-number=$buildNumber',
    '--release',
    if (flavor != null) '--flavor=$flavor',
    if (splitPerAbi) '--split-per-abi',
    if (verbose) '-v',
  ];
  final given = [keystorePath, keystorePassword, keyAlias, keyPassword];
  final any = given.any((v) => v != null);
  final all = given.every((v) => v != null);
  if (!any) {
    return ReleasePlan(
      command: command,
      warnings: const [
        'No keystore given: Flutter signs the bundle with the DEBUG key, which Google Play will reject. '
            'Pass --keystore-path, --keystore-password, --key-alias and --key-password.',
      ],
    );
  }
  if (!all) {
    return ReleasePlan(
      errors: const [
        'Android signing needs all of --keystore-path, --keystore-password, --key-alias and --key-password.',
      ],
    );
  }
  if (!keystoreExists) {
    return ReleasePlan(errors: ['Keystore file not found at $keystorePath']);
  }
  if (gradleText == null || !gradleText.contains('key.properties')) {
    return ReleasePlan(
      errors: [
        'android/app/build.gradle(.kts) does not read android/key.properties, so Flutter would ignore the keystore. '
            'Add this once, then re-run:\n$androidSigningSnippet',
      ],
    );
  }
  return ReleasePlan(
    command: command,
    writes: {
      'android/key.properties':
          'storePassword=$keystorePassword\n'
          'keyPassword=$keyPassword\n'
          'keyAlias=$keyAlias\n'
          'storeFile=$keystorePath\n',
    },
  );
}

/// An ExportOptions.plist for App Store export with Xcode-managed (automatic) signing under [teamId].
String automaticExportOptions(String teamId) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>$teamId</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
''';

/// The `flutter build ipa` plan.
///
/// `flutter build ipa` has no `--team-id`, `--provisioning-profile` or `--codesign-identity`
/// flags: signing is the Xcode project's, and export is described by an ExportOptions.plist. So
/// `--team-id` alone generates an automatic-signing plist; manual signing (a specific profile or
/// identity) needs your own `--export-options-plist`, and passing those flags without one is an
/// error rather than being silently ignored.
ReleasePlan planIos({
  required String target,
  required String buildName,
  required String buildNumber,
  String? flavor,
  String? teamId,
  String? provisioningProfile,
  String? codesignIdentity,
  String? exportOptionsPlist,
  bool noCodesign = false,
  bool verbose = false,
}) {
  final base = [
    'flutter',
    'build',
    'ipa',
    '--target=$target',
    '--build-name=$buildName',
    '--build-number=$buildNumber',
    '--release',
    if (flavor != null) '--flavor=$flavor',
    if (verbose) '-v',
  ];
  if (noCodesign) {
    return ReleasePlan(command: [...base, '--no-codesign']);
  }
  if (exportOptionsPlist != null) {
    return ReleasePlan(
      command: [...base, '--export-options-plist=$exportOptionsPlist'],
      warnings: [
        if (teamId != null ||
            provisioningProfile != null ||
            codesignIdentity != null)
          '--team-id/--provisioning-profile/--codesign-identity are ignored when --export-options-plist is given; '
              'put them in the plist.',
      ],
    );
  }
  if (provisioningProfile != null || codesignIdentity != null) {
    return ReleasePlan(
      errors: const [
        'flutter build ipa cannot take a provisioning profile or signing identity as flags. '
            'Write them into an ExportOptions.plist and pass --export-options-plist.',
      ],
    );
  }
  if (teamId != null) {
    return ReleasePlan(
      command: [
        ...base,
        '--export-options-plist=ios/ExportOptions.generated.plist',
      ],
      writes: {
        'ios/ExportOptions.generated.plist': automaticExportOptions(teamId),
      },
    );
  }
  return ReleasePlan(
    command: base,
    warnings: const [
      'No signing details given: the IPA is signed however the Xcode project is set up (and export will fail '
          'without a valid team). Pass --team-id, or --export-options-plist, or --no-codesign for a test build.',
    ],
  );
}
