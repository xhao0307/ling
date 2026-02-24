# City Ling Flutter Client (Shell)

This folder contains a Flutter client shell for the backend APIs in this repo.

Current MVP features:
- AR viewport with live camera preview
- On-device visual labeling for common city objects (Android/iOS)
- 2D spirit overlay + spirit dialogues after scan
- Pokedex and daily report views

## Prerequisite

Install Flutter first: https://docs.flutter.dev/get-started/install

## Bootstrap project files

If `android/` and `ios/` folders are missing, run:

```bash
cd flutter_client
flutter create .
```

This will generate platform folders and keep the existing `lib/main.dart`.

## Run

```bash
cd flutter_client
flutter pub get
flutter run --dart-define=CITYLING_BASE_URL=http://121.43.118.53:3026
```

`CITYLING_BASE_URL` tips:
- Android emulator: `http://10.0.2.2:8080`
- iOS simulator: `http://127.0.0.1:8080`
- Real device: use your LAN IP, e.g. `http://192.168.1.10:8080`

Platform notes:
- Camera and on-device recognition are enabled on Android/iOS.
- On macOS/web, the app falls back to manual object label selection.
