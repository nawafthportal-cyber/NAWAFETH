# تقرير المرحلة 1: الفحص واكتشاف النواقص
## PHASE 1 AUDIT REPORT – NAWAFETH Dashboard System

**التاريخ:** 2026-03-09  
**النطاق:** فحص كامل للمشروع مقابل الوثيقة المعتمدة  
**الحالة:** مكتمل

---

## 1. Dashboard Inventory (جرد اللوحات الموجودة)

### 1.1 لوحات الداشبورد المسجلة في النظام (جدول `backoffice.Dashboard`)

| الكود | الاسم | الحالة |
|-------|-------|--------|
| `analytics` | التحليلات والإحصاءات | ✅ فعّال |
| `content` | إدارة المحتوى والطلبات | ✅ فعّال |
| `billing` | الفواتير | ✅ فعّال |
| `support` | الدعم والمساعدة | ✅ فعّال |
| `verify` | التوثيق | ✅ فعّال |
| `excellence` | التميز | ✅ فعّال |
| `promo` | الإعلانات والترويج | ✅ فعّال |
| `subs` | الاشتراكات | ✅ فعّال |
| `extras` | الخدمات الإضافية | ✅ فعّال |
| `access` | إدارة الصلاحيات | ✅ فعّال |

### 1.2 مقارنة مع الوثيقة المعتمدة (8 لوحات مطلوبة)

| # | اللوحة المطلوبة (الوثيقة) | الكود الموجود | الحالة |
|---|--------------------------|--------------|--------|
| 1 | لوحة إدارة الصلاحيات وتقارير المنصة | `access` + `analytics` | ✅ موجودة (مقسمة على كودين) |
| 2 | فريق الدعم والمساعدة | `support` | ✅ موجودة |
| 3 | فريق إدارة المحتوى | `content` | ✅ موجودة (تشمل الطلبات + المراجعات + التميز) |
| 4 | فريق إدارة الإعلانات والترويج | `promo` | ✅ موجودة |
| 5 | فريق التوثيق | `verify` | ✅ موجودة |
| 6 | فريق إدارة الاشتراكات والترقية | `subs` | ✅ موجودة |
| 7 | فريق إدارة الخدمات الإضافية | `extras` | ✅ موجودة |
| 8 | لوحة تحكم العملاء للخدمات الإضافية | `extras_portal` (تطبيق مستقل) | ✅ موجودة |

**لوحات إضافية غير مذكورة في الوثيقة:**
- `billing` — لوحة الفواتير (موجودة كلوحة مستقلة)
- `excellence` — لوحة التميز (موجودة كلوحة مستقلة)

### 1.3 عدد الواجهات (Views) لكل لوحة

| الكود | عدد Views | عدد Templates | عدد Write Actions |
|-------|----------|---------------|-------------------|
| `analytics` | 3 | 3 | 0 |
| `content` | ~18 | 12 | ~10 |
| `billing` | 2 | 1 | 1 |
| `support` | 8 | 3 | 5 |
| `verify` | 12 | 4 | 5 |
| `promo` | 18 | 7 | 8 |
| `subs` | 20 | 9 | 10 |
| `extras` | 8 | 3 | 3 |
| `access` | 7 | 4 | 4 |
| `excellence` | 4 | 2 | 2 |
| **المجموع** | **~100** | **~52** | **~48** |

---

## 2. Teams / Roles / Permissions Inventory (جرد الأدوار والصلاحيات)

### 2.1 مستويات الصلاحية (AccessLevel)

| المستوى | الكود | الصلاحية | الموجود | مطابق للوثيقة |
|---------|-------|---------|---------|---------------|
| Admin | `admin` | وصول كامل لجميع اللوحات + كتابة | ✅ | ✅ |
| Power User | `power` | وصول كامل لجميع اللوحات + كتابة | ✅ | ✅ |
| User | `user` | وصول محدود للوحات المحددة + كتابة | ✅ | ✅ |
| QA | `qa` | عرض فقط (read-only) لجميع اللوحات المسموحة | ✅ | ✅ |
| Client | `client` | — | ✅ مسجل في `AccessLevel` | ⚠️ جزئي |

### 2.2 تحليل صلاحية Client

**الوثيقة تطلب:** Client يصل فقط للوحة الخدمات الإضافية.

