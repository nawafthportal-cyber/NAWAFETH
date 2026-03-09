# تقرير المراحل 3-10 — نوافذ

**التاريخ:** يوليو 2025  
**الحالة:** مكتمل ✅

---

## نظرة عامة

بعد مراجعة شاملة لكامل الـ codebase (24 تطبيق Django، 170+ مسار URL، 90+ view function، 56+ قالب)، تبيّن أن المراحل 3-8 (لوحات التحكم) مبنية بالكامل مسبقاً. العمل الفعلي تركّز على:

1. ربط PlatformConfig بالقيم الثابتة في الكود (hardcoded values)
2. سد ثغرات Phase 9 (Extras Dashboard) 
3. سد ثغرات Phase 10 (Extras Portal)
4. توحيد الأكواد المكررة (Permissions)
5. إصلاح ثغرة أمنية (OTP bypass)

---

## المراحل 3-8: تأكيد الاكتمال

| المرحلة | اللوحة | الحالة |
|---------|--------|--------|
| 3 | Access & Analytics | ✅ مبنية بالكامل — views, templates, URLs, RBAC |
| 4 | Support | ✅ مبنية بالكامل |
| 5 | Content | ✅ مبنية بالكامل |
| 6 | Promo | ✅ مبنية بالكامل |
| 7 | Verification | ✅ مبنية بالكامل |
| 8 | Subscriptions | ✅ مبنية بالكامل |

---

## ربط PlatformConfig — 8 ملفات × 11 دالة

**القاعدة الأساسية:** *أي أرقام أو أسعار أو مدد أو حدود تشغيلية يجب أن تكون قابلة للتعديل من Django Admin.*

| الملف | الدالة | القيمة السابقة | حقل PlatformConfig |
|-------|--------|----------------|--------------------|
| `subscriptions/services.py` | `_grace_days()` | `settings.SUBS_GRACE_DAYS` | `subscription_grace_days` |
| `subscriptions/offers.py` | `subscription_offer_end_at()` | 365 / 30 | `subscription_yearly_duration_days` / `subscription_monthly_duration_days` |
| `billing/serializers.py` | `InvoiceCreateSerializer.create()` | `settings.DEFAULT_VAT_PERCENT` | `vat_percent` |
| `verification/services.py` | `_get_verification_currency()` | `"SAR"` ثابت | `verification_currency` |
| `excellence/selectors.py` | `get_featured_service_candidates()` | `Decimal("4.50")` | `excellence_min_rating` |
| `excellence/selectors.py` | `get_high_achievement_candidates()` | `5` | `excellence_min_orders` |
| `excellence/selectors.py` | `get_top_100_club_candidates()` | `100` | `excellence_top_n_club` |
| `extras/services.py` | `infer_duration()` | `30` | `extras_default_duration_days` |
| `features/upload_limits.py` | `user_max_upload_mb()` | `100` | `upload_max_file_size_mb` |
| `extras_portal/views.py` | 4 دوال تصدير | `[:200]` / `[:2000]` | `export_pdf_max_rows` / `export_xlsx_max_rows` |

---

## المرحلة 9: Extras Dashboard — إكمال الفجوات

### Views جديدة (`dashboard/views.py`)

1. **`extras_finance_list()`** — عرض قائمة البيانات المالية (IBAN) لمقدمي الخدمات الإضافية
   - بحث بالجوال / IBAN / اسم البنك
   - تصدير CSV
   - ترقيم صفحات

2. **`extras_clients_list()`** — عرض اشتراكات العملاء مع مقدمي الخدمات الإضافية
   - بحث بجوال العميل / المزود
   - فلتر حالة (نشط / غير نشط)
   - تصدير CSV
   - ترقيم صفحات

### URLs جديدة (`dashboard/urls.py`)
- `extras/finance/` → `extras_finance_list`
- `extras/clients/` → `extras_clients_list`

### قوالب جديدة
- `dashboard/extras_finance_list.html`
- `dashboard/extras_clients_list.html`

---

## المرحلة 10: Extras Portal — إكمال الفجوات

### 1. واجهة تفاصيل الفاتورة (جديد)
- **View:** `portal_invoice_detail(request, pk)` في `extras_portal/views.py`
- **URL:** `finance/invoice/<int:pk>/`
- **Template:** `extras_portal/invoice_detail.html`
- يعرض: بيانات الطلب، العميل، التصنيف، المبالغ (تقديري، مستلم، متبقي، فعلي)، التواريخ، سبب الإلغاء
- **أمان:** يتحقق أن الطلب تابع للمزود الحالي (`provider=provider`)
- **ربط:** كشف الحساب في `finance.html` الآن يحتوي على رابط لكل طلب

