# نوافذ — NAWAFETH

[![Backend Tests](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/backend-critical-tests.yml/badge.svg)](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/backend-critical-tests.yml)
[![Mobile Flutter Tests](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/mobile-flutter-tests.yml/badge.svg)](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/mobile-flutter-tests.yml)
[![Docker Build](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/docker.yml/badge.svg)](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/docker.yml)

منصة سوق خدمات عربية شاملة تربط العملاء بمقدمي الخدمات. تتضمن تطبيق موبايل (Flutter)، واجهة ويب (Django templates)، ولوحة تحكم إدارية.

**الدومين:** nawafthportal.com

---

## هيكل المشروع

```
nawafeth/
├── backend/          # Django API + لوحة التحكم + صفحات الويب
│   ├── apps/         # 25 تطبيق Django
│   ├── config/       # إعدادات المشروع (base, dev, prod)
│   ├── scripts/      # سكربتات النشر والبناء
│   ├── static/       # ملفات CSS/JS
│   └── templates/    # قوالب HTML
├── mobile/           # تطبيق Flutter
│   ├── lib/screens/  # 34 شاشة
│   ├── lib/services/ # 26 خدمة API
│   └── lib/widgets/  # مكونات UI
├── nginx/            # إعدادات Nginx reverse proxy
├── docker-compose.yml
└── render.yaml       # إعداد النشر على Render
```

## التقنيات

| الطبقة | التقنية |
|--------|---------|
| Backend | Django 5.1, Django REST Framework, Channels (WebSocket) |
| المهام الخلفية | Celery + Celery Beat + Redis broker |
| قاعدة البيانات | PostgreSQL (إنتاج) / SQLite (تطوير) |
| التخزين المؤقت | Redis |
| تخزين الملفات | Cloudflare R2 (S3) / مجلد محلي |
| السيرفر | Gunicorn + Uvicorn ASGI worker |
| الملفات الثابتة | WhiteNoise + Brotli |
| الموبايل | Flutter (Dart 3) |
| البنية التحتية | Docker Compose (6 خدمات) / Render Blueprint |

## تطبيقات Backend (25 تطبيق)

| الفئة | التطبيقات | الوصف |
|-------|----------|-------|
| الهوية والمصادقة | `accounts`, `verification`, `core` | تسجيل، OTP، JWT، بصمة حيوية |
| السوق | `providers`, `marketplace`, `reviews` | مقدمو خدمات، طلبات، تقييمات |
| التواصل | `messaging`, `notifications`, `support` | محادثات فورية، إشعارات، تذاكر دعم |
| التجارة | `billing`, `subscriptions`, `extras` | فوترة، اشتراكات، إضافات |
| المحتوى | `promo`, `content`, `excellence` | عروض ترويجية، جوائز تميز |
| الإدارة | `dashboard`, `backoffice`, `moderation`, `audit` | لوحة تحكم RBAC، إشراف، سجل مراجعة |
| التحليل | `analytics`, `features` | تتبع أحداث، أعلام ميزات، KPIs |
| متخصص | `mobile_web`, `unified_requests`, `extras_portal`, `uploads` | صفحات ويب، بوابة شركاء |

## نقاط API الرئيسية

```
/healthz/                    # فحص الحياة
/health/live/  /health/ready/ # فحوصات Kubernetes
/admin-panel/                # لوحة Django الإدارية
/dashboard/                  # لوحة التحكم

/api/accounts/       # المصادقة والملفات الشخصية
/api/providers/      # مقدمو الخدمات
/api/marketplace/    # طلبات السوق والمطابقة
/api/messaging/      # المحادثات + WebSocket
/api/notifications/  # الإشعارات
/api/reviews/        # التقييمات
/api/subscriptions/  # إدارة الاشتراكات
/api/billing/        # الفواتير والمدفوعات
/api/verification/   # التحقق من الهوية
/api/promo/          # الحملات الترويجية
/api/extras/         # الخدمات الإضافية
/api/excellence/     # نظام الجوائز
/api/analytics/      # تتبع الأحداث
/api/moderation/     # إشراف المحتوى
/api/support/        # تذاكر الدعم
/api/features/       # أعلام الميزات

/mobile-web/         # صفحات الويب المتجاوبة
/portal/extras/      # بوابة الشركاء
```

## المتطلبات

- Python 3.12+
- Flutter stable channel
- PowerShell (Windows) أو Bash (Linux/macOS)
- اختياري محلياً: Redis + PostgreSQL

---

## ⚙️ الإعداد المحلي

### Backend

```powershell
# 1) البيئة الافتراضية
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# 2) التبعيات
cd backend
pip install --upgrade pip
pip install -r requirements.txt -r requirements/dev.txt

# 3) ملف الإعدادات — انسخ من المثال
cp env.example .env
# عدّل القيم حسب الحاجة

# 4) قاعدة البيانات والتشغيل
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

أو استخدم السكربت الجاهز:
```powershell
backend\runserver_local.ps1
```

#### إعدادات البيئة

| المتغير | القيمة الافتراضية | الوصف |
|---------|------------------|-------|
| `DJANGO_ENV` | `dev` | `dev` أو `prod` |
| `DJANGO_DEBUG` | `1` | تفعيل وضع التطوير |
| `DJANGO_SECRET_KEY` | — | مفتاح سري (مطلوب) |
| `DATABASE_URL` | فارغ = SQLite | رابط PostgreSQL |
| `REDIS_URL` | فارغ = ذاكرة محلية | رابط Redis |

### Mobile (Flutter)

```powershell
cd mobile
flutter pub get