**الواقع:**
- `AccessLevel.CLIENT` موجود في `backoffice.models` كخيار.
- **لا يوجد منطق في `access.py`** يقيّد Client على `extras` فقط.
- لوحة العملاء (`extras_portal`) هي تطبيق Django مستقل بـ auth منفصل (OTP + session) — **ليست جزءًا من نظام Dashboard RBAC**.
- ⚠️ **Client في Dashboard RBAC غير مفعّل وظيفيًا** — لا يوجد فرق بين Client و User في المنطق الحالي.

### 2.3 تعدد اللوحات لنفس المستخدم

| الميزة | الحالة |
|--------|--------|
| `allowed_dashboards` (ManyToMany) | ✅ موجود |
| Admin/Power يرى كل اللوحات تلقائيًا | ✅ موجود |
| User يرى فقط اللوحات المحددة | ✅ موجود |
| QA read-only | ✅ موجود |
| تعدد لوحات لنفس المستخدم | ✅ مدعوم بـ ManyToMany |

### 2.4 سلسلة حماية الصلاحيات

| الطبقة | آلية الحماية | الحالة |
|--------|-------------|--------|
| Login | `dashboard_login_required` + OTP | ✅ |
| Staff check | `staff_member_required` | ✅ |
| Dashboard access | `@dashboard_access_required(code)` | ✅ |
| Write protection | `@dashboard_access_required(code, write=True)` | ✅ |
| POST-only for writes | `@require_POST` | ✅ |
| Last-admin protection | في admin.py و views | ✅ |
| Expiry/Revoke | `expires_at` + `revoked_at` | ✅ |
| API level | `BackofficeAccessPermission` + per-module | ✅ |
| Object-level | `IsOwner*` permissions | ✅ |

### 2.5 أدوار المستخدم العامة (UserRole)

| الدور | الكود | الاستخدام |
|-------|-------|----------|
| Visitor | `visitor` | مستخدم غير مكتمل التسجيل |
| Phone Only | `phone_only` | سجّل برقم الهاتف فقط |
| Client | `client` | عميل يطلب خدمات |
| Provider | `provider` | مقدم خدمة |
| Staff | `staff` | موظف داخلي (Dashboard) |

---

## 3. Existing Models Mapping (خريطة النماذج لكل فريق)

### 3.1 لوحة إدارة الصلاحيات وتقارير المنصة (`access` + `analytics`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `User` | accounts | ✅ كامل |
| `UserAccessProfile` | backoffice | ✅ كامل |
| `Dashboard` | backoffice | ✅ كامل |
| `AuditLog` | audit | ✅ كامل |

### 3.2 فريق الدعم والمساعدة (`support`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `SupportTicket` | support | ✅ كامل |
| `SupportTeam` | support | ✅ كامل |
| `SupportComment` | support | ✅ كامل |
| `SupportAttachment` | support | ✅ كامل |
| `SupportStatusLog` | support | ✅ كامل |

### 3.3 فريق إدارة المحتوى (`content`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `SiteContentBlock` | content | ✅ كامل |
| `SiteLegalDocument` | content | ✅ كامل |
| `SiteLinks` | content | ✅ كامل |
| `Review` | reviews | ✅ كامل |
| `ExcellenceBadgeType` | excellence | ✅ كامل |
| `ExcellenceBadgeCandidate` | excellence | ✅ كامل |
| `ExcellenceBadgeAward` | excellence | ✅ كامل |
| `Category` / `SubCategory` | providers | ✅ كامل |
| `ServiceRequest` | marketplace | ✅ (مشتركة — تحت `content` كعرض) |
| `ProviderProfile` | providers | ✅ (مشتركة — تحت `content` كعرض) |

### 3.4 فريق إدارة الإعلانات والترويج (`promo`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `PromoRequest` | promo | ✅ كامل |
| `PromoRequestItem` | promo | ✅ كامل |
| `PromoAsset` | promo | ✅ كامل |
| `PromoAdPrice` | promo | ✅ (legacy — replaced by PromoPricingRule) |
| `PromoPricingRule` | promo | ✅ كامل |
| `HomeBanner` | promo | ✅ كامل |
| `PromoInquiryProfile` | promo | ✅ كامل |

### 3.5 فريق التوثيق (`verify`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `VerificationRequest` | verification | ✅ كامل |
| `VerificationDocument` | verification | ✅ كامل |
| `VerificationRequirement` | verification | ✅ كامل |
| `VerificationRequirementAttachment` | verification | ✅ كامل |
| `VerifiedBadge` | verification | ✅ كامل |

