# NOTES.MD - أوامر تشغيل المحاكي

## 1) Start emulator

```powershell
cd C:\Users\manso\nawafeth\mobile
flutter emulators
flutter emulators --launch Medium_Phone
adb devices
```

Expected device:
- `emulator-5554`

---

## 2) بيئة الإنتاج (Render)

```powershell
cd C:\Users\manso\nawafeth
git pull origin main

cd C:\Users\manso\nawafeth\mobile
flutter clean
flutter pub get

adb -s emulator-5554 uninstall com.example.nawafeth
flutter run -d emulator-5554 --target lib/main.dart --dart-define=API_TARGET=render --dart-define=API_RENDER_BASE_URL=https://nawafeth-2290.onrender.com
```

---

## 3) بيئة التطوير (Local)

### Local backend on same machine

```powershell
cd C:\Users\manso\nawafeth
git pull origin main

cd C:\Users\manso\nawafeth\mobile
flutter clean
flutter pub get

adb -s emulator-5554 uninstall com.example.nawafeth
flutter run -d emulator-5554 --target lib/main.dart --dart-define=API_TARGET=local
```

### Local backend on another device in same network (optional)

```powershell
flutter run -d emulator-5554 --target lib/main.dart --dart-define=API_TARGET=local --dart-define=API_LOCAL_BASE_URL=http://192.168.1.10:8000
```

---

## 4) Quick checks

```powershell
adb devices
flutter devices
flutter doctor -v
```
