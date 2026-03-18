# Sprint 1 Feature Flags

## FEATURE_MODERATION_CENTER
- الافتراضي: `False`
- الأثر: يخفي endpoints الموديريشن الجديدة بالكامل عند الإطفاء.

## FEATURE_MODERATION_DUAL_WRITE
- الافتراضي: `False`
- الأثر: محجوز لـ Sprint 2 عند ربط الموديريشن بالأنظمة الحالية.

## FEATURE_RBAC_ENFORCE
- الافتراضي: `False`
- الأثر: يبقي الصلاحيات الجديدة في وضع foundation دون hard enforcement على النظام القائم.

## RBAC_AUDIT_ONLY
- الافتراضي: `True`
- الأثر: يسمح ببناء policy classes الآن مع rollout محافظ.
