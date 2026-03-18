# Sprint 2 Feature Flags Rollout

## Flags

- `FEATURE_MODERATION_CENTER`
  - يفعّل مركز الموديريشن وواجهاته
- `FEATURE_MODERATION_DUAL_WRITE`
  - يفعّل كتابة الحالات إلى `ModerationCase` من المصادر الحالية
- `FEATURE_RBAC_ENFORCE`
  - يفعّل staged enforcement للصلاحيات الحساسة
- `RBAC_AUDIT_ONLY`
  - يسمح بتسجيل قرارات policy دون قطع التدفق في fallback mode
- `FEATURE_ANALYTICS_EVENTS`
  - يفعّل event ingest والـ emitters الجديدة

## Recommended rollout

1. `FEATURE_MODERATION_CENTER=1` على staging فقط
2. `FEATURE_MODERATION_DUAL_WRITE=1` بعد التأكد من عدم كسر complaint/report flows
3. `FEATURE_RBAC_ENFORCE=0`, `RBAC_AUDIT_ONLY=1` في أول rollout
4. بعد مراجعة audit logs:
   - فعّل `FEATURE_RBAC_ENFORCE=1` على المسارات الحرجة فقط عبر deployment staged
5. فعّل `FEATURE_ANALYTICS_EVENTS=1` قبل التحقق من emitters والـ client baseline

## Sprint 3 defer

- aggregate jobs
- KPI cards/pages الكبيرة
- parity gates الصارمة في CI
