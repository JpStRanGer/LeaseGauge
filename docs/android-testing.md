# Android / Volvo testing

LeaseGauge's Android application ID is `com.strangestudio.leasegauge`.
It is a separate app from EX30 Trykkespill (`no.jonas.helloex30`). Do not
upload it as an update to that app or change its package name to replace it.

## Scope and distribution limits

- The current app is a manual lease calculator. It does **not** read the
  odometer, connect to Volvo, or synchronize with a phone/browser.
- Android Automotive OS (AAOS) runs directly in the Volvo EX30. This setup
  does not add support for phone-projected Android Auto or Apple CarPlay.
- The manifest declares Automotive as optional so phone/tablet support is
  preserved. It does not require a fixed display orientation.
- The Flutter activity is for **parked use only** in a car. It must not be
  marked `distractionOptimized`; do not bypass the car's UX restrictions.
- Automotive compatibility is not Play category approval. A lease calculator
  is not clearly covered by the current supported car categories. Do not
  label it as a game, browser, navigation or media app to obtain distribution.
  Confirm the applicable route with Google Play before relying on distribution
  to testers' cars or promising a public car release.
- Internal testing has no car form-factor review, but that is not a policy
  exemption or a guarantee that the app is eligible/available on every car.

References: [supported categories](https://developer.android.com/training/cars#supported-app-categories),
[distribution and review](https://developer.android.com/training/cars/distribute),
[parked app requirements](https://developer.android.com/training/cars/parked/automotive-os).

## Local emulator check

Start the Volvo emulator in Android Studio, then run from the project root:

```powershell
& 'C:\dev\flutter\bin\flutter.bat' devices
& 'C:\dev\flutter\bin\flutter.bat' run -d emulator-5554
```

Use the ID actually printed by `devices` if it differs. This installs a
debug build only on that emulator; it does not publish anything.

Check setup, date entry, commute weekdays, save/back navigation, restart
persistence and readable layout. Validate both portrait and landscape layouts
and confirm that the OS blocks the app while driving is simulated. Do not use
the real car while driving for these tests.

## Signed upload bundle

Release builds intentionally fail when upload-signing credentials are absent
or incomplete. There is no fallback to a debug key or an unsigned release.

The recommended local helper prompts for passwords without putting them in
shell history, a tracked file, or command-line arguments:

```powershell
.\tools\build-android-release.ps1 -KeyStorePath 'C:\path\to\upload-key.jks' -KeyAlias 'your-upload-alias'
```

Choose the upload key you intend to keep using for LeaseGauge and back it up
securely. An existing upload key can be reused for a new Play app if desired;
the helper only reads the selected keystore and never modifies it. Passwords
are supplied to the build as process environment variables and the previous
environment is restored when the helper exits. Do not run with shell tracing
or share logs that contain secrets. Never send passwords in chat.

The helper runs analysis and unit/widget tests, then `flutter build appbundle
--release`. The build prints the resulting `.aab` path under
`build/app/outputs/bundle/release/`. Keep the local debug APK separate from this
signed upload bundle. Only a successful build is a new upload candidate.

Alternative for local/CI setup: copy `android/key.properties.example` to
`android/key.properties`, complete it privately, and run the Flutter build
command directly. `key.properties` and keystores are ignored by Git.
`LEASEGAUGE_KEYSTORE_PATH`, `LEASEGAUGE_KEY_ALIAS`, `LEASEGAUGE_STORE_PASSWORD`
and `LEASEGAUGE_KEY_PASSWORD` override the corresponding file settings.

Current version comes from `pubspec.yaml` (`1.0.0+1`). For each new Play upload,
increase the build number after `+` (or use `-BuildNumber 2` with the helper,
then `3`, and so on). Numbers already uploaded for this app cannot be reused.

See [Flutter's Android release guide](https://docs.flutter.dev/deployment/android).

## Play Console handoff (after eligibility and device compatibility checks)

1. Create a separate **LeaseGauge** app entry, type **App**, not Game.
2. Configure Play App Signing and the selected upload certificate.
3. In Advanced settings > Form factors, configure **Android Automotive OS**
   with a dedicated AAOS track if available for the app's approved use case.
4. Select **Internal testing > Automotive OS only**. Add testers' Google
   accounts, upload the signed bundle and review all console warnings/errors.
5. Publish only after the account owner has reviewed the release. Testers join
   through the opt-in link using the Google account they use in the car.
6. Verify that Play lists the actual Volvo model as compatible before asking
   testers to install. A successful emulator build does not establish this.

Building locally never creates a Play app, uploads a file, or publishes a release.
