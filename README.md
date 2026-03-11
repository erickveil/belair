# Belair

A multi-platform local file transfer application built with Flutter.

## Features
- Automatic device discovery using UDP broadcasting.
- High-speed file transfer acting as both client and server.
- Support for manual IP entry.
- Cross-platform support (Windows, macOS, Linux, Android, iOS).

## Building the Application

Build scripts are available in the `scripts` directory and require Node.js.

### Windows Build
Generates a zipped release of the Windows application.
```bash
node scripts/build-windows.js
```

### Android Build
Generates a signed APK (requires the dummy key at `D:\AndroidPlayStore\Dummy`).
```bash
node scripts/build-android.js
```
The version name and version code are automatically derived from `pubspec.yaml`. For example, `1.0.3` becomes versionCode `10003`.
