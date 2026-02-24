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
- 远端默认后端: `http://121.43.118.53:3026`
- 若切换到本地开发服务，请按运行环境改为本机/局域网地址（例如 Android 模拟器常用 `http://10.0.2.2:8080`）

Platform notes:
- Camera and on-device recognition are enabled on Android/iOS.
- On macOS desktop and web (Chrome), the app can request camera permission and capture frames.