### 3.6 فريق إدارة الاشتراكات والترقية (`subs`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `SubscriptionPlan` | subscriptions | ✅ كامل |
| `Subscription` | subscriptions | ✅ كامل |
| `Invoice` | billing | ✅ (مشتركة) |
| `PaymentAttempt` | billing | ✅ (مشتركة) |

### 3.7 فريق إدارة الخدمات الإضافية (`extras`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `ExtraPurchase` | extras | ✅ كامل |
| `UnifiedRequest` | unified_requests | ✅ (مشتركة) |

### 3.8 لوحة تحكم العملاء للخدمات الإضافية (`extras_portal`)

| النموذج | التطبيق | الحالة |
|---------|---------|--------|
| `ExtrasPortalSubscription` | extras_portal | ✅ كامل |
| `ExtrasPortalFinanceSettings` | extras_portal | ✅ كامل |
| `ExtrasPortalScheduledMessage` | extras_portal | ✅ كامل |
| `ExtrasPortalScheduledMessageRecipient` | extras_portal | ✅ كامل |

### 3.9 مشتركة عبر اللوحات

| النموذج | التطبيق | يستخدمه |
|---------|---------|---------|
| `UnifiedRequest` | unified_requests | جميع اللوحات |
| `UnifiedRequestMetadata` | unified_requests | جميع اللوحات |
| `Invoice` | billing | verify, subs, promo, extras |
| `AuditLog` | audit | access |

---

## 4. Gap Analysis (تحليل الفجوات)

### 4.1 الموجود الكامل ✅

| الميزة | الحالة |
|--------|--------|
| نظام RBAC متعدد المستويات (Admin/Power/User/QA) | ✅ مكتمل |
| تعدد اللوحات لنفس المستخدم | ✅ مكتمل |
| QA read-only | ✅ مكتمل |
| حماية آخر Admin | ✅ مكتمل |
| OTP login للداشبورد | ✅ مكتمل |
| Audit logging | ✅ مكتمل |
| إدارة المستخدمين الداخليين | ✅ مكتمل |
| فريق الدعم (استقبال / نوع / أولوية / حالة / إحالة / تعليقات / إغلاق) | ✅ مكتمل |
| إدارة المحتوى الثابت + الروابط + الوثائق القانونية | ✅ مكتمل |
| إدارة التقييمات والمراجعات (moderation + management reply) | ✅ مكتمل |
| إدارة التميز وشارات التميز | ✅ مكتمل |
| طلبات الترويج (استقبال / تسعير / تفعيل / رفض) | ✅ مكتمل |
| إدارة المساحات الإعلانية (HomeBanner CRUD) | ✅ مكتمل |
| تسعير الخدمات الإعلانية (PromoPricingRule) | ✅ مكتمل |
| التوثيق (الشارة الزرقاء / الخضراء / بنود / اعتماد / رفض) | ✅ مكتمل |
| الاشتراكات (باقات / تفعيل / ترقية / تجديد / إلغاء) | ✅ مكتمل |
| الخدمات الإضافية (طلبات / تفعيل) | ✅ مكتمل |
| لوحة العملاء (تقارير / عملاء / مالية / تصدير) | ✅ مكتمل |
| نظام الفواتير والمدفوعات | ✅ مكتمل |
| تصدير البيانات (CSV/XLSX/PDF) | ✅ مكتمل |
| إدارة التصنيفات والتصنيفات الفرعية | ✅ مكتمل |
| إدارة مقدمي الخدمات | ✅ مكتمل |
| Unified Requests (تتبع موحد) | ✅ مكتمل |

### 4.2 الموجود الجزئي ⚠️

