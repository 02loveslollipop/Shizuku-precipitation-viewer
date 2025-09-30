# Shizuku Viewer (Flutter)

Material-themed viewer that overlays precipitation data on a Mapbox basemap (via Flutter Map + Mapbox tiles), powered by the Shizuku API.

## Features

- Mapbox basemap with tappable sensor pins coloured by WMO precipitation intensity classes.
- Toggle between **Heat plot** and **Contour** visual styles via the navigation drawer.
- Bottom panel with average precipitation line chart and time slider (placeholder series when historical data is unavailable).
- Sensor detail sheet with mini history chart fetched on demand.

## Prerequisites

- Flutter SDK ≥ 3.7 (`dart --version` / `flutter --version`).
- Mapbox access token (the app currently uses `pk.eyJ1IjoiMDJsb3Zlc2xvbGxpcG9wIiwiYSI6ImNtZzVjZWtsdDAzOGYycXEyZGttZm85NngifQ.xkNii295tuT1s7eMs0Nrhg`).
- Android Studio/Xcode CLI tools depending on target platform.

## Setup

1. Install packages:
   ```bash
   flutter pub get
   ```

2. Configure Mapbox tokens for each platform:
- **Android**: provide the token when running (`MAPBOX_ACCESS_TOKEN=... flutter run`). If you wish, add it to `android/app/src/main/AndroidManifest.xml` as a `<meta-data>` entry.
- **iOS**: set `MBXAccessToken` in `ios/Runner/Info.plist` or export it at runtime.

3. (Optional) Update the `mapboxAccessToken` constant in `lib/main.dart` if you rotate credentials.

## Running

```bash
flutter run -d <device>
```

The viewer consumes the deployed Shizuku REST API (default base URL `https://api.shizuku.02labs.me`).

## Project structure

- `lib/main.dart` – application entry point with modular UI widgets, Flutter Map integration, API client, and chart widgets.
- `assets/icons/shizuku_logo.svg` – brand icon used in the app bar.
- `services/api/...` (backend Go service) – provides JSON endpoints consumed by the viewer.

## Notes

- Android minSdkVersion is set to 20 to satisfy Mapbox requirements (`android/app/build.gradle.kts`).
- The line chart currently synthesises a short history if the API cannot provide multiple timestamps; replace `ApiClient.fetchAverageSeries` with real aggregation when available.
