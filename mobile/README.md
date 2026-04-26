# NAWAFETH Mobile

## API environment setup

The app now reads API configuration from `--dart-define` values.

Supported keys:
- `API_TARGET=auto|local|render`
- `API_BASE_URL=https://example.com` (highest priority if provided)
- `API_LOCAL_BASE_URL=http://192.168.1.10:8000` (optional local override)
- `API_RENDER_BASE_URL=https://www.nawafthportal.com` (optional production override)

Default behavior:
- Uses production backend (`https://www.nawafthportal.com`) unless overridden via `--dart-define`.

## Run commands

Use local backend API:

```bash
flutter run -d emulator-5554 --dart-define=API_TARGET=local
```

Use Render backend API:

```bash
flutter run -d emulator-5554 --dart-define=API_TARGET=render
```

Force a specific API URL (local or remote):

```bash
flutter run -d emulator-5554 --dart-define=API_BASE_URL=https://www.nawafthportal.com
```

## Push notifications (FCM + sound)

This project now includes:
- Firebase Cloud Messaging (`firebase_messaging`)
- Local foreground notifications with sound (`flutter_local_notifications`)
- Backend device token registration (`/api/notifications/device-token/`)

Required setup:

1) Android
- Place `google-services.json` in: `android/app/google-services.json`

2) iOS
- Place `GoogleService-Info.plist` in: `ios/Runner/GoogleService-Info.plist`
- Open iOS project in Xcode and ensure Push Notifications + Background Modes (Remote notifications) are enabled.

3) Backend
- Configure Firebase service account env vars in backend `.env`:
	- `FIREBASE_PUSH_ENABLED=1`
	- `FIREBASE_PROJECT_ID=...`
	- `FIREBASE_CREDENTIALS_PATH=/path/to/service-account.json` (or `FIREBASE_CREDENTIALS_JSON`)

After setup:

```bash
flutter pub get
flutter run -d emulator-5554 --dart-define=API_TARGET=local
```
