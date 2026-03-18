# Sprint 3 Parity Contract Inventory

هذه الإضافة تبني فوق baseline الخاصة بـ Sprint 2، وتركّز على تثبيت المسارات الحرجة التي قد تنحرف بين Flutter و`mobile_web`.

## Protected flows

- `auth`: `GET /api/accounts/me/`
- `profile`: provider detail / profile payloads
- `orders`: list + detail payloads
- `chat`: thread messages payload
- `notifications`: list + unread count
- `plans/subscriptions`: plans list + current subscription summary
- `verification`: request detail
- `promo`: active promo items / banners
- `support`: support ticket detail

## Rule

أي تغيير backend يلمس shape لأحد العقود أعلاه يجب أن يحدّث fixture المقابلة أو يوضح أن التغيير متوافق backward-compatible.

## Sprint 3 additions

- `docs/contracts/sprint3/notifications_list.json`
- `docs/contracts/sprint3/notifications_unread_count.json`
