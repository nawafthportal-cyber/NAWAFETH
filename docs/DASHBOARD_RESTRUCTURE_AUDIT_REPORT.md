# تقرير تدقيق وتحليل إعادة هيكلة لوحة التحكم
# Nawafeth Dashboard Restructuring — Phase 1 Audit Report

**التاريخ:** 2026-03-18  
**الإصدار:** 1.0  
**النوع:** تقرير تحليلي تأسيسي — Phase 1 (Audit & Architecture Decision)

---

## جدول المحتويات

1. [Executive Summary](#1-executive-summary)
2. [Current State Audit](#2-current-state-audit)
3. [Gap Analysis](#3-gap-analysis)
4. [Reuse / Refactor / Replace Matrix](#4-reuse--refactor--replace-matrix)
5. [Proposed Django Architecture](#5-proposed-django-architecture)
6. [Pricing & Tax Admin Design](#6-pricing--tax-admin-design)
7. [Step-by-step Execution Plan](#7-step-by-step-execution-plan)
8. [Risks and Migration Notes](#8-risks-and-migration-notes)

---

## 1. Executive Summary

### القرار الهندسي العام

**التوصية: Refactor التدريجي وليس إعادة البناء من الصفر.**

بعد فحص شامل للبنية الحالية (25 تطبيق Django، 100+ نموذج، 58 قالب لوحة تحكم، نظام RBAC مبني مسبقاً)، الخلاصة هي:

| الجانب | الحالة | القرار |
|--------|--------|--------|
| نظام الصلاحيات (RBAC) | مبني بنسبة ~85% | **Refactor** — يحتاج إضافة طبقة "صلاحية الرؤية vs التنفيذ" + ربط متعدد اللوحات |
| لوحات التحكم الداخلية | مبنية بنسبة ~70% | **Refactor + Extend** — 7 من 8 لوحات موجودة جزئياً |
| نظام الطلبات الموحد | مبني بنسبة ~80% | **Refactor** — `UnifiedRequest` موجود، يحتاج توحيد الأكواد |
| التسعير والضريبة | مبني بنسبة ~45% | **Refactor + New Modules** — `PlatformConfig` + `PromoPricingRule` موجودان، لكن النظام مفتت |
| لوحة العميل (بوابة الخدمات الإضافية) | مبنية بنسبة ~60% | **Refactor** — `extras_portal` موجود لكنه مرتبط بالمزود وليس العميل |
| التقارير والتصدير | مبنية بنسبة ~65% | **Extend** — أساسيات التحليلات موجودة |

**الخلاصة:** ~60-70% من البنية المطلوبة موجود فعلاً. الحل الأمثل هو Refactor مؤسسي منظم وليس هدم وإعادة بناء.

---

## 2. Current State Audit

### 2.1 التطبيقات الموجودة (25 تطبيق)

| # | التطبيق | الوظيفة | عدد النماذج | حالة النضج |
|---|---------|---------|-------------|------------|
| 1 | `accounts` | المستخدمين، OTP، المحفظة، المصادقة البيومترية | 5 | ✅ ناضج |
| 2 | `providers` | ملفات المزودين، الخدمات، المتابعة | 12 | ✅ ناضج |
| 3 | `marketplace` | طلبات الخدمة، العروض، الإرسال | 6 | ✅ ناضج |
| 4 | `billing` | الفواتير، المدفوعات، Webhooks | 4 | ✅ ناضج |
| 5 | `subscriptions` | خطط الاشتراك، الاشتراكات الفعالة | 2 | ✅ ناضج |
| 6 | `verification` | طلبات التوثيق، الشارات، المستندات | 5 | ✅ ناضج |
| 7 | `promo` | الحملات الإعلانية، التسعير، البنرات | 7 | ✅ ناضج |
| 8 | `support` | تذاكر الدعم، الفرق، التعليقات | 5 | ✅ ناضج |
| 9 | `content` | محتوى الموقع، الوثائق القانونية، الروابط | 3 | ✅ ناضج |
| 10 | `moderation` | حالات الإشراف، القرارات | 3 | ✅ ناضج |
| 11 | `excellence` | شارات التميز، المرشحين، الجوائز | 3 | ✅ ناضج |
| 12 | `reviews` | المراجعات والتقييمات | 1 | ✅ ناضج |
| 13 | `messaging` | محادثات مباشرة وسياقية | 4 | ✅ ناضج |
| 14 | `notifications` | الإشعارات، تفضيلات الإشعار، DeviceToken | 4 | ✅ ناضج |
| 15 | `analytics` | تتبع الأحداث، إحصاءات يومية | 3 | ✅ ناضج |
| 16 | `audit` | سجل التدقيق | 2 | ✅ ناضج |
| 17 | `core` | إعدادات المنصة (PlatformConfig) | 2 | ✅ ناضج |
| 18 | `backoffice` | RBAC، لوحات التحكم، الصلاحيات | 3 | ⚠️ يحتاج تعزيز |
| 19 | `dashboard` | واجهات لوحات التحكم HTML | 0 (views only) | ⚠️ يحتاج إعادة هيكلة |
| 20 | `extras` | الخدمات الإضافية (المشتريات) | 1 | ⚠️ أساسي |
| 21 | `extras_portal` | بوابة مزود الخدمات الإضافية | 3 | ⚠️ مبني للمزود وليس العميل |
| 22 | `unified_requests` | الطلبات الموحدة | 1 | ⚠️ يحتاج توسيع |
| 23 | `features` | أعلام الميزات | 0 | ✅ خدمات فقط |
| 24 | `mobile_web` | واجهات PWA | 0 (views only) | ✅ ناضج |
| 25 | `uploads` | إدارة الملفات | — | ✅ خدمي |

### 2.2 النماذج الحالية — جرد كامل

#### نماذج الحسابات والهوية
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `User` | accounts | مستخدم مبني على الهاتف، `role_state`: visitor/phone_only/client/provider/staff |
| `Wallet` | accounts | محفظة المستخدم (1:1) |
| `OTP` | accounts | رمز التحقق لمرة واحدة |
| `BiometricToken` | accounts | تسجيل بيومتري |

#### نماذج المزودين والسوق
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `Category` / `SubCategory` | providers | تصنيفات الخدمات |
| `ProviderProfile` | providers | ملف المزود الشامل مع التقييم والموقع |
| `ProviderService` | providers | خدمات المزود مع التسعير |
| `ProviderPortfolioItem/Like/Save` | providers | معرض الأعمال |
| `ProviderSpotlightItem/Like/Save` | providers | لمحات المزود |
| `ProviderFollow/Like` | providers | المتابعة والإعجاب |
| `ServiceRequest` | marketplace | طلب الخدمة الأساسي |
| `Offer` | marketplace | عروض المزودين |
| `ServiceRequestDispatch` | marketplace | نظام الإرسال المتدرج |

#### نماذج الفوترة والمالية
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `Invoice` | billing | فاتورة عامة مع VAT |
| `InvoiceLineItem` | billing | بنود الفاتورة |
| `PaymentAttempt` | billing | محاولات الدفع |
| `WebhookEvent` | billing | أحداث webhook |

#### نماذج الاشتراكات
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `SubscriptionPlan` | subscriptions | خطة اشتراك مع features JSONField |
| `Subscription` | subscriptions | اشتراك مستخدم فعال |

#### نماذج التوثيق
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `VerificationRequest` | verification | طلب توثيق مع سير عمل كامل |
| `VerificationDocument` | verification | مستند مرفق |
| `VerificationRequirement` | verification | متطلب توثيق مع قرار فردي |
| `VerificationRequirementAttachment` | verification | مرفق المتطلب |
| `VerifiedBadge` | verification | شارة توثيق فعالة |

#### نماذج الإعلانات
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `PromoRequest` | promo | طلب حملة إعلانية |
| `PromoRequestItem` | promo | بند خدمة إعلانية |
| `PromoAsset` | promo | ملف وسائط إعلاني |
| `PromoAdPrice` | promo | أسعار ثابتة حسب نوع الإعلان |
| `PromoPricingRule` | promo | قواعد تسعير مرنة |
| `HomeBanner` | promo | بنرات الصفحة الرئيسية |
| `PromoInquiryProfile` | promo | ربط استفسار بحملة |

#### نماذج الخدمات الإضافية
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `ExtraPurchase` | extras | عملية شراء خدمة إضافية |
| `ExtrasPortalSubscription` | extras_portal | اشتراك مزود في البوابة |
| `ExtrasPortalFinanceSettings` | extras_portal | إعدادات مالية للمزود |
| `ExtrasPortalScheduledMessage` | extras_portal | رسائل مجدولة |

#### نماذج الدعم والإشراف
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `SupportTeam` | support | فريق الدعم |
| `SupportTicket` | support | تذكرة دعم |
| `SupportAttachment` / `SupportComment` | support | مرفقات وتعليقات |
| `ModerationCase` | moderation | حالة إشراف |
| `ModerationActionLog` / `ModerationDecision` | moderation | سجل الإجراءات والقرارات |

#### نماذج التميز
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `ExcellenceBadgeType` | excellence | نوع شارة تميز |
| `ExcellenceBadgeCandidate` | excellence | مرشح للتميز |
| `ExcellenceBadgeAward` | excellence | جائزة تميز |

#### نماذج RBAC والتحكم
| النموذج | التطبيق | الوصف |
|---------|---------|-------|
| `Dashboard` | backoffice | كتالوج لوحات التحكم |
| `AccessPermission` | backoffice | صلاحيات دقيقة |
| `UserAccessProfile` | backoffice | ملف صلاحيات المستخدم |
| `PlatformConfig` | core | إعدادات المنصة المركزية (Singleton) |
| `AuditLog` / `EventLog` | audit | سجل التدقيق |

### 2.3 الفيوز (Views)

#### API Views (REST — للجوال والويب)
| التطبيق | عدد الـ Views | النوع |
|---------|--------------|-------|
| accounts | 9 | OTP، ملف شخصي، بيومتري، محفظة |
| billing | 6 | فواتير، مدفوعات، webhooks |
| marketplace | 6 | طلبات خدمة، عروض |
| verification | 10 | طلبات توثيق، مستندات، backoffice |
| promo | 8 | حملات، استفسارات، backoffice |
| support | 6 | تذاكر دعم |
| moderation | 8 | حالات إشراف، قرارات |
| excellence | 6 | شارات، مرشحين |
| subscriptions | 4 | خطط، اشتراكات |
| extras | 4 | خدمات إضافية |
| content | 2 | محتوى الموقع |
| analytics | 10 | KPIs، تصدير |
| backoffice | 4 | RBAC API |

#### Dashboard Views (HTML — لوحة التحكم الداخلية)
| القسم | عدد الـ Views | الوظيفة |
|-------|--------------|---------|
| Auth | 3 | تسجيل دخول OTP، تسجيل خروج |
| الرئيسية | 1 | لوحة البلاطات الرئيسية |
| الطلبات الموحدة | 2 | قائمة + تفاصيل |
| المزودين | 3 | قائمة + تفاصيل + خدمات |
| الفوترة | 2 | فواتير + تغيير حالة |
| الدعم | 8 | تذاكر + تعليقات + إنشاء + حذف محتوى مبلغ عنه |
| التوثيق | 10 | طلبات + مستندات + متطلبات + شارات + تفعيل + تجديد |
| الإعلانات | 12 | حملات + تسعير + بنرات + لوحة خدمة + استفسارات |
| المحتوى | 6 | محتوى + وثائق + روابط + إشراف المعرض |
| المراجعات | 4 | قائمة + تفاصيل + إشراف + رد الإدارة |
| الإشراف | 5 | حالات + تعيين + حالة + قرار |
| التميز | 4 | لوحة + مرشح + موافقة + إلغاء |
| التحليلات | 6 | رؤى + KPIs حسب القسم + تصدير |
| الاشتراكات | 4+ | قوائم + عمليات |
| الخدمات الإضافية | 4+ | قوائم + عمليات + عملاء |
| المستخدمين | 4+ | قوائم + تفاصيل + ملفات صلاحيات |

#### بوابة الخدمات الإضافية (Extras Portal)
| القسم | عدد الـ Views | الوظيفة |
|-------|--------------|---------|
| Auth | 3 | تسجيل دخول OTP |
| التقارير | 3 | لوحة + PDF + XLSX |
| المالية | 3 | قائمة + PDF + XLSX |
| العملاء | 1 | قائمة عملاء |
| الفواتير | 1 | تفاصيل فاتورة |

### 2.4 هيكل URLs

```
/admin-panel/          → Django Admin
/api/
  ├── accounts/        → OTP، ملف شخصي، مصادقة
  ├── providers/       → ملفات المزودين
  ├── marketplace/     → طلبات الخدمة
  ├── messaging/       → المحادثات
  ├── notifications/   → الإشعارات
  ├── reviews/         → المراجعات
  ├── content/         → محتوى الموقع
  ├── moderation/      → الإشراف
  ├── excellence/      → التميز
  ├── billing/         → الفواتير
  ├── verification/    → التوثيق
  ├── promo/           → الإعلانات
  ├── subscriptions/   → الاشتراكات
  ├── extras/          → الخدمات الإضافية
  ├── features/        → أعلام الميزات
  ├── analytics/       → التحليلات
  ├── support/         → الدعم
  ├── backoffice/      → RBAC API
  └── core/            → عدادات عامة
/dashboard/            → لوحة التحكم الداخلية (HTML)
/portal/extras/        → بوابة المزود
/mobile-web/           → PWA
/healthz/              → Health checks
```

### 2.5 نظام الصلاحيات الحالي

#### طبقة 1: Role State (accounts)
```
UserRole: visitor → phone_only → client → provider → staff
```
- تستخدم في API لفرض الحد الأدنى من الدور المطلوب
- `IsAtLeastClient`, `IsAtLeastProvider` — DRF Permission classes

#### طبقة 2: RBAC (backoffice)
```
AccessLevel: admin(99) → power → user → qa(read-only) → client(portal-only)
```
- `Dashboard` model: كتالوج لوحات التحكم المتاحة
- `AccessPermission` model: صلاحيات دقيقة لكل إجراء
- `UserAccessProfile`: ملف صلاحيات 1:1 مع المستخدم
  - M2M → Dashboard (اللوحات المسموحة)
  - M2M → AccessPermission (الصلاحيات الممنوحة)
  - expires_at / revoked_at

#### طبقة 3: Policy Engines (backoffice/policies.py)
- 8 محركات سياسة لعمليات حساسة:
  - `AnalyticsExportPolicy`
  - `ContentHideDeletePolicy`
  - `ExtrasManagePolicy`
  - `PromoQuoteActivatePolicy`
  - `SubscriptionManagePolicy`
  - `SupportAssignPolicy`
  - `SupportResolvePolicy`
  - `VerificationFinalizePolicy`

#### طبقة 4: Feature Flags
- `FEATURE_RBAC_ENFORCE`: تفعيل/تعطيل RBAC
- `RBAC_AUDIT_ONLY`: وضع التدقيق (سجل بدون حظر)

#### لوحات التحكم المسجلة حالياً (Dashboard records)
| الكود | الاسم العربي | ترتيب |
|-------|-------------|-------|
| `support` | الدعم والمساعدة | 10 |
| `content` | إدارة المحتوى | 20 |
| `moderation` | مركز الإشراف | 25 |
| `promo` | الإعلانات والترويج | — |
| `verify` | التوثيق | — |
| `subs` | الاشتراكات | — |
| `extras` | الخدمات الإضافية | — |
| `excellence` | إدارة التميز للمختصين | 45 |
| `analytics` | التحليلات | — |
| `billing` | الفوترة | — |
| `access` | صلاحيات التشغيل | — |
| `features` | أعلام الميزات | — |

#### الصلاحيات الدقيقة المسجلة (AccessPermission records)
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `moderation.assign` | تعيين حالات الإشراف | moderation |
| `moderation.resolve` | حل حالات الإشراف | moderation |
| `content.hide_delete` | إخفاء/حذف محتوى | content |
| `support.assign` | تعيين تذاكر الدعم | support |
| `support.resolve` | حل تذاكر الدعم | support |
| `promo.quote_activate` | تسعير وتفعيل الحملات | promo |
| `verification.finalize` | إنهاء طلبات التوثيق | verify |
| `analytics.export` | تصدير التحليلات | analytics |
| `reviews.moderate` | إدارة المراجعات | — |
| `subscriptions.manage` | إدارة الاشتراكات | subs |
| `extras.manage` | إدارة الخدمات الإضافية | extras |

### 2.6 التسعير والضريبة — الوضع الحالي

#### مصادر التسعير الحالية:

**1. PlatformConfig (Singleton — Django Admin)**
```python
vat_percent = 15.00%           # ضريبة القيمة المضافة العامة
promo_vat_percent = 15.00%     # VAT خاص بالإعلانات
promo_base_prices = JSONField  # أسعار أساسية حسب نوع الإعلان
promo_position_multipliers = JSONField  # مضاعفات حسب الموضع
promo_frequency_multipliers = JSONField # مضاعفات حسب التكرار
```

**2. PromoPricingRule (Django Admin)**
```python
code, service_type, title, unit, frequency, search_position,
message_channel, amount, is_active, sort_order
```
- نظام تسعير مرن للإعلانات مع قواعد متعددة

**3. PromoAdPrice (Django Admin)**
```python
ad_type (unique), price_per_day, is_active
```
- أسعار ثابتة مبسطة حسب نوع الإعلان (legacy)

**4. SubscriptionPlan (Django Admin)**
```python
price, verification_blue_fee, verification_green_fee
features (JSONField), feature_bullets (JSONField)
```
- أسعار مضمنة في الخطة مباشرة

**5. SubscriptionPlan.verification_*_fee**
- رسوم التوثيق مرتبطة بخطة الاشتراك

**6. PlatformConfig.extras_* settings**
```python
extras_default_duration_days = 30
extras_short_duration_days = 7
extras_currency = "SAR"
```
- إعدادات أساسية فقط — **لا يوجد كتالوج أسعار للخدمات الإضافية**

### 2.7 صفحات التقارير الحالية

| الصفحة | المسار | البيانات |
|--------|--------|---------|
| Analytics Insights | `/dashboard/analytics/insights/` | KPIs عامة + رسوم بيانية |
| Provider KPIs | عبر API | أداء المزود |
| Promo KPIs | عبر API | أداء الحملات |
| Subscription KPIs | عبر API | إحصاءات الاشتراكات |
| Extras KPIs | عبر API | إحصاءات الخدمات الإضافية |
| Revenue Daily | عبر API | الإيرادات اليومية |
| Revenue Monthly | عبر API | الإيرادات الشهرية |
| Requests Breakdown | عبر API | تحليل الطلبات |
| CSV/XLSX/PDF Exports | عبر views | تصدير متعدد الصيغ |

---

## 3. Gap Analysis

### 3.1 اللوحات المطلوبة vs الموجود

| # | اللوحة المطلوبة | الكود المقترح | الحالة الحالية | الفجوة |
|---|----------------|---------------|---------------|--------|
| 1 | لوحة إدارة الصلاحيات وتقارير المنصة | `admin_control` | ⚠️ **جزئي** — `access` dashboard + `analytics` views موجودان لكن غير موحدين في لوحة واحدة | يحتاج دمج Access + Analytics في لوحة رئيسية واحدة + إضافة تقارير شاملة |
| 2 | لوحة فريق الدعم والمساعدة | `support` | ✅ **موجود ~90%** — views + templates كاملة | يحتاج ربط أفضل مع UnifiedRequest (HD) |
| 3 | لوحة إدارة المحتوى | `content` | ✅ **موجود ~85%** — إدارة المحتوى + إشراف المعرض + المراجعات | يحتاج إضافة المراجعات كقسم فرعي رسمي |
| 4 | لوحة إدارة الإعلانات والترويج | `promo` | ✅ **موجود ~90%** — حملات + تسعير + بنرات + لوحة خدمة + استفسارات | يحتاج توثيق أفضل لسير العمل |
| 5 | لوحة فريق التوثيق | `verify` | ✅ **موجود ~90%** — طلبات + مستندات + متطلبات + شارات + ops | يحتاج ربط مع UnifiedRequest (AD) |
| 6 | لوحة إدارة الاشتراكات والترقية | `subs` | ⚠️ **جزئي ~65%** — خطط + قوائم موجودة، لكن عمليات التشغيل محدودة | يحتاج إضافة إدارة ترقية/تخفيض + تقارير + أتمتة |
| 7 | لوحة إدارة الخدمات الإضافية | `extras` | ⚠️ **جزئي ~50%** — views أساسية موجودة، لكن لا يوجد كتالوج خدمات | يحتاج ServiceCatalog + إدارة طلبات + تقارير |
| 8 | لوحة العميل للخدمات الإضافية | `client_extras` | ⚠️ **خاطئ البناء ~30%** — `extras_portal` مبني كبوابة مزود وليس عميل | يحتاج إعادة توجيه أو بناء بوابة عميل جديدة |

### 3.2 مستويات الصلاحيات المطلوبة vs الموجود

| المستوى | مطلوب | موجود | الفجوة |
|---------|-------|-------|--------|
| Admin | ✅ | ✅ `AccessLevel.ADMIN` | — |
| Power User | ✅ | ✅ `AccessLevel.POWER` | — |
| User | ✅ | ✅ `AccessLevel.USER` | — |
| QA | ✅ | ✅ `AccessLevel.QA` (read-only) | — |
| Client | ✅ | ⚠️ `AccessLevel.CLIENT` موجود لكن محدود بـ extras فقط | يحتاج توسيع لدعم بوابة العميل الكاملة |

**فجوات RBAC:**
1. **صلاحية الرؤية vs التنفيذ**: موجودة جزئياً عبر `is_readonly()` لـ QA، لكن غير مُعمّمة لكل مستوى
2. **منح أكثر من لوحة**: ✅ مدعوم عبر M2M `allowed_dashboards`
3. **صلاحية الإجراء داخل اللوحة**: ✅ مدعوم عبر `AccessPermission` + Policy Engines
4. **تمييز read vs write per dashboard**: ⚠️ `dashboard_allowed(user, code, write=True)` موجود لكن التطبيق غير متسق عبر كل الـ views

### 3.3 أنواع الطلبات المطلوبة vs الموجود

| النوع | الكود المطلوب | الموجود | الفجوة |
|-------|--------------|---------|--------|
| الدعم والمساعدة | HD | ✅ `helpdesk` في UnifiedRequest | يحتاج مطابقة الكود → HD |
| الإعلانات والترويج | MD | ✅ `promo` في UnifiedRequest | يحتاج مطابقة الكود → MD |
| التوثيق | AD | ✅ `verification` في UnifiedRequest | يحتاج مطابقة الكود → AD |
| الاشتراكات والترقية | SD | ✅ `subscription` في UnifiedRequest | يحتاج مطابقة الكود → SD |
| الخدمات الإضافية | P | ✅ `extras` في UnifiedRequest | يحتاج مطابقة الكود → P |

**ملاحظة:** نظام `UnifiedRequest` موجود بالفعل مع الأنواع التالية:
```python
UnifiedRequestType: helpdesk, promo, verification, subscription, extras, reviews
```
الفجوة تقتصر على توحيد الترميز وإضافة `reviews` إذا لزم الأمر.

### 3.4 التسعير والضريبة — تحليل الفجوات

| الميزة | مطلوب | موجود | الفجوة |
|--------|-------|-------|--------|
| أسعار الخدمات الإعلانية من Admin | ✅ | ✅ `PromoPricingRule` + `PromoAdPrice` | — (موجود) |
| أسعار التوثيق من Admin | ✅ | ⚠️ مخزنة في `SubscriptionPlan.verification_*_fee` | يحتاج نموذج مستقل |
| أسعار الخدمات الإضافية من Admin | ✅ | ❌ **غير موجود** — لا كتالوج أسعار | يحتاج `ServiceCatalog` + `ExtraPricingRule` |
| VAT / Tax rate من Admin | ✅ | ✅ `PlatformConfig.vat_percent` | — (موجود) |
| قواعد تسعير حسب النوع/الترتيب/المدة | ✅ | ⚠️ موجود جزئياً للإعلانات فقط | يحتاج تعميم |
| أسعار الاشتراكات من Admin | ✅ | ✅ `SubscriptionPlan.price` | — (موجود) |

---

## 4. Reuse / Refactor / Replace Matrix

### 4.1 القرار لكل تطبيق

| التطبيق | القرار | التفاصيل |
|---------|--------|---------|
| `accounts` | ✅ **Reuse** | ناضج ومستقر — لا يحتاج تعديل |
| `providers` | ✅ **Reuse** | ناضج ومستقر |
| `marketplace` | ✅ **Reuse** | ناضج ومستقر |
| `billing` | ✅ **Reuse** | نظام فوترة قوي ومتكامل |
| `subscriptions` | ⚠️ **Refactor** | إضافة إدارة ترقية/تخفيض من اللوحة |
| `verification` | ✅ **Reuse** | ناضج جداً مع سير عمل كامل |
| `promo` | ✅ **Reuse** | نظام تسعير مرن جاهز |
| `support` | ✅ **Reuse** | ناضج مع سير عمل كامل |
| `content` | ✅ **Reuse** | ناضج |
| `moderation` | ✅ **Reuse** | ناضج |
| `excellence` | ✅ **Reuse** | ناضج |
| `reviews` | ✅ **Reuse** | ناضج |
| `messaging` | ✅ **Reuse** | ناضج |
| `notifications` | ✅ **Reuse** | ناضج |
| `analytics` | ⚠️ **Refactor** | إضافة تقارير متقدمة لكل لوحة |
| `audit` | ✅ **Reuse** | ناضج |
| `core` | ⚠️ **Refactor** | توسيع PlatformConfig للتسعير الشامل |
| `backoffice` | ⚠️ **Refactor** | تعزيز RBAC: read/write per dashboard، توسيع Client level |
| `dashboard` | ⚠️ **Refactor** | إعادة تنظيم الأقسام لتطابق الـ 8 لوحات + توحيد access control |
| `extras` | ⚠️ **Refactor** | إضافة ServiceCatalog + كتالوج أسعار |
| `extras_portal` | 🔄 **Replace/Rebuild** | إعادة توجيه ليصبح بوابة عميل بدلاً من بوابة مزود |
| `unified_requests` | ⚠️ **Refactor** | توحيد أكواد الأنواع (HD, MD, AD, SD, P) |
| `features` | ✅ **Reuse** | خدمات فقط — لا يحتاج تعديل |
| `mobile_web` | ✅ **Reuse** | ناضج |
| `uploads` | ✅ **Reuse** | خدمي |

### 4.2 القرار لكل نموذج بيانات

| النموذج | القرار | الملاحظات |
|---------|--------|----------|
| `Dashboard` | ✅ Reuse | يحتاج seed data جديد فقط |
| `AccessPermission` | ⚠️ Refactor | إضافة `can_read` / `can_write` flags |
| `UserAccessProfile` | ⚠️ Refactor | إضافة field: `read_only_dashboards` M2M أو flag per dashboard |
| `PlatformConfig` | ⚠️ Refactor | توسيع بإعدادات تسعير الخدمات الإضافية والتوثيق |
| `UnifiedRequest` | ⚠️ Refactor | تحديث أكواد الأنواع |
| `PromoPricingRule` | ✅ Reuse | — |
| `PromoAdPrice` | ⚠️ Deprecate | استبدال بـ PromoPricingRule |
| `SubscriptionPlan` | ⚠️ Refactor | فصل verification fees إلى نموذج مستقل |
| `ExtraPurchase` | ⚠️ Refactor | ربط بـ ServiceCatalog |
| `ExtrasPortalSubscription` | 🔄 Replace | إعادة بناء للعميل |
| جميع النماذج الأخرى | ✅ Reuse | لا تحتاج تعديل |

### 4.3 القرار لكل ميزة وظيفية

| الميزة | القرار | الملاحظات |
|--------|--------|----------|
| مصادقة OTP للوحة | ✅ Reuse | تعمل بشكل ممتاز |
| Access Control decorator | ⚠️ Refactor | إضافة فحص read/write |
| Policy Engines | ✅ Reuse | بنية ممتازة |
| Audit Logging | ✅ Reuse | شامل (50+ نوع إجراء) |
| Celery Tasks | ✅ Reuse | 10+ مهام مجدولة |
| Feature Flags | ✅ Reuse | بنية مرنة |
| تصدير CSV/XLSX/PDF | ✅ Reuse | مع حدود صفوف |
| Dashboard Templates | ⚠️ Refactor | إعادة تنظيم per-panel |

---

## 5. Proposed Django Architecture

### 5.1 التطبيقات المقترحة (بعد إعادة الهيكلة)

لا حاجة لإنشاء تطبيقات جديدة بالكامل. التغييرات المطلوبة:

| التطبيق | التغيير | الوصف |
|---------|--------|-------|
| `backoffice` | **Refactor** | تعزيز models + policies |
| `dashboard` | **Refactor** | إعادة تنظيم views حسب اللوحات الـ 8 |
| `extras` | **Refactor** | إضافة ServiceCatalog |
| `extras_portal` | **Rebuild** | تحويل لبوابة عميل |
| `unified_requests` | **Refactor** | توحيد الرموز |
| `core` | **Extend** | توسيع PlatformConfig |
| جميع الباقي | **Reuse** | بدون تغيير |

### 5.2 النماذج المقترحة (الجديدة فقط)

#### نموذج جديد: `ServiceCatalog` (في extras app)
```python
class ServiceCatalog(models.Model):
    code = models.SlugField(unique=True)       # e.g. "extra_chat_10", "extra_boost_7d"
    title_ar = models.CharField(max_length=200)
    description_ar = models.TextField(blank=True)
    extra_type = models.CharField(choices=ExtraType.choices)  # time_based / credit_based
    default_duration_days = models.PositiveIntegerField(null=True, blank=True)
    default_credits = models.PositiveIntegerField(null=True, blank=True)
    base_price = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=3, default="SAR")
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```

#### نموذج جديد: `VerificationPricingRule` (في verification app)
```python
class VerificationPricingRule(models.Model):
    badge_type = models.CharField(choices=VerificationBadgeType.choices)
    plan_tier = models.CharField(choices=PlanTier.choices, blank=True)  # إذا فارغ = لجميع الخطط
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=3, default="SAR")
    validity_days = models.PositiveIntegerField(default=365)
    is_active = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ["badge_type", "plan_tier"]
```

#### نموذج جديد: `TaxSetting` (في core app — بديل لتبسيط PlatformConfig)
**القرار: لا حاجة لنموذج منفصل.** `PlatformConfig` يكفي كـ singleton مع حقول VAT الموجودة. إضافة حقول فقط:

```python
# إضافة إلى PlatformConfig:
verification_blue_base_price = models.DecimalField(default=0)
verification_green_base_price = models.DecimalField(default=0)
extras_vat_percent = models.DecimalField(default=15.00)
```

### 5.3 هيكل الصلاحيات / RBAC المقترح

#### تعديل `AccessPermission`:
```python
class AccessPermission(models.Model):
    code = models.SlugField(unique=True)
    name_ar = models.CharField(max_length=120)
    dashboard_code = models.SlugField(blank=True)
    permission_type = models.CharField(
        max_length=10,
        choices=[("read", "قراءة"), ("write", "قراءة وكتابة")],
        default="write"
    )
    description = models.CharField(max_length=255, blank=True)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)
```

#### تعديل `UserAccessProfile`:
```python
class UserAccessProfile(models.Model):
    user = models.OneToOneField(User, ...)
    level = models.CharField(choices=AccessLevel.choices)
    allowed_dashboards = models.ManyToManyField(Dashboard, blank=True)
    read_only_dashboards = models.ManyToManyField(
        Dashboard, blank=True, related_name="readonly_profiles"
    )  # لوحات بصلاحية قراءة فقط
    granted_permissions = models.ManyToManyField(AccessPermission, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
```

#### Seed Data المطلوب للوحات:
```python
DASHBOARDS = [
    ("admin_control", "إدارة الصلاحيات والتقارير", 1),
    ("support", "الدعم والمساعدة", 10),
    ("content", "إدارة المحتوى", 20),
    ("promo", "الإعلانات والترويج", 30),
    ("verify", "التوثيق", 40),
    ("subs", "الاشتراكات والترقية", 50),
    ("extras", "الخدمات الإضافية", 60),
    ("client_extras", "بوابة العميل", 70),
    # لوحات مساندة (تبقى كما هي):
    ("moderation", "مركز الإشراف", 25),
    ("excellence", "إدارة التميز", 45),
    ("analytics", "التحليلات", 5),
    ("billing", "الفوترة", 55),
]
```

### 5.4 هيكل URLs المقترح

```
/dashboard/                           → الرئيسية
/dashboard/admin/                     → لوحة 1: الصلاحيات والتقارير
  ├── access-profiles/                → إدارة ملفات الصلاحيات
  ├── users/                          → إدارة المستخدمين
  ├── audit-log/                      → سجل التدقيق
  ├── reports/                        → التقارير الشاملة
  └── analytics/                      → التحليلات والـ KPIs

/dashboard/support/                   → لوحة 2: الدعم
  ├── tickets/                        → تذاكر الدعم
  ├── tickets/<id>/                   → تفاصيل التذكرة
  └── tickets/create/                 → إنشاء تذكرة

/dashboard/content/                   → لوحة 3: المحتوى
  ├── blocks/                         → كتل المحتوى
  ├── docs/                           → الوثائق القانونية
  ├── links/                          → الروابط
  ├── portfolio/                      → إشراف المعرض
  ├── spotlights/                     → إشراف اللمحات
  └── reviews/                        → إدارة المراجعات

/dashboard/promo/                     → لوحة 4: الإعلانات
  ├── requests/                       → طلبات الحملات
  ├── requests/<id>/                  → تفاصيل الحملة
  ├── banners/                        → البنرات الرئيسية
  ├── pricing/                        → التسعير
  ├── inquiries/                      → الاستفسارات
  └── modules/                        → لوحة الخدمات

/dashboard/verify/                    → لوحة 5: التوثيق
  ├── requests/                       → طلبات التوثيق
  ├── requests/<id>/                  → تفاصيل الطلب
  ├── badges/                         → الشارات الفعالة
  └── ops/                            → عمليات التوثيق

/dashboard/subs/                      → لوحة 6: الاشتراكات
  ├── plans/                          → خطط الاشتراك
  ├── subscriptions/                  → الاشتراكات الفعالة
  ├── ops/                            → عمليات الاشتراكات
  └── reports/                        → تقارير الاشتراكات

/dashboard/extras/                    → لوحة 7: الخدمات الإضافية
  ├── catalog/                        → كتالوج الخدمات
  ├── purchases/                      → المشتريات
  ├── clients/                        → العملاء
  └── reports/                        → التقارير

/portal/client/                       → لوحة 8: بوابة العميل
  ├── services/                       → الخدمات المتاحة
  ├── my-purchases/                   → مشترياتي
  ├── invoices/                       → فواتيري
  └── profile/                        → ملفي الشخصي
```

### 5.5 هيكل Views/Classes المقترح

لا حاجة لتغيير جذري. المطلوب:

1. **إعادة تنظيم `dashboard/views.py`** (ملف كبير جداً ~5600+ سطر) إلى ملفات فرعية:
```
dashboard/
  views/
    __init__.py
    admin_control.py      → Access profiles, audit, reports
    support.py             → Support tickets (موجود)
    content.py             → Content + Reviews (موجود)
    promo.py               → Promo campaigns (موجود)
    verify.py              → Verification (موجود)
    subs.py                → Subscriptions (يحتاج توسيع)
    extras.py              → Extras management (يحتاج توسيع)
    common.py              → Shared helpers
    auth.py                → OTP auth (موجود)
    home.py                → Dashboard home
```

2. **إضافة decorator محسّن:**
```python
def dashboard_panel_required(panel_code, write=False):
    """يفحص صلاحية الوصول للوحة محددة مع تمييز read/write"""
    ...
```

### 5.6 هيكل Admin المقترح

التغييرات المطلوبة في Django Admin:

| النموذج | الحالة | التغيير |
|---------|--------|--------|
| `ServiceCatalog` | 🆕 جديد | إضافة admin مع بحث وفلترة |
| `VerificationPricingRule` | 🆕 جديد | إضافة admin مع فلترة حسب badge_type |
| `PlatformConfig` | ⚠️ توسيع | إضافة fieldsets للأسعار الجديدة |
| `AccessPermission` | ⚠️ توسيع | إضافة عمود permission_type |
| `UserAccessProfile` | ⚠️ توسيع | إضافة read_only_dashboards |
| جميع الباقي | ✅ بدون تغيير | — |

### 5.7 هيكل القوالب المقترح

```
dashboard/templates/dashboard/
  ├── base_dashboard.html              → ✅ Reuse (القالب الأساسي)
  ├── home.html                        → ✅ Reuse (الرئيسية)
  ├── login.html / otp.html            → ✅ Reuse (المصادقة)
  │
  ├── admin_control/                   → ⚠️ Refactor (تجميع)
  │   ├── access_profiles_list.html    → نقل من الجذر
  │   ├── users_list.html              → نقل من الجذر
  │   ├── user_detail.html             → نقل من الجذر
  │   ├── audit_log_list.html          → نقل من الجذر
  │   └── reports.html                 → 🆕 جديد
  │
  ├── support/                         → ✅ Reuse
  │   ├── tickets_list.html
  │   ├── ticket_detail.html
  │   └── ticket_create.html
  │
  ├── content/                         → ✅ Reuse
  │   ├── management.html
  │   ├── portfolio_moderation.html
  │   ├── spotlight_moderation.html
  │   ├── reviews_list.html            → نقل من الجذر
  │   └── review_detail.html           → نقل من الجذر
  │
  ├── promo/                           → ✅ Reuse (معظمها منظم بالفعل)
  │   ├── requests_list.html
  │   ├── request_detail.html
  │   ├── pricing.html
  │   ├── banners.html
  │   ├── inquiries.html
  │   └── service_board.html
  │
  ├── verify/                          → ✅ Reuse
  │   ├── requests_list.html
  │   ├── request_detail.html
  │   ├── badges_list.html
  │   └── ops.html
  │
  ├── subs/                            → ⚠️ Extend
  │   ├── plans_list.html
  │   ├── subscriptions_list.html
  │   ├── ops.html
  │   └── reports.html                 → 🆕 جديد
  │
  ├── extras/                          → ⚠️ Extend
  │   ├── catalog.html                 → 🆕 جديد
  │   ├── purchases_list.html
  │   ├── clients_list.html
  │   └── reports.html                 → 🆕 جديد
  │
  └── partials/                        → ✅ Reuse
      ├── _promo_nav.html
      └── _request_actions.html
```

---

## 6. Pricing & Tax Admin Design

### 6.1 المبدأ المعماري

**لا أسعار Hardcoded في الكود. كل سعر يُقرأ من قاعدة البيانات ويُدار من Django Admin.**

### 6.2 النماذج المقترحة والموجودة

#### أ. ضريبة القيمة المضافة (VAT) — ✅ موجود
```
PlatformConfig (Singleton)
├── vat_percent = 15.00            → VAT عام
├── promo_vat_percent = 15.00      → VAT إعلانات
└── extras_vat_percent = 15.00     → 🆕 VAT خدمات إضافية
```
**الاستخدام:** عند إنشاء فاتورة:
```python
config = PlatformConfig.load()
invoice.vat_percent = config.vat_percent
invoice.vat_amount = invoice.subtotal * config.vat_percent / 100
invoice.total = invoice.subtotal + invoice.vat_amount
```

#### ب. أسعار الإعلانات — ✅ موجود ومتطور
```
PromoPricingRule (Admin-managed)
├── code: "home_banner_daily_10s_first"
├── service_type: HOME_BANNER
├── unit: day
├── frequency: 10s
├── search_position: first
├── amount: 150.00
└── is_active: True
```
**الاستخدام:** عند تسعير حملة إعلانية:
```python
rules = PromoPricingRule.objects.filter(
    service_type=item.service_type,
    is_active=True
)
# اختيار القاعدة المطابقة حسب frequency + position
```

#### ج. أسعار التوثيق — 🆕 جديد
```
VerificationPricingRule (Admin-managed)
├── badge_type: blue / green
├── plan_tier: basic / riyadi / pro / "" (عام)
├── amount: 500.00
├── currency: SAR
├── validity_days: 365
└── is_active: True
```
**الاستخدام:** عند إنشاء فاتورة توثيق:
```python
rule = VerificationPricingRule.objects.filter(
    badge_type=request.badge_type,
    plan_tier__in=[user_plan_tier, ""],
    is_active=True
).order_by("-plan_tier").first()  # الأكثر تحديداً أولاً
```
**لماذا نموذج مستقل؟** لأن أسعار التوثيق الحالية مدمجة في `SubscriptionPlan.verification_blue_fee` وهذا يخلق تبعية غير ضرورية — ماذا لو أراد العميل تغيير سعر التوثيق الأزرق فقط لخطة واحدة؟

#### د. كتالوج الخدمات الإضافية — 🆕 جديد
```
ServiceCatalog (Admin-managed)
├── code: "extra_chat_credits_50"
├── title_ar: "50 رصيد محادثة إضافي"
├── description_ar: "..."
├── extra_type: credit_based
├── default_credits: 50
├── base_price: 99.00
├── currency: SAR
├── is_active: True
└── sort_order: 10
```
**الاستخدام:** عند شراء خدمة إضافية:
```python
catalog_item = ServiceCatalog.objects.get(code=sku, is_active=True)
purchase = ExtraPurchase.objects.create(
    user=user,
    sku=catalog_item.code,
    title=catalog_item.title_ar,
    extra_type=catalog_item.extra_type,
    subtotal=catalog_item.base_price,
    credits_total=catalog_item.default_credits,
    ...
)
```

### 6.3 مخطط تدفق التسعير

```
  ┌────────────────────────────────────────────┐
  │            Django Admin                     │
  │  ┌──────────────────────────────────────┐   │
  │  │ PlatformConfig                       │   │
  │  │  • vat_percent                       │   │
  │  │  • promo_vat_percent                 │   │
  │  │  • extras_vat_percent                │   │
  │  └──────────────────────────────────────┘   │
  │  ┌──────────────────────────────────────┐   │
  │  │ PromoPricingRule                     │   │
  │  │  • service_type + frequency → amount │   │
  │  └──────────────────────────────────────┘   │
  │  ┌──────────────────────────────────────┐   │
  │  │ VerificationPricingRule (🆕)         │   │
  │  │  • badge_type + plan_tier → amount   │   │
  │  └──────────────────────────────────────┘   │
  │  ┌──────────────────────────────────────┐   │
  │  │ ServiceCatalog (🆕)                  │   │
  │  │  • code + extra_type → base_price    │   │
  │  └──────────────────────────────────────┘   │
  │  ┌──────────────────────────────────────┐   │
  │  │ SubscriptionPlan                     │   │
  │  │  • tier + period → price             │   │
  │  └──────────────────────────────────────┘   │
  └────────────────────────────────────────────┘
                    │
                    ▼
  ┌────────────────────────────────────────────┐
  │          Pricing Service Layer              │
  │  calculate_promo_price(request_item)        │
  │  calculate_verification_price(request)      │
  │  calculate_extras_price(purchase)           │
  │  calculate_subscription_price(plan)         │
  │  apply_vat(subtotal, category)              │
  └────────────────────────────────────────────┘
                    │
                    ▼
  ┌────────────────────────────────────────────┐
  │          Invoice Creation                   │
  │  billing.services.create_invoice(           │
  │      user, subtotal, vat_percent,           │
  │      reference_type, reference_id           │
  │  )                                          │
  └────────────────────────────────────────────┘
```

### 6.4 ملخص قرارات التسعير

| المجال | النموذج | Django Admin | ملاحظة |
|--------|---------|------------|--------|
| VAT عام | `PlatformConfig.vat_percent` | ✅ موجود | Singleton |
| VAT إعلانات | `PlatformConfig.promo_vat_percent` | ✅ موجود | Singleton |
| VAT خدمات إضافية | `PlatformConfig.extras_vat_percent` | 🆕 إضافة | حقل جديد في Singleton |
| أسعار الاشتراكات | `SubscriptionPlan.price` | ✅ موجود | per-plan |
| أسعار الإعلانات | `PromoPricingRule` | ✅ موجود | قواعد مرنة |
| أسعار التوثيق | `VerificationPricingRule` | 🆕 جديد | per badge_type + plan_tier |
| كتالوج الخدمات الإضافية | `ServiceCatalog` | 🆕 جديد | كتالوج كامل |
| مضاعفات الموضع والتكرار | `PlatformConfig` JSON fields | ✅ موجود | — |

---

## 7. Step-by-step Execution Plan

### Phase 1: Audit ✅ (هذا التقرير)
- [x] جرد كامل للبنية الحالية
- [x] تحليل الفجوات
- [x] قرارات هندسية
- [x] معمارية مقترحة

### Phase 2: Core RBAC Enhancement
**الهدف:** تعزيز نظام الصلاحيات ليدعم كل المتطلبات.

| المهمة | النوع | التأثير |
|--------|-------|--------|
| إضافة `permission_type` (read/write) إلى `AccessPermission` | Migration | لا يكسر |
| إضافة `read_only_dashboards` M2M إلى `UserAccessProfile` | Migration | لا يكسر |
| تحديث `dashboard_allowed()` لدعم read/write per dashboard | Code | Backward compatible |
| تحديث `@dashboard_staff_required` لدعم `write=True/False` | Code | Backward compatible |
| إنشاء seed migration للوحات الـ 8 المطلوبة + `admin_control` | Migration | لا يكسر |
| إنشاء seed migration للصلاحيات الدقيقة الجديدة | Migration | لا يكسر |
| اختبارات RBAC الجديدة | Tests | — |

**المخاطر:** ⚠️ يجب ضمان backward compatibility — القيم الافتراضية يجب أن تحافظ على السلوك الحالي.

### Phase 3: Unified Request Core
**الهدف:** توحيد أكواد أنواع الطلبات.

| المهمة | النوع | التأثير |
|--------|-------|--------|
| إضافة `display_code` property لـ UnifiedRequest يعيد HD/MD/AD/SD/P | Code | لا يكسر |
| تحديث القوالب لعرض الأكواد الجديدة | Templates | عرض فقط |
| إضافة `prefix_map` في UnifiedRequest | Code | لا يكسر |
| توحيد auto-code generation عند الإنشاء | Code | للجديد فقط |

**المخاطر:** ⚠️ الأكواد الحالية (helpdesk, promo, etc.) يجب أن تبقى valid — نضيف mapping فقط.

### Phase 4: Admin Control Panel (لوحة 1)
**الهدف:** إنشاء لوحة إدارة الصلاحيات والتقارير.

| المهمة | النوع | التأثير |
|--------|-------|--------|
| دمج Access Profiles views تحت `/dashboard/admin/` | URL Refactor | إعادة توجيه |
| دمج Users management views | URL Refactor | إعادة توجيه |
| دمج Audit Log views | URL Refactor | إعادة توجيه |
| دمج Analytics/Reports views | URL Refactor | إعادة توجيه |
| إنشاء template `admin_control/` directory | Templates | جديد |
| إنشاء تقرير عام للمنصة | View + Template | جديد |

### Phase 5: Team Modules Enhancement
**الهدف:** تعزيز لوحات الفرق الموجودة.

| المهمة | اللوحة | النوع |
|--------|--------|-------|
| ربط Support بـ UnifiedRequest (HD) | الدعم | Code |
| إضافة Reviews كقسم رسمي في Content | المحتوى | URL + Template |
| توثيق سير عمل Promo | الإعلانات | Docs |
| ربط Verification بـ UnifiedRequest (AD) | التوثيق | Code |
| إضافة عمليات ترقية/تخفيض في Subs | الاشتراكات | View + Template |
| إضافة تقارير الاشتراكات | الاشتراكات | View + Template |

### Phase 6: Client Add-ons Portal (لوحة 8)
**الهدف:** إعادة بناء بوابة الخدمات الإضافية للعميل.

| المهمة | النوع | التأثير |
|--------|-------|--------|
| قرار: تحويل `extras_portal` أو إنشاء views جديدة في `dashboard` | Architecture | — |
| إنشاء views لعرض الخدمات المتاحة للعميل | View | جديد |
| إنشاء views لمشتريات العميل | View | جديد |
| إنشاء views لفواتير العميل | View | جديد |
| ربط بـ `ServiceCatalog` | Code | جديد |
| اختبارات access control للعميل | Tests | — |

### Phase 7: Pricing/Tax from Admin
**الهدف:** إنشاء النماذج الجديدة للتسعير.

| المهمة | النوع | التأثير |
|--------|-------|--------|
| إنشاء `ServiceCatalog` model + migration | Migration | لا يكسر |
| إنشاء `VerificationPricingRule` model + migration | Migration | لا يكسر |
| إضافة `extras_vat_percent` إلى PlatformConfig | Migration | لا يكسر |
| إنشاء Admin registrations | Admin | جديد |
| تحديث verification pricing logic لاستخدام VerificationPricingRule | Code | Refactor |
| تحديث extras purchase logic لاستخدام ServiceCatalog | Code | Refactor |
| إنشاء Pricing Service Layer | Code | جديد |
| Data migration لنقل أسعار التوثيق من SubscriptionPlan | Migration | Data |
| اختبارات التسعير | Tests | — |

### Phase 8: Reporting / Export / Notifications
**الهدف:** تعزيز التقارير والتصدير.

| المهمة | النوع | التأثير |
|--------|-------|--------|
| تقارير شاملة لكل لوحة | Views + Templates | جديد |
| توسيع التصدير (CSV/XLSX/PDF) لكل قسم | Views | توسيع |
| إشعارات لتغييرات الحالة | Notifications | توسيع |
| Dashboard widgets للإحصاءات الحية | Templates | جديد |

---

## 8. Risks and Migration Notes

### 8.1 المخاطر الرئيسية

| # | المخاطرة | الاحتمال | التأثير | الاستراتيجية |
|---|---------|---------|--------|-------------|
| 1 | كسر الـ views الحالية أثناء إعادة تنظيم URLs | متوسط | عالي | استخدام URL redirects + backward-compatible aliases |
| 2 | فقدان بيانات الصلاحيات أثناء migration | منخفض | عالي | Data migration مع rollback plan |
| 3 | تعارض بين code القديم والجديد لـ UnifiedRequest | متوسط | متوسط | إضافة mapping بدلاً من تغيير القيم |
| 4 | أداء مع إضافة RBAC checks إضافية | منخفض | منخفض | استخدام caching الموجود |
| 5 | كسر الـ extras_portal أثناء إعادة البناء | متوسط | متوسط | بناء البوابة الجديدة أولاً ثم التبديل |

### 8.2 قواعد الترحيل

1. **لا حذف بدون بديل:** لا يُحذف أي model أو view حتى يكون البديل جاهزاً ومختبراً.
2. **Backward compatible migrations:** كل migration يجب أن يكون runnable بدون downtime.
3. **Feature flags:** استخدام Feature Flags لتفعيل الميزات الجديدة تدريجياً.
4. **Data integrity:** كل data migration يجب أن يكون قابلاً للعكس (reversible).
5. **Test coverage:** كل phase يجب أن تنتهي بـ tests تغطي التغييرات.

### 8.3 ملاحظات قرار هندسي

#### لماذا Refactor وليس Rebuild؟

1. **البنية الحالية قوية:** 25 تطبيق Django مع فصل واضح بين المسؤوليات.
2. **RBAC موجود بنسبة 85%:** `Dashboard` + `AccessPermission` + `UserAccessProfile` + Policy Engines = بنية ممتازة.
3. **نظام الطلبات الموحد موجود:** `UnifiedRequest` يدعم كل الأنواع المطلوبة.
4. **الفوترة ناضجة:** `Invoice` + `PaymentAttempt` + VAT = نظام متكامل.
5. **التسعير موجود جزئياً:** `PromoPricingRule` + `PlatformConfig` يحتاج فقط إلى نموذجين جديدين.
6. **58 قالب لوحة تحكم:** إعادة بنائها من الصفر ستكون هدراً.
7. **10+ مهام Celery مجدولة:** تعمل بثبات وتغطي كل الوحدات.

#### ما الذي يُبنى من جديد فعلاً؟

فقط:
- نموذج `ServiceCatalog` (كتالوج أسعار الخدمات الإضافية)
- نموذج `VerificationPricingRule` (أسعار التوثيق)
- بوابة العميل للخدمات الإضافية (views + templates)
- تقرير عام للمنصة (view + template)
- حقل `extras_vat_percent` في PlatformConfig
- ~5 templates جديدة
- Pricing Service Layer

**كل شيء آخر = Refactor + Extend.**

### 8.4 أولوية التنفيذ المقترحة

```
الأولوية القصوى (يجب أن يُنفذ أولاً):
  Phase 2: RBAC Enhancement → أساس كل شيء آخر

الأولوية العالية:
  Phase 3: Unified Request Codes → توحيد لقراءة أسهل
  Phase 7: Pricing Models → ServiceCatalog + VerificationPricingRule

الأولوية المتوسطة:
  Phase 4: Admin Control Panel → تجميع لوحة الإدارة
  Phase 5: Team Modules → تعزيز اللوحات الموجودة

الأولوية الأقل (يمكن تأجيلها):
  Phase 6: Client Portal → بوابة العميل
  Phase 8: Reports/Export → تحسينات
```

---

## الخلاصة النهائية

المشروع في حالة ناضجة بشكل ملحوظ. البنية الحالية تغطي ~65-70% من المتطلبات النهائية. القرار الأمثل هو **Refactor مؤسسي تدريجي** يحافظ على الاستقرار ويضيف ما ينقص فقط.

**الجاهز للاستثمار الفوري (Reuse):**
- 20 من 25 تطبيق Django
- 100+ نموذج بيانات
- نظام RBAC (85% جاهز)
- نظام الفوترة الكامل
- 58 قالب لوحة تحكم
- 10+ مهام خلفية

**يحتاج عمل (Refactor/New):**
- نموذجان جديدان (ServiceCatalog, VerificationPricingRule)
- تعزيز RBAC (read/write)
- إعادة تنظيم URLs/views
- بوابة عميل جديدة
- ~5 templates جديدة
- Pricing Service Layer

---

*هذا التقرير جاهز. في انتظار الموافقة للانتقال إلى Phase 2.*
