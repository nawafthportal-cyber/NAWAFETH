# Checklist نشر وإثبات إصلاح home_banner

هذه القائمة مخصصة لتأكيد أن إصلاح مشكلة عدم ظهور `home_banner` بعد الدفع والاعتماد تم تطبيقه فعليًا على البيئة المستهدفة، وأن سلسلة العمل من الفاتورة إلى الظهور العام سليمة.

## 1. قبل النشر

- تأكد أن الفرع المنشور يحتوي على:
  - [backend/apps/promo/views.py](backend/apps/promo/views.py)
  - [backend/apps/promo/migrations/0006_promorequestitem_message_delivery_fields.py](backend/apps/promo/migrations/0006_promorequestitem_message_delivery_fields.py)
  - [backend/apps/promo/tests/test_promo.py](backend/apps/promo/tests/test_promo.py)
- تأكد أن الاستعلامات العامة في promo لا تسحب أعمدة `message_sent_at` و `message_recipients_count` و `message_dispatch_error` ضمن `public querysets`.
- شغّل اختبارات التحقق الأساسية قبل الدفع إلى الإنتاج:

```bash
python -m pytest apps/promo/tests/test_promo.py -k "invoice_paid_signal_activates_home_banner_and_exposes_it_publicly or public_home_banners or ops_completion_does_not_end_active_home_banner_campaign"
```

النتيجة المطلوبة: كل الاختبارات تمر بنجاح.

## 2. إعدادات النشر

- تأكد أن النشر يستخدم `startCommand` الحالي ولا يتجاوزه.
- تأكد أن `preDeployCommand` يشغّل:
  - `python manage.py migrate --noinput`
- تأكد أن:
  - `RUN_MIGRATIONS_ON_START=0`
  - `RUN_COLLECTSTATIC_ON_START=0`
- راجع ملفات النشر المرجعية:
  - [render.yaml](render.yaml)
  - [backend/render.yaml](backend/render.yaml)
  - [backend/scripts/render_start.sh](backend/scripts/render_start.sh)

النتيجة المطلوبة: المايجريشن تتم قبل الإقلاع، وstartup لا تضيع وقت فتح البورت في أعمال ثقيلة.

## 3. أثناء النشر

- راقب logs الإقلاع وابحث عن أحد الاحتمالين:
  - `Applying promo.0006_promorequestitem_message_delivery_fields... OK`
  - `No migrations to apply`
- إذا ظهر `migrate failed` أو `refusing to start with a potentially stale schema` فاعتبر النشر فاشلًا ولا تعتمد البيئة.

النتيجة المطلوبة: الخدمة تقلع بعد `Migrations completed.` بدون أخطاء schema.

## 4. تحقق سريع بعد النشر

- افحص health endpoint:

```bash
curl -I https://<your-domain>/health/live/
```

- افحص endpoint الخاص بالبانرات:

```bash
curl https://<your-domain>/api/promo/banners/home/?limit=3
```

النتيجة المطلوبة:

- حالة HTTP تساوي `200`
- لا يوجد `OperationalError`
- إذا كانت هناك حملة فعالة حاليًا، يجب أن يظهر عنصر يحتوي عادة على:
  - `id`
  - `provider_id`
  - `file` أو `file_url`
  - `caption`

## 5. تحقق بيانات الحملة الفعلية

إذا كان لديك `promo_id` أو `code` في البيئة المستهدفة، نفّذ فحص Django shell التالي:

```bash
python manage.py shell
```

ثم تحقق من الآتي:

```python
from django.utils import timezone
from apps.promo.models import PromoRequest, PromoRequestStatus, PromoServiceType

now = timezone.now()
pr = PromoRequest.objects.select_related("invoice", "requester").prefetch_related("assets", "items", "items__assets").get(code="<PROMO_CODE>")

print("status", pr.status)
print("invoice_status", getattr(pr.invoice, "status", None))
print("ad_type", pr.ad_type)
print("start_at", pr.start_at, "end_at", pr.end_at, "now", now)
print("assets", pr.assets.count())

for item in pr.items.all():
    print({
        "item_id": item.id,
        "service_type": item.service_type,
        "start_at": item.start_at,
        "end_at": item.end_at,
        "assets": item.assets.count(),
    })
```

المطلوب للحملة التي يجب أن تظهر في الصفحة الرئيسية:

- `status == active`
- `invoice_status == paid`
- إذا كانت الحملة legacy: `ad_type == banner_home`
- إذا كانت bundle: يجب أن يوجد item بخاصية `service_type == home_banner`
- يجب أن يكون هناك asset مربوط بالطلب أو بالـ item
- نافذة العرض الحالية يجب أن تشمل الوقت الحالي

## 6. قاعدة الحسم عند التشخيص

- إذا endpoint `/api/promo/banners/home/` يرجع `500` أو `OperationalError`: المشكلة Backend/Data وليست Flutter.
- إذا endpoint يرجع `200` والبيانات صحيحة لكن التطبيق لا يعرضها: عندها فقط يبدأ فحص Flutter.
- لا تبدأ بفحص Flutter قبل التأكد من:
  - migration state
  - request status
  - invoice status
  - assets
  - active time window

## 7. أوامر الإنقاذ السريع

على البيئة المستهدفة:

```bash
python manage.py showmigrations promo
python manage.py migrate --noinput
```

إذا كانت `0006` غير مطبقة، فهذه أولوية الإصلاح الأولى.

## 8. معيار الإغلاق النهائي

يعتبر الإصلاح مكتملاً فقط إذا تحققت الشروط التالية معًا:

- migration `promo.0006` مطبقة
- deploy logs خالية من أخطاء migrate
- `/api/promo/banners/home/` يعيد `200`
- الحملة المدفوعة تتحول إلى `active`
- أصل الإعلان موجود ومربوط
- البانر يظهر في response العام

إذا اختل شرط واحد من هذه الشروط، فلا تعتبر المشكلة منتهية.
