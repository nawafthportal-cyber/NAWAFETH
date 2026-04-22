# أوامر المشروع

مرجع سريع ومرتب لأهم أوامر مشروع NAWAFETH على Windows وPowerShell.

## المسارات الأساسية

```powershell
cd c:\Users\manso\nawafeth
cd c:\Users\manso\nawafeth\backend
cd c:\Users\manso\nawafeth\mobile
```

## تفعيل البيئة الافتراضية للـ Backend

إذا كانت البيئة الافتراضية في جذر المشروع:

```powershell
cd c:\Users\manso\nawafeth
.\.venv\Scripts\Activate.ps1
```

إذا كانت البيئة الافتراضية داخل مجلد `backend`:

```powershell
cd c:\Users\manso\nawafeth\backend
.\.venv\Scripts\Activate.ps1
```

## إعداد الـ Backend لأول مرة

```powershell
cd c:\Users\manso\nawafeth\backend
python -m pip install --upgrade pip
pip install -r requirements.txt -r requirements/dev.txt
Copy-Item env.example .env
python manage.py migrate
python manage.py collectstatic --noinput
```

## تشغيل الـ Backend محليًا

تشغيل عادي:

```powershell
cd c:\Users\manso\nawafeth\backend
python manage.py runserver
```

تشغيل على الشبكة المحلية LAN:

```powershell
cd c:\Users\manso\nawafeth\backend
python manage.py runserver
```

التشغيل عبر السكربتات الجاهزة:

```powershell
cd c:\Users\manso\nawafeth\backend
.\runserver_local.ps1
.\runserver_lan.ps1
.\runserver_local.cmd
.\runserver_lan.cmd
```

## أوامر Django اليومية

```powershell
cd c:\Users\manso\nawafeth\backend
python manage.py showmigrations
python manage.py makemigrations
python manage.py makemigrations --check --dry-run
python manage.py migrate
python manage.py collectstatic --noinput
python manage.py check
python manage.py createsuperuser
python manage.py shell
```

## اختبارات وفحوصات الـ Backend

```powershell
cd c:\Users\manso\nawafeth\backend
pytest -q
python scripts\startup_smoke.py
python scripts\smoke_inbox.py
python scripts\smoke_support_ticket.py
```

## سكربتات الصيانة في الـ Backend

```powershell
cd c:\Users\manso\nawafeth\backend
python scripts\backfill_extras_bundle_payment_links.py
python scripts\print_static_manifest_path.py
```

## تشغيل محاكي أندرويد

عرض المحاكيات المتاحة:

```powershell
emulator -list-avds
```

تشغيل محاكي محدد:

```powershell
emulator -avd Medium_Phone
```

## أوامر Flutter

```powershell
cd c:\Users\manso\nawafeth\mobile
flutter clean
flutter pub get
flutter test
```

تشغيل التطبيق على المحاكي مع الـ Backend المحلي:

```powershell
cd c:\Users\manso\nawafeth\mobile
flutter run -d emulator-5554 --dart-define=API_TARGET=local
```

تشغيل التطبيق مع سيرفر Render:

```powershell
cd c:\Users\manso\nawafeth\mobile
flutter run -d emulator-5554 --dart-define=API_TARGET=render```

تشغيل التطبيق مع رابط API مخصص:

```powershell
cd c:\Users\manso\nawafeth\mobile
flutter run -d emulator-5554 --dart-define=API_BASE_URL=https://example.com
```

إذا كان الـ Backend المحلي يعمل على IP داخل الشبكة:

```powershell
cd c:\Users\manso\nawafeth\mobile
flutter run -d emulator-5554 --dart-define=API_TARGET=local --dart-define=API_LOCAL_BASE_URL=http://192.168.1.10:8000
```

## أوامر Docker Compose

ملاحظة: إذا لم يعمل `docker-compose` استخدم `docker compose` بنفس الأوامر.

```powershell
cd c:\Users\manso\nawafeth
docker-compose up -d
docker-compose down
docker-compose ps
docker-compose logs -f web
docker-compose logs -f celery_worker
docker-compose logs -f celery_beat
docker-compose logs -f nginx
```

## أوامر النشر على Render

هذه الأوامر مخصصة للنشر أو بيئة السيرفر، وليست للاستخدام اليومي في التطوير المحلي:

```powershell
cd c:\Users\manso\nawafeth\backend
bash scripts/render_build.sh
bash scripts/render_migrate.sh
bash scripts/render_start.sh
```

## تسلسل سريع للعمل اليومي

تشغيل الـ Backend:

```powershell
cd c:\Users\manso\nawafeth
.\.venv\Scripts\Activate.ps1
cd backend
python manage.py migrate
python manage.py runserver
```

تشغيل المحاكي والموبايل:

```powershell
emulator -avd Medium_Phone

cd c:\Users\manso\nawafeth\mobile
flutter pub get
flutter run -d emulator-5554 --dart-define=API_TARGET=local
```
