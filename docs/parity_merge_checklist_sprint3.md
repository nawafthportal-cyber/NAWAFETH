# Sprint 3 Parity Merge Checklist

استخدم هذه القائمة عند أي PR يلمس backend APIs أو Flutter أو `mobile_web` في المسارات الحرجة.

- هل تغيّر payload لأي من العقود الموجودة تحت `docs/contracts/sprint2` أو `docs/contracts/sprint3`؟
- هل تغيّر payload لأي من العقود الموجودة تحت `docs/contracts/sprint4` للمسارات الحرجة مثل `unread_badges`؟
- إذا نعم: هل تم تحديث fixture أو إثبات التوافق الخلفي؟
- هل جرى التحقق من `auth`, `profile`, `orders`, `chat`, `notifications`, `plans`, `verification`, `promo`, `support` عند الحاجة؟
- هل تغيّرت تسمية status أو empty/error state في إحدى الواجهتين فقط؟
- هل التغيير يحتاج تحديث smoke checklist؟
- هل التغيير يحتاج ملاحظة واضحة في الـ PR description؟