# تشغيل مع الباك اند المحلي
flutter run --dart-define=API_TARGET=local

# تشغيل مع سيرفر Render
flutter run --dart-define=API_TARGET=render

# رابط مخصص
flutter run --dart-define=API_TARGET=auto --dart-define=API_BASE_URL=https://example.com

# تعديل رابط الباك اند المحلي (مثلاً للشبكة المحلية)
flutter run --dart-define=API_TARGET=local --dart-define=API_LOCAL_BASE_URL=http://192.168.1.10:8000
```

> `API_TARGET` يكون `render` افتراضياً.

---

## 🐳 Docker Compose

يتضمن 6 خدمات:

| الخدمة | الصورة | الوصف |
|--------|--------|-------|
| `db` | PostgreSQL 16 | قاعدة بيانات رئيسية |
| `redis` | Redis 7 | Cache + Broker + Channels |
| `web` | Django + Gunicorn | سيرفر التطبيق (3 workers) |
| `celery_worker` | Celery | معالجة المهام الخلفية |
| `celery_beat` | Celery Beat | جدولة المهام |
| `nginx` | Nginx 1.27 | Reverse proxy + ملفات ثابتة |

```powershell
docker-compose up -d
```

## ⏰ المهام المجدولة (Celery Beat)

| المهمة | التكرار | الوظيفة |
|--------|---------|---------|
| marketplace-dispatch-ready | كل دقيقة | مطابقة وإرسال الطلبات العاجلة |
| verification-expire-badges | كل ساعة | تنظيف شارات التحقق المنتهية |
| promo-auto-complete | كل ساعة | إنهاء الحملات المنتهية |
| subscription-renewal-reminders | كل 6 ساعات | تذكيرات تجديد الاشتراك |
| excellence-generate-candidates | كل 12 ساعة | ترشيح المرشحين للجوائز |
| excellence-rebuild-all-cache | يومياً 3:15 ص | تحديث كاش الجوائز |
| analytics-rebuild-daily-stats | يومياً 2:20 ص | إعادة بناء إحصائيات KPI |

---

## 🧪 الاختبارات

### Backend

```powershell
cd backend
python manage.py check                        # فحص النظام
python manage.py makemigrations --check --dry-run  # فحص الهجرات
pytest -q                                      # تشغيل الاختبارات
```

### Mobile

```powershell
cd mobile
flutter test
```

## 🚀 النشر على Render

ملف `render.yaml` يحدد:
- **Web service:** `nawafeth-backend` (Python)
- **Redis:** `nawafeth-redis` (key-value)
- **PostgreSQL:** `nawafeth-db`

خطوات النشر التلقائية:
1. **Build:** `bash scripts/render_build.sh`
2. **Pre-deploy:** migrations + collectstatic + smoke tests
3. **Start:** `bash scripts/render_start.sh`

### Feature Flags (إنتاج)

| العلم | القيمة | الوصف |
|-------|--------|-------|
| `FEATURE_MODERATION_CENTER` | `1` | مركز الإشراف |
| `FEATURE_ANALYTICS_EVENTS` | `1` | تتبع الأحداث |
| `FEATURE_ANALYTICS_KPI_SURFACES` | `1` | لوحات KPI |
| `PROMO_HOME_BANNER_VIDEO_AUTOFIT` | `1` | قص تلقائي لفيديوهات البانر (1920×840) |
| `INSTALL_FFMPEG_ON_BUILD` | `1` | تثبيت ffmpeg أثناء البناء |

## 📁 الملفات الثابتة والوسائط

- الملفات الثابتة تُجمع في `backend/staticfiles` وتُقدم عبر WhiteNoise + Brotli.
- الوسائط المحلية في `backend/media/`.
- تخزين سحابي اختياري عبر R2/S3 (`USE_R2_MEDIA=1`).

## 🔐 المصادقة

1. تسجيل المستخدم → إرسال OTP عبر SMS
2. تحقق OTP → إصدار JWT (60 دقيقة access, 30 يوم refresh)
3. خيار بصمة حيوية (fingerprint/face)

| الوضع | سلوك OTP |
|-------|----------|
| `dev` | قبول أي رمز من 4 أرقام |
| `prod` | تحقق صارم فقط |

## CI/CD

| Workflow | الملف | الوظيفة |
|----------|-------|---------|
| Backend Tests | `backend-critical-tests.yml` | اختبارات Python 3.12 + pytest |
| Mobile Tests | `mobile-flutter-tests.yml` | اختبارات Flutter + badge guard |
| Docker Build | `docker.yml` | بناء وتحقق Docker Compose |

---

## ملاحظات تشغيلية

- الإعدادات تُحدد تلقائياً حسب `DJANGO_ENV`: `dev` → `config.settings.dev`, `prod` → `config.settings.prod`
- في الإنتاج: HTTPS إجباري، HSTS، رؤوس أمان، CORS/CSRF مقيدة
- تجاوز OTP في التطوير فقط — معطل تماماً في الإنتاج
