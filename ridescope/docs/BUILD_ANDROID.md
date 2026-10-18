# Building the Android APK

Two ways to get an installable APK. Both produce a **tester build**: the
Licence screen can unlock Plus/Pro on the device so every feature can be
tried on your own bike. Store builds leave out `RIDESCOPE_TESTER`.

## A. Download from GitHub (no setup)

Every push that touches `ridescope/` runs the *RideScope Android APK*
workflow (`.github/workflows/ridescope-android.yml`). When it finishes:

1. On your phone, open the repository's **Releases** page and pick the newest
   *RideScope tester build N*.
2. Download `RideScope-tester-buildN.apk`.
3. Open it. Android asks to allow "Install unknown apps" for your browser;
   allow it and install.

The workflow can also be run by hand from the **Actions** tab (*Run workflow*).

## B. Build on your own computer

### One-time setup

1. Install **Android Studio** (https://developer.android.com/studio). In
   *Settings → Languages & Frameworks → Android SDK*:
   - *SDK Platforms*: tick **Android API 37** (and 36).
   - *SDK Tools*: tick **Android SDK Command-line Tools** and
     **Android SDK Build-Tools**.
2. Install **Flutter 3.47.7** (https://docs.flutter.dev/get-started/install)
   and put `flutter/bin` on your `PATH`.
3. Accept the Android licences and check everything is green:
   ```sh
   flutter doctor --android-licenses
   flutter doctor
   ```

### Build

```sh
git clone -b ccr-6d99f5aa-cemwwf https://github.com/andyt19911/testing.git
cd testing/ridescope
flutter pub get
flutter build apk --release --dart-define=RIDESCOPE_TESTER=true
```

The APK is at `build/app/outputs/flutter-apk/app-release.apk` (about 25 MB).

### Install on the phone

- **USB (quickest):** turn on *Developer options → USB debugging* on the
  phone, plug it in, accept the prompt, then run `flutter install`. Or build
  and launch in one go with
  `flutter run --release --dart-define=RIDESCOPE_TESTER=true`.
- **Copy the file:** send the APK to the phone (USB, email, Drive), open it,
  and allow "Install unknown apps" when asked.

## Signing

Without a signing key the APK is signed with a debug key. That's fine for
testing, but a build signed by a different key can't update the installed app:
uninstall first. For a stable key:

```sh
keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- **Local builds:** put `upload.jks` in `android/app/` and create
  `android/key.properties`:
  ```
  storeFile=upload.jks
  storePassword=…
  keyAlias=upload
  keyPassword=…
  ```
  Both files are git-ignored. Keep a backup: losing the key means users must
  reinstall.
- **GitHub builds:** add repository secrets `ANDROID_KEYSTORE_BASE64`
  (`base64 -w0 upload.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`.

## First run with the bike

1. Pair the adapter in Android Bluetooth settings (PIN usually 1234 or 0000).
   BLE adapters such as the OBDLink CX don't need pairing.
2. RideScope → **Connect** → Bluetooth → pick the adapter. Allow the
   Bluetooth permission.
3. *Settings → Licence → Tester build → Unlock Pro* to try every function.
