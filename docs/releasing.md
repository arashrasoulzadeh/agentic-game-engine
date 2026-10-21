# Releasing to the stores

`game_agent build-release` wraps `flutter build appbundle` (Android) and `flutter build ipa` (iOS). It does not
upload anything; it produces the signed artifact you give to Google Play Console or App Store Connect.

## Before the first release

1. **Set the version** in `pubspec.yaml` (`version: 1.2.0+14`: name `+` build number). The build number must
   increase on every upload. `--build-name` / `--build-number` override it.
2. **Check the app id** (`--org` at `create` time, or the bundle id in Xcode / `applicationId` in Gradle).
   It cannot change after the first store upload.
3. **Turn off debug overlays**: collider / performance / fps overlays are forced off in release builds, but
   check `assets/game_config.json` anyway.
4. Run `dart analyze` / your tests, and `game_agent studio validate` on your levels.

## Android

Google Play requires the bundle to be signed with your **upload key**, not Flutter's debug key.

**One-time:** create a keystore (keep it and its passwords somewhere safe - losing the upload key is painful):

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**One-time:** make Gradle read `android/key.properties` by adding the snippet below to
`android/app/build.gradle.kts` (the command prints it if it is missing):

```kotlin
import java.util.Properties
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}
// inside android { ... }
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String?
        keyPassword = keystoreProperties["keyPassword"] as String?
        storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
        storePassword = keystoreProperties["storePassword"] as String?
    }
}
buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
```

**Each release:**

```bash
game_agent build-release --android \
  --keystore-path release.jks --keystore-password "$KS_PASS" --key-alias upload --key-password "$KEY_PASS"
# -> build/app/outputs/bundle/release/app-release.aab
```

The command writes `android/key.properties` for the build and removes it afterwards. Never commit the keystore or
that file.

## iOS (macOS only)

Signing is configured in Xcode (**Signing & Capabilities**: team, bundle id, certificates, profiles).

- **Automatic signing:** `game_agent build-release --no-android --ios --team-id ABCDE12345` generates an
  `ExportOptions.plist` (app-store method, automatic signing) and builds the IPA.
- **Manual signing** (a specific profile or distribution certificate): write the details into an
  `ExportOptions.plist` yourself and pass `--export-options-plist path/to/it.plist`. `--provisioning-profile` and
  `--codesign-identity` alone are rejected, because `flutter build ipa` cannot take them as flags.
- **Test build:** `--no-codesign` skips signing.

Upload the resulting IPA with Xcode's Organizer or `xcrun altool` / Transporter.

## In CI

Keep the keystore as a base64 secret, decode it to a file in the job, and pass the passwords from secret
variables (not literals) - see the warning in the [CLI reference](reference/cli.md#build-release). Use
`--dry-run` first to see the exact `flutter` command that will run.

## What is not covered

Google Play / App Store listing, review and rollout; web and desktop distribution; and code signing for the
studio itself (see `TODO.md`).
