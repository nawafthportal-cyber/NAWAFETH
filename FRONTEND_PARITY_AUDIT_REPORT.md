# FRONTEND_PARITY_AUDIT_REPORT

## A. Executive Summary
- **النتيجة العامة:** Dashboard V2 **غير متوافق بالكامل** مع Web + Mobile في وضعه الحالي.
- **نسبة التوافق التقديرية:** **63%** (Parity وظيفي/تدفقي عبر المنصات الثلاث).
- **الاستنتاج:** V2 ناضج كواجهة Backoffice حديثة، لكنه لا يحقق Parity كاملًا مع:
  - شاشة/شاشة للداشبورد القديم (Legacy Web Dashboard).
  - تدفقات Mobile (Flutter + mobile_web) التي تعمل أساسًا كسطح Client/Provider وليس Backoffice.
- **أهم الفجوات:**
  1. تعارض عقدي في وحدة `excellence` (موجودة في V2 وغير موجودة ضمن dashboard codes الرسمية في العقد/المهاجرات).
  2. اختلاف نطاق المنتج: V2 (Backoffice) مقابل Mobile/Web الحالية (Client/Provider).
  3. وجود صفحات Legacy حرجة غير ممثلة بالكامل في V2.
  4. اختلاف تسمية/دلالات الحالات بين Operational statuses والعروض التجارية في mobile/web.
  5. عدم تطابق RBAC عبر المنصات (Admin/Power/User/QA/Client في V2 مقابل Provider/Client mode في mobile/web).

---

## B. Module-by-Module Table

| Module | Dashboard V2 | Web | Mobile | Backend Contract | Status | Notes | Required Action |
|---|---|---|---|---|---|---|---|
| Auth | `dashboard-v2/login, otp, logout` | `dashboard/login, otp, logout` | `login + twofa` | متوافق من حيث وجود OTP + portal eligibility | PARTIAL | منطق المصادقة متقارب، لكن mobile ليس Backoffice RBAC. | توحيد مسار الدخول المرجعي حسب نوع السطح (Backoffice vs Client/Provider). |
| Home / Overview | بطاقات `NEW/IN_PROGRESS/RETURNED/CLOSED` + quick links | `dashboard/home` | `home` و`provider-dashboard` بطابع منتج | يعتمد operational statuses الرسمية | PARTIAL | الشاشة موجودة بكل سطح لكن الأهداف والبيانات مختلفة جذريًا. | تعريف IA رسمي: Home-Backoffice منفصل عن Home-Product. |
| Users / Access | `access/users list/detail` | `users + access profiles + audit log` | لا يوجد سطح إدارة مستخدمين Backoffice | `admin_control` + RBAC helpers | PARTIAL | V2 يغطي users الأساسي، لكن access profiles/audit (Legacy) غير مكافئة بالكامل؛ mobile غير موجود. | استكمال صفحات الإدارة الناقصة أو إعلان deprecation رسمي للقديم. |
| Unified Requests | list/detail + assign/status | `unified-requests list/detail` | `orders` (client/provider) وليست Unified inbox إدارية | Operational workflow رسمي | PARTIAL | يوجد تطابق جيد بين V2 وWeb الإداري، لكن mobile يعمل على تدفق Marketplace مختلف. | إنشاء mapping contract واضح بين UnifiedRequest وmobile order status groups. |
| Support | list/detail + assign/status | list/detail + create + إجراءات إضافية | `contact` (tickets create/reply) | `support` code + object-level policy | PARTIAL | parity جزئي؛ V2 لا يعكس كل surface القديم، mobile أقرب لبوابة العميل. | تحديد ما يبقى من شاشة دعم العميل خارج V2 وما يجب إتاحته إداريًا داخله. |
| Content | content home + blocks/docs/links + portfolio/spotlight | `content_management` + moderation | provider profile/portfolio (منتج) | `content` code | PARTIAL | V2 وLegacy قريبان إداريًا؛ mobile يركز على إنشاء محتوى المزود وليس moderation backoffice. | توثيق فصل مسؤوليات Content Admin vs Provider Content. |
| Moderation | list/detail + assign/status/decision | list/detail + actions | لا يوجد moderation backoffice مماثل | `moderation` code | PARTIAL | mobile لا يقدم نفس workflow الإشرافي الإداري. | لا يلزم دمج كامل للموبايل؛ يلزم توثيق scope boundary. |
| Reviews | list/detail + moderate/respond | list/detail + moderate/respond | provider reviews (سياق مختلف) | `reviews` code | PARTIAL | V2 وLegacy متقاربان، mobile ليس review moderation backoffice. | إبقاء mobile في نطاق product reviews فقط مع توضيح contract mapping. |
| Excellence | home/detail + approve/revoke | legacy excellence dashboard/detail | فقط عرض شارات ضمن profile/interactive | **غير موجود ضمن official dashboard codes** | MISMATCH | تعارض مباشر مع العقد النهائي والمهاجرة `0007`. | قرار معماري فوري: إضافة `excellence` للعقد والمهاجرة أو دمجها رسميًا تحت code معتمد. |
| Promo | requests/detail + inquiries + pricing + banners list | يغطي promo بشكل أوسع (`service_board`, `campaign_create`, banner CRUD) | provider promotion flow (طلب/متابعة) | `promo` code | PARTIAL | وحدة موجودة عبر المنصات لكن سلوك الاستخدام يختلف إداريًا/منتجيًا. | حسم features القديمة: إبقاؤها/استبدالها/تعطيلها رسميًا. |
| Verification | requests/detail + finalize/activate/requirement decision | requests + ops + verified badges actions | verification request/doc flow للمزود | `verify` code | PARTIAL | V2 يركز العمليات الإدارية الأساسية، legacy أوسع، mobile منتج. | توحيد شجرة verification surfaces وتحديد ما هو Ops-only. |
| Subscriptions | list/plans/request/account/payment detail + actions | legacy أوسع (ops, compare, checkout/success, renew/upgrade/cancel) | plans/summary وتدفقات منتج | `subs` code | PARTIAL | تكامل جزئي مع legacy، mobile ليس console تشغيليًا. | تقرير قرار: هل checkout/success تبقى في surface منفصل أم تُعاد في V2. |
| Extras | requests/detail + clients/catalog/finance + actions | ops/inquiries/requests/clients/catalog/finance | additional services purchases (product) | `extras` code | PARTIAL | V2 وLegacy قريبان نسبيًا، mobile product-centric. | توحيد terminology بين extra request operational وpurchase lifecycle. |
| Client Portal | home/requests/services/reports/account/payment/profile/settings | legacy `client_extras` (catalog/purchases/invoice) | شاشات عميل/مزود موزعة وليست portal إداري موحّد | `client_extras` code | PARTIAL | V2 يقدم بوابة أوسع من legacy والموبايل. | توحيد contract لرحلة العميل بين portal الإداري وmobile product views. |
| Analytics | overview/reports/exports | `analytics_insights` فقط | لا يوجد analytics dashboard مماثل | `analytics` code | MISSING | parity ثلاثي غير موجود فعليًا (mobile بلا مقابل، legacy محدود). | اعتماد analytics كـ Backoffice-only رسميًا أو بناء surface product analytics منفصل. |