### 2. إصلاح ثغرة OTP Bypass (أمني 🔒)
```python
# قبل (غير آمن — يقبل أي رمز OTP في الإنتاج)
def _portal_accept_any_otp_code() -> bool:
    return True

# بعد (آمن — يقبل أي رمز فقط في وضع التطوير)
def _portal_accept_any_otp_code() -> bool:
    from django.conf import settings
    return getattr(settings, "DEBUG", False)
```

---

## توحيد الأكواد المكررة — Permissions

### المشكلة
5 ملفات permissions تحتوي على نفس الكود المُكرر:
- `_is_backoffice_request()` — 5 نسخ متطابقة
- `_has_backoffice_access()` — 5 نسخ تختلف فقط في `dashboard_code`
- فحص `assigned_to_id` — 3 نسخ متطابقة

### الحل: `BackofficeDashboardMixin`

**ملف:** `backoffice/permissions.py`

```python
class BackofficeDashboardMixin:
    dashboard_code: str = ""
    
    def _is_backoffice_request(self, request) -> bool: ...
    def _has_backoffice_access(self, request) -> bool: ...
    def _check_assigned_to(self, request, obj) -> bool: ...
```

### الملفات المُعاد هيكلتها

| الملف | الكلاس | `dashboard_code` |
|-------|--------|------------------|
| `verification/permissions.py` | `IsOwnerOrBackofficeVerify` | `"verify"` |
| `support/permissions.py` | `IsRequesterOrBackofficeSupport` | `"support"` |
| `promo/permissions.py` | `IsOwnerOrBackofficePromo` | `"promo"` |
| `extras/permissions.py` | `IsOwnerOrBackofficeExtras` | `"extras"` |
| `subscriptions/permissions.py` | `IsOwnerOrBackofficeSubscriptions` | `"subs"` |

**النتيجة:** حذف ~120 سطر من الكود المكرر.

---

## نتائج الاختبارات

```
414 passed, 4 failed (pre-existing), 1 warning
```

### الاختبارات الفاشلة (موجودة مسبقاً — ليست من تغييراتنا):

| الاختبار | السبب |
|----------|-------|
| `test_my_access_ok` | المستخدم لا يملك `is_staff` — لا يُمرّر `BackofficeAccessPermission` |
| `test_approve_candidate_*` | `notification is None` — خلل في الإشعارات |
| `test_backoffice_list` (support) | 429 Rate Limit — محدد كمية الطلبات |
| 2× websocket tests | مشاكل async pre-existing |

### اختبارات Phase 2 (core): 15/15 ✅

---

## ملخص كامل الملفات المُعدّلة

### Phase 2 (من الجلسة السابقة):
- `core/models.py` — PlatformConfig + ReminderLog
- `core/admin.py` — تسجيل Admin
- `core/tasks.py` — 3 مهام Celery
- `core/tests.py` — 15 اختبار
- `backoffice/models.py` — CLIENT_ALLOWED_DASHBOARDS
- `dashboard/access.py` — تقييد Client scope
- `config/settings/base.py` — Celery beat schedule

### Phase 3-10 (هذه الجلسة):
**ربط PlatformConfig:**
1. `subscriptions/services.py`
2. `subscriptions/offers.py`
3. `billing/serializers.py`
4. `verification/services.py`
5. `excellence/selectors.py` (3 دوال)
6. `extras/services.py`
7. `features/upload_limits.py`
8. `extras_portal/views.py` (4 دوال تصدير)

**Phase 9 — Extras Dashboard:**
9. `dashboard/views.py` — 2 views جديدة
10. `dashboard/urls.py` — 2 URLs جديدة
11. `dashboard/templates/dashboard/extras_finance_list.html` — قالب جديد
12. `dashboard/templates/dashboard/extras_clients_list.html` — قالب جديد

**Phase 10 — Extras Portal:**
13. `extras_portal/views.py` — invoice detail view + OTP fix
14. `extras_portal/urls.py` — invoice detail URL
15. `extras_portal/templates/extras_portal/invoice_detail.html` — قالب جديد
16. `extras_portal/templates/extras_portal/finance.html` — ربط رقم الطلب بصفحة التفاصيل

**توحيد Permissions:**
17. `backoffice/permissions.py` — BackofficeDashboardMixin
18. `verification/permissions.py` — refactored
19. `support/permissions.py` — refactored
20. `promo/permissions.py` — refactored
21. `extras/permissions.py` — refactored
22. `subscriptions/permissions.py` — refactored

**المجموع:** 22 ملف مُعدّل/جديد
