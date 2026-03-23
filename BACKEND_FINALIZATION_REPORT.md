# BACKEND Finalization Report

## 1) النقاط التي كانت متضاربة أو غير واضحة
- طبقة `UnifiedRequest` كانت تستخدم حالات تشغيلية + حالات أعمال مختلطة (`pending_payment/active/completed/...`) بدون تطبيع تشغيلي واضح.
- workflow التشغيلي لبعض الوحدات (`promo/subs/extras`) كان مبنيًا على مسار قديم ثلاثي ولم يكن متسقًا مع الحالات الفعلية القادمة من المزامنة.
- وُجد خطأ تشغيل مباشر في `extras_ops` باستخدام `UnifiedRequestStatus.OPEN` (غير موجود).
- object-level access كان مطبقًا بشكل مكرر ومتناثر في الـ views.
- تحقق الرفع كان غير موحّد بين الوحدات (بعض الوحدات تتحقق من الحجم فقط/الامتداد فقط).
- تصدير CSV في `analytics` لم يكن محصنًا ضد CSV Injection.
- تسجيل تدقيق التصدير لم يكن شاملًا بشكل موحد عبر كل مسارات التصدير.

## 2) المرجعية المعمارية المعتمدة (Source of Truth)
- **Business Source of Truth**: الموديلات التخصصية لكل وحدة (Support/Verification/Promo/Subscriptions/Extras).
- **Operational Source of Truth**: `UnifiedRequest` كطبقة تشغيل/Inbox/Aggregation.
- تم اعتماد تطبيع تشغيلي للحالة عبر `unified_requests/workflows.py`:
  - `NEW`, `IN_PROGRESS`, `RETURNED`, `CLOSED`.
  - مع خريطة تحويل legacy للحالات التاريخية (`pending_payment/active/completed/...`) إلى الحالة التشغيلية المكافئة.

## 3) ما تم توحيده فعليًا
- توحيد كود اللوحات عبر مرجعية مركزية:
  - ملف: `backend/apps/dashboard/contracts.py`
  - دعم aliases: `admin` و`access` -> `admin_control`.
- توحيد transition rules التشغيلية في `unified_requests/workflows.py`.
- توحيد object-level helper:
  - `can_access_object(...)` في `dashboard/access.py`
  - واستخدامه في مسارات حساسة داخل `dashboard/views.py`.
- توحيد سياسة الرفع الأمنية عبر:
  - `apps/uploads/validators.py` (امتداد + MIME + حجم + basename + safe rename اختياري).
  - ربطها في `support/verification/promo` + `marketplace` + `messaging` + `extras_portal` forms.

## 4) الإصلاحات المنفذة
- إصلاح bug `UnifiedRequestStatus.OPEN` في `extras_ops`.
- ضبط `upsert_unified_request(...)` لتطبيع الحالات التشغيلية قبل الحفظ للوحدات التشغيلية المستهدفة.
- ضبط `closed_at` بما يتسق مع الحالة التشغيلية المغلقة.
- إضافة validation صريح لانتقالات حالات الدعم في `support/services.py`.
- تحصين `analytics/export.py` ضد CSV Injection.
- إضافة تسجيل تدقيق موحد للتصدير عبر Middleware:
  - `apps/audit/middleware.py`
  - وإضافة `AuditAction.DATA_EXPORTED` (وإكمال أكشنات ناقصة مرتبطة).
- تحسين أمان redirect في extras portal OTP flow باستخدام `is_safe_redirect_url(...)`.
- إضافة migration توحيد dashboard codes:
  - `backoffice/migrations/0007_finalize_dashboard_codes.py`
  - إنشاء/تثبيت الأكواد الرسمية + ترحيل `access/admin` إلى `admin_control`.

## 5) ما تُرك كما هو ولماذا
- حالات الأعمال التفصيلية داخل الوحدات (مثل `VerificationStatus` و`PromoRequestStatus`) بقيت كما هي لأنها Business Domain States.
- لم يتم تنفيذ refactor واسع على كل views لتجنب كسر منطق قائم؛ تم استهداف المسارات الأعلى خطورة أولًا.
- العدادات التاريخية التي تعرض حالات legacy في بعض الشاشات لم تُعاد هندستها بالكامل حفاظًا على التوافق مع السلوك الحالي.

## 6) ما يحتاج متابعة عند Dashboard V2
- نقل كل الـ hardcoded dashboard/team/status labels إلى contract constants بشكل كامل (باقي نقاط متناثرة).
- استكمال تعميم `can_access_object(...)` على جميع الـ views المتبقية دون استثناء.
- توحيد كامل لعدادات KPI لتقرأ من مصادر ثابتة مع إزالة الاعتماد على حالات legacy نهائيًا.
- إضافة اختبارات E2E لسيناريوهات التصدير/الرفع عبر كل الوحدات وليس المسارات الحرجة فقط.