---

## C. Screen-level Findings

### C1) Legacy Web Screens موجودة وغير مكافئة بالكامل في V2
- `dashboard/support/create/` (إنشاء تذكرة من الإدارة) غير ظاهر كـ screen مماثلة في V2.
- `dashboard/admin/access-profiles/*` و`dashboard/admin/audit-log/` غير مكافئة بنفس العمق في V2.
- `dashboard/promo/modules/<service_key>/` و`dashboard/promo/campaign/create/` غير مكافئة في V2.
- `dashboard/promo/banners/create|update|toggle|delete` موجودة في Legacy بينما V2 يركز list/عرض إداري أخف.
- `dashboard/verification/ops/` و`dashboard/verification/badges/*` غير مكافئة بنفس breadth في V2.
- `dashboard/subscriptions/ops/` و`checkout/success/renew/upgrade/cancel` غير ممثلة بنفس التغطية في V2.
- `dashboard/extras/ops/` وinquiry-centric flows في Legacy ليست ممثلة بنفس الشكل في V2.

### C2) Screens في V2 غير موجودة بشكل مباشر في Legacy
- `dashboard-v2/analytics/reports/` و`dashboard-v2/analytics/exports/` كتجميع حديث.
- `dashboard-v2/client-portal/profile|settings|reports|account-statement` كحزمة portal موحدة.

### C3) Mobile/Web Product Screens بدون مقابل إداري مباشر في V2
- Flutter/Mobile-web provider/client journeys (`provider-dashboard`, `orders`, `interactive`, `profile`, `search`, `chats`) لا تملك مقابلًا مباشرًا في V2 لأنها ليست Backoffice surfaces.
- شاشات mobile الخاصة بـ marketplace status groups (`new/in_progress/completed/cancelled`) ليست equivalent لشاشة Unified Requests الإدارية.

