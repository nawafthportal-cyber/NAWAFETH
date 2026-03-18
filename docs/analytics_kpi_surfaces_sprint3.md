# Sprint 3 Analytics KPI Surfaces

تم رفع analytics من event collection إلى aggregate surfaces قابلة للاستخدام التشغيلي، مع الإبقاء على النطاق محدودًا وواضحًا.

## Aggregate models

- `ProviderDailyStats`
- `CampaignDailyStats`
- `SubscriptionDailyStats`
- `ExtrasDailyStats`

## KPI endpoints

- `GET /api/analytics/kpis/providers/`
- `GET /api/analytics/kpis/promo/`
- `GET /api/analytics/kpis/subscriptions/`
- `GET /api/analytics/kpis/extras/`

## Dashboard surface

- `GET /dashboard/analytics/insights/`

## Scope notes

- لا توجد dashboards ثقيلة فوق `raw events`.
- لا يوجد historical backfill ثقيل في Sprint 3.
- rebuild يتم يوميًا عبر task مجدولة ويمكن تشغيله يدويًا لنطاق محدد.
