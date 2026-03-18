# Sprint 2 Parity Contract Inventory

هذه القائمة baseline تشغيلية لمنع drift بين Flutter و`mobile_web`.

## Flows covered now

- Auth
  - `POST /api/accounts/otp/send/`
  - `POST /api/accounts/otp/verify/`
  - `GET /api/accounts/me/`
- Profile
  - `GET /api/accounts/me/`
  - `GET /api/providers/{id}/`
- Orders
  - `GET /api/marketplace/my/requests/`
  - `POST /api/marketplace/requests/create/`
- Chat
  - `POST /api/messaging/direct/thread/`
  - `GET /api/messaging/direct/thread/{id}/messages/`
- Plans / subscriptions
  - `GET /api/subscriptions/plans/`
  - `POST /api/subscriptions/subscribe/{plan_id}/`
- Verification
  - `GET /api/verification/my/pricing/`
  - `GET /api/verification/my/requests/`
- Promo
  - `GET /api/promo/active/`
  - `GET /api/promo/banners/home/`
- Support
  - `POST /api/support/tickets/create/`
  - `GET /api/support/tickets/my/`

## Source of truth

- response shape المرجعية المؤقتة: `docs/contracts/sprint2/*.json`
- أي PR يغير response payload لهذه المسارات يجب أن يحدّث fixture المرتبطة به
