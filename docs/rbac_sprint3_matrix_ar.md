# RBAC Matrix - Sprint 3

## Newly expanded permissions

- `subscriptions.manage`
  - يغطي: إسناد طلبات الاشتراك، تغيير حالتها، وتفعيل الاشتراكات من dashboard.

- `extras.manage`
  - يغطي: إسناد طلبات الخدمات الإضافية، تحديث حالتها، وتفعيل الإضافات من dashboard.

## Existing permissions reused in Sprint 3

- `support.resolve`
  - يغطي quick updates على التذاكر عند التفعيل.

- `promo.quote_activate`
  - استُخدم أيضًا لمسارات `ops status` و`reject` على حملات الترويج.

- `verification.finalize`
  - استُخدم أيضًا لتفعيل طلبات التوثيق المدفوعة.

## Rollout note

عند `RBAC_AUDIT_ONLY=1` يبقى fallback dashboard-level فعالًا مع audit logs.
عند `FEATURE_RBAC_ENFORCE=1` تصبح permission matrix هي المرجع النهائي للأفعال المغطاة.
