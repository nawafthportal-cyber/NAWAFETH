# Dashboard V2 Backend Contract

## 1) الوحدات المتاحة
- `support`
- `content`
- `moderation`
- `reviews`
- `promo`
- `verify`
- `subs`
- `extras`
- `analytics`
- `admin` (alias -> `admin_control`)
- `client_extras`

## 2) الأكواد الرسمية للوحات
- الكود الداخلي المعتمد للإدارة: `admin_control`
- aliases المدعومة للتوافق: `admin`, `access`
- مرجعية الأكواد: `backend/apps/dashboard/contracts.py`

## 3) الحالات التشغيلية الرسمية (Operational Status)
- `NEW`
- `IN_PROGRESS`
- `RETURNED`
- `CLOSED`

مرجعية التحقق والانتقالات:
- `backend/apps/unified_requests/workflows.py`

## 4) Request Types الرسمية (Unified)
- `helpdesk`
- `promo`
- `verification`
- `subscription`
- `extras`
- `reviews`

المرجع:
- `backend/apps/unified_requests/models.py` (`UnifiedRequestType`)

## 5) فرق التشغيل الرسمية (Team Codes)
- `support`
- `content`
- `moderation`
- `reviews`
- `promo`
- `verify`
- `subs`
- `extras`
- `analytics`
- `admin_control`
- `client_extras`

المرجع:
- `backend/apps/dashboard/contracts.py` (`TEAM_CODE_TO_NAME_AR`)

## 6) الصلاحيات الرسمية (RBAC)
- مستويات الوصول:
  - `admin`: وصول كامل
  - `power`: وصول كامل ضمن طبيعة backoffice
  - `user`: وصول للوحات المسموحة + object scope
  - `qa`: read-only
  - `client`: بوابة عميل فقط
- دوال التحقق المركزية:
  - `has_dashboard_access(...)` / `can_access_dashboard(...)`
  - `has_action_permission(...)`
  - `can_access_object(...)`

المرجع:
- `backend/apps/dashboard/access.py`
- `backend/apps/backoffice/policies.py`

## 7) مصدر الحقيقة لكل وحدة
- Business truth: جداول/موديلات الوحدة نفسها.
- Operational truth: `UnifiedRequest` كطبقة Inbox/aggregation فقط.
- أي شاشة Dashboard V2 يجب أن تعتمد:
  - الحالة التشغيلية من `UnifiedRequest.status` (بعد canonicalization).
  - الحالة التجارية التفصيلية من metadata/المصدر عند الحاجة.

## 8) قواعد الربط التي يجب أن تعتمدها Dashboard V2
- لا تعتمد على إخفاء الأزرار فقط؛ backend RBAC هو المرجع الحاكم.
- كل إجراء write يجب أن يمر على:
  - dashboard-level check
  - action-level policy (عند الحاجة)
  - object-level check
- كل تصدير (`csv/xlsx/pdf`) هو عملية audited.
- كل رفع ملفات يجب أن يمر على validators الموحدة (ext + MIME + size + safe naming).
