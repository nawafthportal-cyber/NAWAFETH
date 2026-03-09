# Final Closure Contracts

## RBAC Source Of Truth
- المصدر النهائي لصلاحيات لوحات التشغيل هو `User.access_profile` إذا كان فعالًا وغير منتهي وغير مسحوب.
- `is_superuser` يظل تجاوزًا كاملاً لكل اللوحات.
- `is_staff` لم يعد مصدر الحقيقة للتفويض داخل الـ dashboard/backoffice؛ بقي فقط كجسر legacy ولحماية Django admin وما يشبهه.
- المستويات النهائية:
  - `admin`: وصول كامل لكل اللوحات مع الكتابة.
  - `power`: وصول كامل لكل اللوحات مع الكتابة.
  - `user`: وصول فقط إلى اللوحات المصرح بها في `allowed_dashboards` مع احترام حدود التعيين.
  - `qa`: نفس نطاق `user` لكن قراءة فقط.
  - `client`: سياسة ثابتة تجاريًا، نطاقه محصور في `extras` فقط.

## Client Scope Policy
- السياسة النهائية ثابتة وليست admin-driven في هذه المرحلة.
- الثابت الرسمي هو `UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS = {"extras"}`.
- أي اختيار يدوي آخر لهذا المستوى يتم تجاهله ويعاد ضبطه إلى هذا النطاق الثابت.

## OTP Development Mode
- Development OTP Mode يعمل فقط عندما:
  - `DEBUG=True`
  - `OTP_DEV_BYPASS_ENABLED=True`
- عند تفعيل `OTP_DEV_ACCEPT_ANY_4_DIGITS=True`:
  - يقبل النظام أي 4 أرقام في dashboard وextras portal و`/api/accounts/otp/verify/`.
- `OTP_DEV_TEST_CODE` متاح ككود تطوير ثابت اختياري عندما يلزم.
- في `prod.py`:
  - `OTP_DEV_BYPASS_ENABLED=False`
  - `OTP_DEV_ACCEPT_ANY_4_DIGITS=False`
  - `OTP_APP_BYPASS=False`

## Excellence Notification Policy
- إشعار `excellence_badge_awarded` سياسة نظامية إلزامية لمقدم الخدمة الحاصل على الشارة.
- لا يعتمد على امتلاك باقة مدفوعة أعلى من `basic`.
- يبقى مخفيًا من شاشة الإعدادات (`expose_in_settings=False`) لكنه مسموح بالإرسال دائمًا عند الاستحقاق.

## Export Limits
- `export_pdf_max_rows` هو الحد الرسمي لكل PDF dashboard/portal exports.
- `export_xlsx_max_rows` هو الحد الرسمي لكل XLSX exports.
- CSV exports تشارك نفس cap الخاص بالتصدير الجدولي (`export_xlsx_max_rows`).
