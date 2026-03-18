# ADR: Moderation Foundation

تاريخ القرار: 2026-03-17

## القرار
تم إنشاء foundation مستقلة للموديريشن عبر app جديدة: `backend/apps/moderation/`.

## مبادئ التنفيذ
- `loose coupling` مع الأنظمة الحالية.
- لا يوجد نقل ownership من `support/reviews/messaging/content`.
- لا يوجد `FK` إلزامي من الأنظمة الحالية إلى الموديريشن في Sprint 1.
- جميع المسارات الجديدة محمية خلف `FEATURE_MODERATION_CENTER`.

## ما تم بناؤه
- `ModerationCase`
- `ModerationActionLog`
- `ModerationDecision`
- API surface أولية للإنشاء/الاستعراض/التعيين/الحالة/القرار

## ما تم تأجيله
- `dual-write` الواسع
- dashboard UI التشغيلية الكاملة
- integrations العميقة مع كل الأنظمة

## ملاحظات rollout
- التفعيل الافتراضي مغلق.
- مسارات الكتابة الواسعة تبقى مؤجلة حتى Sprint 2.