| الميزة | ما هو موجود | ما ينقص |
|--------|------------|---------|
| **صلاحية Client في Dashboard** | الكود `CLIENT` موجود في `AccessLevel` | لا يوجد منطق تقييد Client على `extras` فقط في `access.py` |
| **تنبيهات قبل الانتهاء (Verification)** | `expires_at` موجود في `VerifiedBadge` | لا يوجد Celery task للتنبيه قبل الانتهاء |
| **تنبيهات قبل الانتهاء (Subscription)** | `reminder_schedule_hours` محدد في الباقة | لا يوجد Celery task فعلي لإرسال التنبيهات |
| **انتهاء تلقائي للحملات (Promo)** | `end_at` موجود في `PromoRequest` | لا يوجد Celery task لإكمال الحملات المنتهية تلقائيًا |
| **التكليف في الترويج** | `assigned_to` + `ops_status` موجود | لا يوجد تدفق تكليف فريق/موظف متقدم |
| **لوحة العملاء — الفواتير** | التقارير المالية + كشف الحساب | لا توجد واجهة فواتير مفصلة في extras_portal |
| **لوحة العملاء — المدفوعات** | — | لا توجد واجهة مدفوعات في extras_portal |
| **لوحة العملاء — بيانات الدفع الإلكتروني** | FinanceSettings (bank) | لا توجد بيانات دفع إلكتروني (بطاقات/محافظ) |
| **بيانات الحساب البنكي للخدمات الإضافية (Dashboard)** | — | لوحة الداشبورد `extras` لا تعرض finance settings |
| **إدارة الخدمات الممنوعة** | `PROHIBITED_SERVICES` في `LegalDocumentType` | يُدار كوثيقة قانونية فقط — لا توجد قائمة منفصلة قابلة للفلترة |
| **الرعاية (Sponsorship)** | `PromoRequestItem.sponsor_name/url/months` | لا توجد واجهة dashboard مخصصة للرعاية |

### 4.3 الناقص ❌

| الميزة | التفاصيل |
|--------|---------|
| **إعدادات مركزية قابلة للإدارة من Admin** | لا يوجد نموذج `SystemSettings` أو `PlatformConfig` لإدارة القيم المشتركة |
| **انتهاء تلقائي لحملات الترويج** | لا يوجد Celery task `promo.auto_complete_expired` |
| **تنبيهات قبل انتهاء التوثيق** | لا يوجد Celery task `verification.send_expiry_reminders` |
| **تنبيهات قبل انتهاء الاشتراك** | لا يوجد Celery task `subscriptions.send_renewal_reminders` |
| **IBAN/كشف حساب في لوحة الخدمات الإضافية (Dashboard)** | لوحة `extras` لا تعرض البيانات المالية لمقدم الخدمة |
| **إدارة العملاء في لوحة الخدمات الإضافية (Dashboard)** | لوحة `extras` لا تعرض قائمة عملاء مقدم الخدمة |
| **تقرير الشكاوى كمحتوى** | الشكاوى تذهب لـ `support` — لا يوجد ربط مع فريق المحتوى |
| **Client-scoped Dashboard RBAC** | لا يوجد منطق يقيّد Client على `extras` فقط |

---

## 5. Hardcoded Values Audit (تدقيق القيم الثابتة)

### 5.1 🔴 حرجة — يجب نقلها إلى Admin

| القيمة | الموقع | القيمة الحالية |
|--------|--------|---------------|
| أسعار الباقات | `subscriptions/bootstrap.py` | Basic=0, Riyadi=199, Pro=999 SAR |
| رسوم التوثيق الأزرق | `subscriptions/bootstrap.py` | 100/50/0 SAR |
| رسوم التوثيق الأخضر | `subscriptions/bootstrap.py` | 100/50/0 SAR |
| مدة تأخير الرؤية التنافسية | `subscriptions/bootstrap.py` | 72/24/0 ساعة |
| حد صور البانر | `subscriptions/bootstrap.py` | 1/3/10 |
| حصة المحادثات المباشرة | `subscriptions/bootstrap.py` | 3/10/50 |
| SLA الدعم | `subscriptions/bootstrap.py` | 120/48/5 ساعة |
| حد رفع الملفات | `subscriptions/bootstrap.py` + `features/upload_limits.py` | 10/20/100 MB |
| أسعار الترويج (29 قاعدة) | `promo/services.py` | 100–12,000 SAR |
| حد حجم الملف | `promo/validators.py` | 100 MB |

**ملاحظة:** أسعار الترويج (`PromoPricingRule`) تُحفظ في قاعدة البيانات ✅ لكن القيم الافتراضية hardcoded في `bootstrap_promo_pricing()`.

**ملاحظة:** أسعار الباقات (`SubscriptionPlan`) تُحفظ في قاعدة البيانات ✅ لكن القيم الافتراضية hardcoded في `bootstrap.py`.

