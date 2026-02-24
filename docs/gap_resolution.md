# GAP Resolution (Backend)

## Scope
تم تنفيذ إغلاق الفجوات المطلوبة في لوحة التشغيل داخل `backend` وفق المراحل:
- GAP-01: لوحة إدارة المحتوى
- GAP-02: لوحة إدارة المراجعات
- CONFLICT-01: توحيد مصطلح Expiry

---

## GAP-01 — Dashboard Content Management

### ما تم إضافته
- تطبيق جديد: `apps/content`
  - Models:
    - `SiteContentBlock` (مفاتيح ثابتة لمحتوى onboarding/settings)
    - `SiteLegalDocument` (مستندات قانونية مع رفع ملف آمن)
    - `SiteLinks` (روابط المنصة)
  - Public API:
    - `GET /api/content/public/`

- Dashboard routes (RTL):
  - `GET /dashboard/content/`
  - `POST /dashboard/content/blocks/<key>/update/`
  - `POST /dashboard/content/docs/<doc_type>/upload/`
  - `POST /dashboard/content/links/update/`

### الأمان
- CSRF مفعّل تلقائياً عبر نمط Django forms.
- XSS mitigation: تعقيم النص عبر `strip_tags` قبل الحفظ (`sanitize_text`).
- File upload validation:
  - الحجم الأقصى: 10MB
  - امتدادات مسموحة: `pdf/doc/docx/txt`
  - MIME allow-list
- Audit logging لكل عملية تعديل/رفع/تحديث روابط.

### RBAC
- كتابة: `admin` و `power`
- قراءة فقط: `qa`
- غير مصرح: المستخدمون غير الإداريين/غير الموظفين

---

## GAP-02 — Dashboard Reviews Operations

### ما تم إضافته
- Dashboard routes:
  - `GET /dashboard/reviews/` (فلاتر: rating/status/date/target)
  - `GET /dashboard/reviews/<id>/`
  - `POST /dashboard/reviews/<id>/actions/moderate/` (approve/reject/hide)
  - `POST /dashboard/reviews/<id>/actions/respond/` (optional)

- توسيع نموذج `Review`:
  - `moderation_status` (`approved/rejected/hidden`)
  - `moderation_note`, `moderated_at`, `moderated_by`
  - `management_reply`, `management_reply_at`, `management_reply_by`

- منطق العرض العام للمراجعات:
  - API العام يعرض فقط المراجعات `approved`
  - ملخص التقييم يحسب فقط المراجعات `approved`

### RBAC
- كتابة: `admin` و `power`
- قراءة فقط: `qa`

---

## CONFLICT-01 — Expiry Meaning

### القرار المعتمد: Option B
تم اعتماد أن `expires_at` تعني **انتهاء صلاحية الوصول للداشبورد** وليست انتهاء كلمة المرور.

### ما نُفذ
- تحديث نصوص UI في صفحة صلاحيات التشغيل لتوضيح المصطلح:
  - `انتهاء صلاحية الوصول (اختياري)`
  - توضيح أن المقصود Access Expiration.

---

## الملفات الرئيسية
- `backend/apps/content/*`
- `backend/apps/dashboard/content_views.py`
- `backend/apps/dashboard/reviews_views.py`
- `backend/apps/dashboard/templates/dashboard/content_management.html`
- `backend/apps/dashboard/templates/dashboard/reviews_list.html`
- `backend/apps/dashboard/templates/dashboard/reviews_detail.html`
- `backend/apps/reviews/models.py`
- `backend/apps/reviews/views.py`
- `backend/apps/reviews/signals.py`
- `backend/apps/dashboard/urls.py`
- `backend/config/urls.py`
- `backend/config/settings/base.py`

---

## الاختبارات
أضيفت اختبارات تغطي:
- صلاحيات المحتوى والمراجعات (admin/power vs qa)
- تحقق رفع الملفات غير الصالحة
- smoke routes للأقسام الجديدة
- سلوك إخفاء المراجعة وعدم ظهورها في API العام
- توضيح مصطلح Access Expiration في UI
