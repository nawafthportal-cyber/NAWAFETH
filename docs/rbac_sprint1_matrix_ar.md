# RBAC Sprint 1 Matrix

## Dashboard-level access
- `admin/power`: وصول كامل.
- `qa`: قراءة فقط.
- `user`: حسب `allowed_dashboards`.
- `client`: فقط `extras`.

## Permission catalog المضاف في Sprint 1
- `moderation.assign`
- `moderation.resolve`
- `content.hide_delete`
- `support.assign`
- `support.resolve`
- `promo.quote_activate`
- `verification.finalize`
- `analytics.export`

## قاعدة التنفيذ الحالية
- عند `FEATURE_RBAC_ENFORCE=0`: fallback إلى dashboard access الحالي.
- عند `FEATURE_RBAC_ENFORCE=1`: تعتمد الأفعال الحرجة على `granted_permissions`.
- `RBAC_AUDIT_ONLY=1` يبقي المسار محافظًا أثناء rollout.