### 5.2 🟠 عالية — يُفضّل نقلها

| القيمة | الموقع | القيمة الحالية |
|--------|--------|---------------|
| مدة الاشتراك السنوي | `subscriptions/offers.py` | 365 يوم |
| مدة الاشتراك الشهري | `subscriptions/offers.py` | 30 يوم |
| جدول التذكيرات | `subscriptions/bootstrap.py` | [24], [24,120], [24,120,240] ساعة |
| نسبة الضريبة (VAT) | `billing/serializers.py` | 15% |
| نسبة ضريبة الترويج | `promo/services.py` (settings) | 15% |
| حدود التصدير | `extras_portal/views.py` | PDF=200, XLSX=2000 صف |
| معايير شارة التميز | `excellence/selectors.py` | rating≥4.5, orders≥5, top 100 |
| دورة مراجعة التميز | `excellence/services.py` | 90 يوم × 365 يوم نافذة |
| مدة خدمة إضافية | `extras/services.py` | 30/7 يوم |
| ضريبة التوثيق | `verification/services.py` | 0% (inclusive) |
| عملة التوثيق | `verification/services.py` | SAR |
| OTP bypass | `dashboard/auth_views.py` + `extras_portal/views.py` | `True` (dev mode) |

### 5.3 🟡 متوسطة

| القيمة | الموقع |
|--------|--------|
| حدود حقول النص (200/300/500) | عبر عدة ملفات |
| ترتيب وأوزان التصنيف | providers/models.py |
| Labels عربية | عبر عدة ملفات |
| أنواع الخدمات الممنوعة | content/models.py |

### 5.4 ما هو قابل للتعديل حاليًا من Admin ✅

| القيمة | آلية التعديل |
|--------|-------------|
| أسعار الباقات ومزاياها | `SubscriptionPlan` via Django Admin (custom form) |
| قواعد تسعير الترويج | `PromoPricingRule` via Django Admin + Dashboard |
| أنواع شارات التميز | `ExcellenceBadgeType` via Django Admin |
| محتوى الموقع | `SiteContentBlock` via Dashboard |
| الوثائق القانونية | `SiteLegalDocument` via Dashboard |
| روابط الموقع | `SiteLinks` via Dashboard |
| فرق الدعم | `SupportTeam` via Django Admin |
| لوحات الداشبورد | `Dashboard` via Django Admin |
| بانرات الصفحة الرئيسية | `HomeBanner` via Dashboard |
| التصنيفات | `Category`/`SubCategory` via Dashboard |

---

## 6. Risks / Conflicts / Duplications (المخاطر والتعارضات)

### 6.1 مخاطر معمارية

| # | المخاطرة | الخطورة | التفاصيل |
|---|---------|---------|---------|
| R1 | OTP bypass hardcoded to `True` | 🔴 عالية | كلا البوابتين (Dashboard + extras_portal) تقبل أي كود OTP — يجب ربطها بـ `settings.DEBUG` أو `settings.DASHBOARD_OTP_BYPASS` |
| R2 | لا يوجد نموذج إعدادات مركزية | 🟠 عالية | القيم التجارية متفرقة عبر bootstrap/services/settings — يجب نموذج `PlatformConfig` singleton |
| R3 | Client AccessLevel غير مفعّل | 🟡 متوسطة | `CLIENT` موجود كخيار لكن لا يوجد منطق تقييد في `access.py` |
| R4 | لا يوجد Celery tasks للتنبيهات | 🟡 متوسطة | انتهاء التوثيق/الاشتراك/الحملات بدون تنبيه مسبق |
| R5 | `extras_portal` auth منفصل تمامًا | 🟡 متوسطة | نظام auth مستقل (session-based) — لا يستخدم Dashboard RBAC |

### 6.2 تكرار (Duplications)

| # | التكرار | التفاصيل |
|---|---------|---------|
| D1 | نمط Permission متكرر | 5 ملفات permissions.py بنفس النمط (`IsOwnerOrBackoffice*`) — يمكن توحيدها في base class |
| D2 | OTP verification منفصلة | `dashboard/auth.py` و `extras_portal/auth.py` — نفس المنطق مكرر |
| D3 | Export utilities | `dashboard/exports.py` و `extras_portal/views.py` — نفس منطق XLSX/PDF مكرر |
| D4 | `PromoAdPrice` legacy | `PromoAdPrice` موجود بجانب `PromoPricingRule` — يبدو أنه legacy |

