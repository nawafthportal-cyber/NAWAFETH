# Sprint 3 Feature Flags Rollout

## Flags in active use

- `FEATURE_MODERATION_CENTER`
- `FEATURE_MODERATION_DUAL_WRITE`
- `FEATURE_RBAC_ENFORCE`
- `RBAC_AUDIT_ONLY`
- `FEATURE_ANALYTICS_EVENTS`
- `FEATURE_ANALYTICS_KPI_SURFACES`

## Recommended rollout

1. إبقاء `FEATURE_ANALYTICS_KPI_SURFACES=0` حتى اكتمال migration وإعادة بناء يوم واحد على الأقل.
2. تشغيل `FEATURE_ANALYTICS_EVENTS=1` قبل KPI surfaces.
3. الإبقاء على `RBAC_AUDIT_ONLY=1` عند أول توسيع لصلاحيات Sprint 3 في staging.
4. تفعيل `FEATURE_RBAC_ENFORCE=1` تدريجيًا بعد مرور اختبارات dashboard/actions.
5. إبقاء `FEATURE_MODERATION_DUAL_WRITE=1` فقط بعد التحقق من consistency بين sources و`ModerationCase`.
