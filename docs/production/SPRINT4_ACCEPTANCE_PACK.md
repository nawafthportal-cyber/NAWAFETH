# Sprint 4 Acceptance Pack

هذا الملف هو baseline القبول النهائية قبل الإطلاق المنضبط. يصف ما أصبح داخل الإصدار، وما يبقى staged rollout، وما هو مؤجل عمدًا.

## Release scope included

- Moderation Center foundation + lifecycle + dashboard queue/detail + dual-write orchestration
- RBAC permission matrix + staged enforcement على الأفعال الحرجة المغطاة
- Analytics event-first + daily aggregates + KPI endpoints + dashboard insights
- Flutter / `mobile_web` parity safeguards الأساسية (contracts, fixtures, smoke guidance)
- Dashboard extraction المحدود للمناطق الحرجة التي طالتها التغييرات

## Acceptance closure summary

| Area | Release status | Evidence | Notes |
| --- | --- | --- | --- |
| Moderation | Ready with staged rollout | moderation models/APIs/dashboard/tests | ownership بقي في الأنظمة الأصلية |
| RBAC | Ready with staged enforcement | policy classes + audit/enforce tests + matrix docs | يوصى بالبدء بـ `RBAC_AUDIT_ONLY=1` |
| Analytics | Ready with gated KPI surfaces | event tracking + daily tasks + KPI tests | لا يعتمد على raw event queries مباشرة |
| Parity | Ready with baseline safeguards | fixtures + PR template + smoke guidance | ليس parity overhaul كامل |
| Dashboard hardening | Ready | extracted analytics/moderation surfaces + regression tests | لا يوجد redesign بصري |
| Governance / docs | Ready | ADRs + rollout docs + post-release boundary | docs الآن تصف الواقع التنفيذي |

## Definition of Done snapshot

### Moderation
- يمكن إنشاء البلاغات الحالية بدون كسر flows الدعم/المراسلة/المراجعات.
- يمكن إنشاء `ModerationCase` بالتوازي عند تفعيل `FEATURE_MODERATION_DUAL_WRITE`.
- توجد queue/detail تشغيلية مع filters وحالة SLA واضحة.
- يوجد audit trail وdecision/action logging واختبارات تغطي happy/forbidden/validation.

### RBAC
- الصلاحيات الحرجة المغطاة تستخدم policy classes نفسها في dashboard/API حيث طُبقت.
- يوجد audit-only mode وenforced mode واختبارات لكل منهما.
- لا يوجد hard cutover غير قابل للتراجع.

### Analytics
- يتم التقاط الأحداث الأساسية من backend والعملاء.
- توجد aggregate rows يومية قابلة لإعادة البناء.
- توجد KPI endpoints وصفحة dashboard بسيطة خلف flag.
- صيغ المؤشرات الأساسية مغطاة باختبارات صحة.

### Parity
- توجد fixtures للعقود الحرجة.
- توجد smoke/checklist للمسارات الحساسة.
- قالب PR يفرض الإفصاح عن التأثير على العقود والـ flags والاختبارات.

## Released vs staged vs deferred

### Released in codebase
- Foundation and tested paths لكل من moderation / RBAC / analytics / parity safeguards
- Backend critical CI workflow
- Production readiness docs and rollout checklists

### Staged rollout
- `FEATURE_MODERATION_CENTER`
- `FEATURE_MODERATION_DUAL_WRITE`
- `FEATURE_RBAC_ENFORCE`
- `RBAC_AUDIT_ONLY`
- `FEATURE_ANALYTICS_EVENTS`
- `FEATURE_ANALYTICS_KPI_SURFACES`

### Deferred intentionally
- Social comments العامة
- dashboard visual redesign
- heavy analytics historical backfill
- BI / warehouse
- ABAC heavy model
- parity overhaul الكامل

### Blocked by product decision
- أي توسيع Social Layer إلى comments/community model

## Required validation before controlled release

- `python manage.py check`
- `python manage.py makemigrations --check --dry-run`
- Backend critical GitHub Actions workflow green
- Flutter workflow green
- Staging smoke for: moderation actions, unread badges, promo/verification critical actions, subscriptions/extras operations