### 6.3 تعارضات محتملة

| # | التعارض | التفاصيل |
|---|--------|---------|
| C1 | `content` dashboard overloaded | لوحة `content` تشمل: الطلبات + مقدمي الخدمات + الخدمات + التصنيفات + المحتوى + المراجعات — حمل كبير على كود واحد |
| C2 | Billing مشتركة | الفواتير تخدم: verify + subs + promo + extras — لا يوجد فصل dashboard-level |
| C3 | SupportTicket متعددة الأنواع | `SupportTicket.ticket_type` يُستخدم كـ inquiry لكل الفرق (VERIFY/SUBS/ADS/EXTRAS) |

---

## 7. Recommended Build Order (ترتيب البناء المقترح)

### المنطق:

1. **الأساس المشترك أولًا** — RBAC + إعدادات مركزية + Client scope + تنبيهات
2. **اللوحات بترتيب الاعتمادية** — الأقل اعتمادًا على غيره أولًا
3. **تجنب التداخل** — لوحة واحدة في كل مرحلة

### الترتيب:

| المرحلة | المحتوى | السبب |
|---------|---------|-------|
| **2** | تثبيت الأساس المشترك | RBAC + PlatformConfig + Client scope + Celery tasks أساسية |
| **3** | لوحة إدارة الصلاحيات وتقارير المنصة | أساسية — تُدير كل اللوحات الأخرى |
| **4** | فريق الدعم والمساعدة | مستقل — لا يعتمد على غيره |
| **5** | فريق إدارة المحتوى | يعتمد على providers/reviews/excellence |
| **6** | فريق إدارة الإعلانات والترويج | يعتمد على billing + promo pricing |
| **7** | فريق التوثيق | يعتمد على billing + subscription fees |
| **8** | فريق إدارة الاشتراكات والترقية | يعتمد على billing + plans |
| **9** | فريق إدارة الخدمات الإضافية | يعتمد على billing + unified_requests |
| **10** | لوحة تحكم العملاء للخدمات الإضافية | يعتمد على extras + extras_portal |

---

## 8. ملخص الأرقام

| المقياس | القيمة |
|---------|--------|
| إجمالي التطبيقات (apps) | 24 |
| التطبيقات ذات النماذج | 18 |
| إجمالي النماذج (Models) | ~60+ |
| إجمالي Views في Dashboard | ~100 |
| إجمالي Templates | 52 |
| لوحات Dashboard مسجلة | 10 |
| لوحات مطلوبة في الوثيقة | 8 |
| مستويات صلاحية | 5 (Admin/Power/User/QA/Client) |
| قواعد تسعير ترويج | 29 |
| عدد Celery Tasks | 5 |
| عناصر hardcoded حرجة | ~15 |
| عناصر hardcoded عالية | ~12 |
| نقص كامل (Missing) | 8 عناصر |
| نقص جزئي (Partial) | 11 عنصر |
| نسبة التغطية الإجمالية | ~75-80% |

---

## 9. قرارات مطلوبة قبل البدء

| # | القرار | التفاصيل |
|---|--------|---------|
| Q1 | هل يجب دمج `extras_portal` auth مع Dashboard RBAC؟ | حاليًا نظامان منفصلان |
| Q2 | هل `billing` تبقى لوحة مستقلة أم تندمج مع كل فريق؟ | حاليًا لوحة مستقلة |
| Q3 | هل `excellence` تبقى لوحة مستقلة أم تندمج مع `content`؟ | حاليًا لوحة مستقلة |
| Q4 | هل تُقسم لوحة `content` إلى أقسام فرعية؟ | حمل كبير (طلبات + مقدمي + تصنيفات + محتوى + مراجعات) |
| Q5 | ما هي مدة صلاحية التوثيق الافتراضية؟ | غير محددة في الكود — يجب تحديدها لبناء التنبيهات |
| Q6 | هل المدفوعات الإلكترونية (بطاقات/محافظ) مطلوبة في extras_portal الآن؟ | الوثيقة تذكرها لكن لا يوجد provider فعلي |

---

**انتهى تقرير المرحلة 1. جاهز للانتقال إلى المرحلة 2 بعد مراجعة التقرير والإجابة على القرارات المطلوبة.**
