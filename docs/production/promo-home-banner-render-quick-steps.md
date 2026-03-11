# خطوات Render السريعة لإصلاح home_banner

هذا الملف هو النسخة التنفيذية المختصرة لنشر إصلاح `home_banner` على Render والتأكد أن المشكلة أغلقت فعليًا.

## 1. ادفع الكود الصحيح

يجب أن يحتوي deploy على الأقل على الملفات التالية:

- [backend/apps/promo/views.py](backend/apps/promo/views.py)
- [backend/apps/promo/migrations/0006_promorequestitem_message_delivery_fields.py](backend/apps/promo/migrations/0006_promorequestitem_message_delivery_fields.py)
- [backend/apps/promo/tests/test_promo.py](backend/apps/promo/tests/test_promo.py)

## 2. افتح خدمة Render الصحيحة

- Service: `nawafeth-backend`
- تأكد أن الخدمة تستخدم:
  - Build Command: `bash scripts/render_build.sh`
  - Start Command: `bash scripts/render_start.sh`

راجع المرجع إذا احتجت:

- [render.yaml](render.yaml)
- [backend/render.yaml](backend/render.yaml)

## 3. راجع Environment Variables قبل النشر

يجب أن تكون هذه القيم مفعلة:

- `RUN_MIGRATIONS_ON_START=1`
- `RUN_COLLECTSTATIC_ON_START=1`
- `DJANGO_ENV=prod`

إذا كانت `RUN_MIGRATIONS_ON_START` معطلة، لا تكمل النشر قبل تصحيحها.

## 4. نفّذ النشر

على Render:

- اختر `Manual Deploy`
- ثم `Deploy latest commit`

إذا شككت بوجود build cache قديم أو image قديمة، استخدم إعادة بناء نظيفة قبل إعادة المحاولة.

## 5. راقب startup logs

ابحث عن هذه الرسائل:

- `[start] Running migrations before startup`
- `Applying promo.0006_promorequestitem_message_delivery_fields... OK`
  أو
- `No migrations to apply`
- `[start] Migrations completed.`
- `[start] Launching gunicorn`

إذا ظهر أي من التالي، اعتبر النشر غير صالح:

- `migrate failed`
- `refusing to start with a potentially stale schema`
- `no such column: promo_promorequestitem.message_sent_at`

## 6. افحص الخدمة بعد الإقلاع

نفّذ مباشرة:

```bash
curl -I https://<your-domain>/health/live/
curl https://<your-domain>/api/promo/banners/home/?limit=3
```

النتيجة المطلوبة:

- `health/live` يرجع `200`
- `banners/home` يرجع `200`
- لا يوجد `OperationalError`

## 7. إذا كان لديك حملة حقيقية متأثرة

افتح Render Shell ونفّذ:

```bash
python manage.py showmigrations promo
python manage.py migrate --noinput
python manage.py shell
```

ثم داخل shell:

```python
from django.utils import timezone
from apps.promo.models import PromoRequest

now = timezone.now()
pr = PromoRequest.objects.select_related("invoice").prefetch_related("assets", "items", "items__assets").get(code="<PROMO_CODE>")

print("status", pr.status)
print("invoice_status", getattr(pr.invoice, "status", None))
print("ad_type", pr.ad_type)
print("window", pr.start_at, pr.end_at, now)
print("request_assets", pr.assets.count())

for item in pr.items.all():
    print(item.id, item.service_type, item.start_at, item.end_at, item.assets.count())
```

## 8. معيار النجاح النهائي

تعتبر المشكلة منتهية فقط إذا تحقق التالي معًا:

- migration `promo.0006` مطبقة
- الخدمة أقلعت بدون أخطاء schema
- `/api/promo/banners/home/` يرجع `200`
- الطلب المدفوع أصبح `active`
- الأصل الإعلاني موجود
- البانر يظهر في response العام

إذا فشل أي شرط من هذه الشروط، لا تعتبر الإصلاح مكتملًا.