### C4) مستوى الثقة
- **High confidence** في Route/Screen coverage (تم الفحص من `urls.py`, templates, js, dart).
- **Medium confidence** في parity التفصيلي لبعض behavior الديناميكي المعتمد على payload API وقت التشغيل.

---

## D. RBAC Findings

- **Dashboard V2:** مطبق backend enforcement واضح (`has_dashboard_access`, `has_action_permission`, `can_access_object`) مع decorators وحواجز object-level.
- **Legacy Web Dashboard:** يعتمد نفس طبقة RBAC الخلفية بدرجة جيدة.
- **Mobile + mobile_web:** لا يطبق نموذج أدوار Backoffice (`ADMIN/POWER/USER/QA/CLIENT`) بنفس الشكل؛ يعتمد غالبًا `provider/client mode`.
- **نتيجة RBAC parity:** **PARTIAL** عبر المنصات الثلاث.
- **مخاطر اتساق:**
  - ما يراه/ينفذه `QA` و`POWER USER` في V2 ليس له تمثيل equivalent في mobile.
  - أي قرار “توحيد RBAC كامل” يحتاج فصلًا رسميًا بين Backoffice RBAC وProduct RBAC بدل محاولة مطابقة حرفية.

---

## E. Workflow Findings

- **Backoffice workflow (V2 + contract):** Operational transitions canonical (`NEW → IN_PROGRESS/RETURNED → CLOSED`) مع validation وسجلات.
- **Legacy Web:** متقارب غالبًا في المسارات الإدارية، لكن ما زال يحتوي تدفقات ops إضافية.
- **Mobile/Web Product:** يستخدم business workflows مختلفة حسب المجال (`pending_payment`, `active`, `expired`, `completed`, `cancelled`...).
- **النتيجة:** workflow parity عبر المنصات الثلاث **ليس كاملًا**؛ الموجود هو **تكامل domain-level** وليس parity حرفي.

---

## F. Naming & Contract Findings

1. **Mismatch Critical:** `excellence` مستخدم فعليًا في V2 (`urls/view_utils/views`) لكنه غير موجود ضمن:
   - `DASHBOARD_BACKEND_CONTRACT.md` (official codes)
   - `backend/apps/dashboard/contracts.py` (`OFFICIAL_DASHBOARD_CODES`)
   - `0007_finalize_dashboard_codes.py` rows الرسمية

2. **Naming divergence (متوقع جزئيًا لكن غير موحد توثيقيًا):**
   - Operational statuses الرسمية: `NEW/IN_PROGRESS/RETURNED/CLOSED`.
   - Product/mobile statuses كثيرة ومختلفة: `pending_payment`, `active`, `expired`, `completed`, `cancelled`.
   - يلزم mapping matrix موحد ومعلن بين “تشغيلي” و“تجاري”.

3. **Label consistency gaps:**
   - مزج عناوين إنجليزية/عربية عبر V2 والقديم والموبايل (`ACTIVE`, `OPS DONE`, `مغلق`, `completed`...).
   - قد يسبب ارتباكًا تشغيليًا للمستخدم متعدد القنوات.

4. **Source of Truth parity:**
   - Backoffice contract صحيح من حيث: module models = business truth، UnifiedRequest = aggregation.
   - لكن surfaces الأمامية لا تعرض دائمًا هذا الفصل بشكل موحد في التسمية والشرح.

---

## G. Final Decision

- **هل Dashboard V2 متوافق فعلاً مع Web + Mobile؟**
  - **لا، ليس بالكامل.** التوافق الحالي **جزئي (PARTIAL)** مع فجوات contract/scope/workflow واضحة.

- **هل يمكن اعتماده رسميًا كواجهة الإدارة المرجعية؟**
  - **نعم كمرجعية Backoffice فقط** بعد إغلاق فجوات parity الحرجة أدناه.
  - **لا كمرجعية موحدة لكل Web + Mobile product surfaces** بدون Phase Parity Fix مخصص.

- **ما الذي يجب تعديله قبل اعتماد التوافق النهائي؟**
  1. حسم `excellence` عقديًا (إضافته رسميًا أو إزالته/دمجه).
  2. اعتماد وثيقة Scope Boundary واضحة: Backoffice surfaces مقابل Product (Client/Provider) surfaces.
  3. تحديد مصير صفحات Legacy الإدارية غير المكافئة في V2 (إعادة بناء/إحالة/تعطيل رسمي).
  4. إنشاء Status Mapping Matrix موحد بين operational والبزنس statuses لكل منصة.
  5. توحيد قاموس labels/badges/actions عبر المنصات لتقليل الالتباس التشغيلي.

