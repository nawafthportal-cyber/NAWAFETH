# Sprint 2 Analytics Event Taxonomy

الهدف من هذه الطبقة هو تثبيت baseline موحدة للأحداث التجارية/التشغيلية دون بناء BI ثقيل.

## Server-side events

- `marketplace.request_created`
- `messaging.direct_thread_created`
- `messaging.thread_report_created`
- `promo.request_quoted`
- `promo.request_activated`
- `subscriptions.checkout_created`
- `subscriptions.activated`
- `extras.checkout_created`
- `extras.activated`
- `extras.credit_consumed`

## Client-side baseline events

- `provider.profile_view`
- `promo.banner_impression`
- `promo.banner_click`
- `promo.popup_open`
- `promo.popup_click`
- `search.result_click`

## Naming rules

- الصيغة المعتمدة: `domain.event_name`
- `channel` أحد: `server`, `flutter`, `mobile_web`
- `surface` يحدد نقطة الإطلاق مثل:
  - `marketplace.service_request_create`
  - `flutter.home.hero`
  - `mobile_web.search.banner`
- `object_type` و`object_id` يحددان الكيان التجاري المرتبط إن وُجد
- `dedupe_key` يستخدم فقط للأحداث المعرضة للتكرار مثل impressions/views

## Out of scope in Sprint 2

- daily aggregates الثقيلة
- KPI dashboards واسعة
- historical backfill
- event warehouse خارجي
