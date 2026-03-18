# Sprint 4 Release Flags Matrix

## Current flags

| Flag | Default in code | Recommended release state | Notes |
| --- | --- | --- | --- |
| `FEATURE_MODERATION_CENTER` | `0` | staged enable | فعّلها بعد تطبيق migrations والتحقق من dashboard routes |
| `FEATURE_MODERATION_DUAL_WRITE` | `0` | staged enable لاحقًا | لا تُفعّل قبل مراقبة consistency في staging |
| `FEATURE_RBAC_ENFORCE` | `0` | staged enable | لا تُفعّل مع `RBAC_AUDIT_ONLY=0` من أول rollout |
| `RBAC_AUDIT_ONLY` | `1` | keep enabled أولًا | اجمع audit logs قبل التشديد الكامل |
| `FEATURE_ANALYTICS_EVENTS` | `0` | enable before KPI surfaces | آمن للتفعيل المبكر |
| `FEATURE_ANALYTICS_KPI_SURFACES` | `0` | enable after first aggregate rebuild | لا تعتمد عليه قبل توفر rows يومية |

## Recommended rollout order

1. Apply migrations and restart API / worker / beat.
2. Enable `FEATURE_ANALYTICS_EVENTS=1`.
3. Enable `FEATURE_MODERATION_CENTER=1` في staging ثم production المحدود.
4. Keep `FEATURE_MODERATION_DUAL_WRITE=0` حتى تمر complaint/report smoke checks.
5. Keep `RBAC_AUDIT_ONLY=1` و`FEATURE_RBAC_ENFORCE=0` في أول production rollout.
6. Run one successful daily aggregate rebuild or force a manual rebuild for the current day.
7. Enable `FEATURE_ANALYTICS_KPI_SURFACES=1`.
8. Enable `FEATURE_MODERATION_DUAL_WRITE=1` بعد مراقبة consistency.
9. Enable `FEATURE_RBAC_ENFORCE=1` فقط بعد مراجعة audit logs، ثم اضبط `RBAC_AUDIT_ONLY=0`.

## Rollback guidance

- إذا ظهرت inconsistency في البلاغات: عطّل `FEATURE_MODERATION_DUAL_WRITE` فقط، ولا تُغلق source flows الأصلية.
- إذا ظهرت false denies في العمليات الداخلية: عطّل `FEATURE_RBAC_ENFORCE` وأبقِ `RBAC_AUDIT_ONLY=1`.
- إذا ظهرت مؤشرات غير مكتملة: عطّل `FEATURE_ANALYTICS_KPI_SURFACES` مع إبقاء `FEATURE_ANALYTICS_EVENTS=1`.
