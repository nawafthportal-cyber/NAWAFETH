# 📘 مرجع مشروع نوافذ — NAWAFETH PROJECT REFERENCE

> **آخر تحديث:** 2026-02-28  
> **الغرض:** مرجع شامل لأي مطوّر أو وكيل ذكي قبل إجراء أي تحديث أو إضافة على المشروع  
> **اللغة الأساسية:** العربية (RTL) — `ar_SA`

---

## جدول المحتويات

1. [نظرة عامة على المشروع](#1-نظرة-عامة-على-المشروع)
2. [البنية العامة للمجلدات](#2-البنية-العامة-للمجلدات)
3. [نظام التصميم والألوان](#3-نظام-التصميم-والألوان)
4. [هيكلية تطبيق Flutter (Mobile)](#4-هيكلية-تطبيق-flutter-mobile)
5. [هيكلية Backend — Django](#5-هيكلية-backend--django)
6. [الأمان والمصادقة](#6-الأمان-والمصادقة)
7. [طبقة API والخدمات](#7-طبقة-api-والخدمات)
8. [التنقل والمسارات](#8-التنقل-والمسارات)
9. [نظام عزل الحسابات](#9-نظام-عزل-الحسابات)
10. [النماذج (Models)](#10-النماذج-models)
11. [التخزين المؤقت والأداء](#11-التخزين-المؤقت-والأداء)
12. [أنماط التطوير المتبعة](#12-أنماط-التطوير-المتبعة)
13. [قواعد إلزامية قبل أي تعديل](#13-قواعد-إلزامية-قبل-أي-تعديل)
14. [مصفوفة نقاط الـ API](#14-مصفوفة-نقاط-الـ-api)
15. [البيئات والنشر](#15-البيئات-والنشر)
16. [الملحقات](#16-الملحقات)

---

## 1. نظرة عامة على المشروع

**نوافذ (Nawafeth)** — منصة سوق خدمات سعودية تربط بين **العملاء** و **مزودي الخدمات**.

| البُعد | التفاصيل |
|--------|----------|
| **نوع المشروع** | سوق خدمات (Services Marketplace) |
| **الفئة المستهدفة** | السوق السعودي — هوية المستخدم عبر رقم الجوال |
| **لغات التطبيق** | عربية (أساسية) + إنجليزية |
| **الخط الأساسي** | Cairo (8 أوزان: ExtraLight → Black) |
| **الاتجاه** | RTL (من اليمين لليسار) |
| **تطبيق الجوال** | Flutter (Dart ≥ 3.0) |
| **الخادم** | Django 5+ (Python) — DRF — PostgreSQL |
| **المصادقة** | OTP عبر الجوال → JWT (Access + Refresh) |
| **النشر** | Render.com (Backend) — رابط: `nawafeth-2290.onrender.com` |

### الأدوار الأساسية

| الدور | الوصف |
|-------|-------|
| `visitor` | زائر بدون حساب |
| `phone_only` | سجّل رقم الجوال فقط |
| `client` | عميل مكتمل التسجيل — يطلب خدمات |
| `provider` | مزود خدمة معتمد — يقدم خدمات |
| `staff` | فريق العمليات والإدارة |

---

## 2. البنية العامة للمجلدات

```
nawafeth/
├── backend/                    # Django Backend
│   ├── apps/                   # 22 تطبيق Django
│   │   ├── accounts/           # المستخدمون، المحافظ، OTP
│   │   ├── providers/          # ملفات المزودين، خدماتهم، المعرض
│   │   ├── marketplace/        # طلبات الخدمة، العروض
│   │   ├── messaging/          # المحادثات المباشرة
│   │   ├── notifications/      # الإشعارات والتفضيلات
│   │   ├── reviews/            # التقييمات (5 محاور)
│   │   ├── billing/            # الفواتير والمدفوعات
│   │   ├── subscriptions/      # خطط الاشتراك
│   │   ├── verification/       # التوثيق (الشارة الزرقاء/الخضراء)
│   │   ├── promo/              # الإعلانات والترويج
│   │   ├── support/            # تذاكر الدعم الفني
│   │   ├── content/            # CMS — محتوى الموقع
│   │   ├── backoffice/         # لوحة تحكم العمليات
│   │   ├── dashboard/          # لوحات المراقبة
│   │   ├── analytics/          # التحليلات
│   │   ├── audit/              # سجل المراجعة
│   │   ├── unified_requests/   # محرك الطلبات الموحد
│   │   ├── extras/             # مشتريات إضافية
│   │   ├── extras_portal/      # بوابة الإضافات للمزود
│   │   ├── features/           # Middleware تجديد الاشتراك
│   │   ├── core/               # فحوصات الصحة
│   │   └── uploads/            # (غير مفعّل حالياً)
│   ├── config/                 # إعدادات Django
│   │   ├── settings/
│   │   │   ├── base.py         # الإعدادات المشتركة
│   │   │   ├── dev.py          # بيئة التطوير
│   │   │   └── prod.py         # بيئة الإنتاج
│   │   ├── urls.py
│   │   └── wsgi.py / asgi.py
│   ├── requirements/
│   │   ├── base.txt
│   │   ├── dev.txt
│   │   └── prod.txt
│   └── media/                  # ملفات المستخدمين
│
├── mobile/                     # Flutter Mobile App
│   ├── lib/
│   │   ├── main.dart          # نقطة الدخول + الثيم + المسارات
│   │   ├── config/
│   │   │   └── app_env.dart   # بيئة API (local/render/auto)
│   │   ├── constants/
│   │   │   ├── colors.dart    # ألوان التطبيق
│   │   │   └── app_texts.dart # نصوص مترجمة
│   │   ├── models/            # 15 نموذج بيانات
│   │   ├── screens/           # 30+ شاشة
│   │   │   ├── provider_dashboard/  # 10 شاشات المزود
│   │   │   └── registration/       # تسجيل المزود (3 خطوات + 9 خطوات إكمال)
│   │   ├── services/          # 15 خدمة API
│   │   ├── utils/             # أدوات مساعدة
│   │   └── widgets/           # 12 widget مشترك
│   ├── assets/
│   │   ├── fonts/             # خط Cairo (8 أوزان)
│   │   ├── images/            # صور ثابتة
│   │   └── videos/            # فيديوهات ثابتة
│   └── pubspec.yaml
│
├── docs/                       # وثائق المشروع
└── infra/                      # البنية التحتية
```

---

## 3. نظام التصميم والألوان

### 🎨 لوحة الألوان الرئيسية

| الاسم | القيمة | الاستخدام |
|--------|--------|-----------|
| **DeepPurple** (أساسي) | `Colors.deepPurple` / `#673AB7` | AppBar، الأزرار الرئيسية، العلامات المحددة |
| **AppColors.deepPurple** | `rgb(102, 61, 144)` | نصوص العناوين، أيقونات الشريط العلوي |
| **AppColors.primaryLight** | `#E6E6FA` (لافندر) | خلفيات البطاقات، الشرائح الفاتحة |
| **AppColors.primaryDark** | `rgb(118, 118, 173)` | زر "خدمة" العائم، تدرجات |
| **AppColors.accentOrange** | `#F1A559` | تنبيهات، عناصر ثانوية |
| **خلفية فاتحة** | `#F5F5FA` | خلفية Scaffold الفاتحة |
| **خلفية داكنة** | `#121212` | خلفية الوضع الداكن |
| **أخضر** | `Colors.green` | نجاح، تأكيد |
| **أحمر** | `Colors.red` | خطأ، حذف، إلغاء |

### رموز الحالات (Status Colors)

| الحالة | اللون |
|--------|-------|
| جديد | `Colors.blue` |
| تحت المعالجة / تحت التنفيذ | `Colors.orange` |
| مقبول | `Colors.teal` |
| بانتظار الدفع | `Colors.amber` |
| مكتمل | `Colors.green` |
| مرفوض / ملغي | `Colors.red` |
| منتهي الصلاحية | `Colors.grey` |

### 📐 قواعد التصميم

| القاعدة | التفاصيل |
|---------|----------|
| **الخط** | `Cairo` — يُحدد في `ThemeData.fontFamily` عالمياً |
| **الاتجاه** | RTL — `Locale('ar', 'SA')` افتراضي |
| **Material** | Material 3 — `useMaterial3: true` |
| **الثيم** | Light (افتراضي) + Dark — يُتحكم عبر `MyThemeController` (InheritedWidget) |
| **AppBar** | شفاف (`backgroundColor: Colors.transparent`) مع أيقونات بنفسجية |
| **بطاقات** | حواف دائرية `BorderRadius.circular(12-16)` |
| **ظلال** | `BoxShadow` خفيفة — `blurRadius: 8-20`, `alpha: 0.05-0.08` |
| **أيقونات** | Material Icons (أساسية) + FontAwesome (ثانوية) |
| **تحريك** | `animate_do` (FadeIn, SlideIn) |
| **صور المزوّد** | `CircleAvatar` قطر `48-64` مع fallback أيقونة |

### 📏 مسافات شائعة

| العنصر | القيمة |
|--------|--------|
| padding أفقي للمحتوى | `16px` |
| padding رأسي للأقسام | `12-20px` |
| فاصل بين العناصر | `8-12px` |
| حجم خط العنوان | `18px` |
| حجم خط النص العادي | `13-14px` |
| حجم خط التسمية | `10-12px` |
| ارتفاع الشريط السفلي | `80px` |
| حجم زر "خدمة" العائم | `72x72px` |

---

## 4. هيكلية تطبيق Flutter (Mobile)

### الشاشات (Screens) — 30+ شاشة

#### الشاشات الرئيسية (Bottom Nav)
| الشاشة | الملف | المسار | Tab Index |
|--------|-------|--------|-----------|
| الرئيسية | `home_screen.dart` | `/home` | 0 |
| طلباتي/طلبات الخدمة | `orders_hub_screen.dart` | `/orders` | 1 |
| تفاعلي | `interactive_screen.dart` | `/interactive` | 2 |
| نافذتي (البروفايل) | `my_profile_screen.dart` | `/profile` | 3 |

#### شاشات المصادقة
| الشاشة | الملف | المسار |
|--------|-------|--------|
| الترحيب | `onboarding_screen.dart` | `/onboarding` |
| تسجيل الدخول | `login_screen.dart` | `/login` |
| التحقق بخطوتين | `twofa_screen.dart` | — |
| إكمال التسجيل | `signup_screen.dart` | — |

#### شاشات العميل
| الشاشة | الملف | المسار |
|--------|-------|--------|
| البحث عن مزود | `search_provider_screen.dart` | `/search_provider` 🔒 |
| طلب عاجل | `urgent_request_screen.dart` | `/urgent_request` 🔒 |
| طلب عرض سعر | `request_quote_screen.dart` | `/request_quote` 🔒 |
| إضافة خدمة | `add_service_screen.dart` | `/add_service` 🔒 |
| طلبات العميل | `client_orders_screen.dart` | — |
| تفاصيل الطلب | `client_order_details_screen.dart` | — |

> 🔒 = محمي بـ `_ModeRouteGuard` — يُمنع الوصول في وضع المزوّد

#### لوحة مزود الخدمة (`provider_dashboard/`)
| الشاشة | الملف |
|--------|-------|
| الرئيسية | `provider_home_screen.dart` |
| البروفايل | `profile_tab.dart` |
| الخدمات | `services_tab.dart` |
| التقييمات | `reviews_tab.dart` |
| الطلبات | `provider_orders_screen.dart` |
| تفاصيل الطلب | `provider_order_details_screen.dart` |
| إكمال الملف | `provider_profile_completion_screen.dart` |
| الترويج | `promotion_screen.dart` |
| الترقية | `upgrade_screen.dart` → `PlansScreen` |
| التوثيق | `verification_screen.dart` → `VerificationScreen` |

#### تسجيل المزوّد (`registration/`)
| الخطوة | الملف |
|--------|-------|
| التسجيل (3 مراحل) | `register_service_provider.dart` |
| المعلومات الشخصية | `steps/personal_info_step.dart` |
| تصنيف الاختصاص | `steps/service_classification_step.dart` |
| بيانات التواصل | `steps/contact_info_step.dart` |
| تفاصيل الخدمة | `steps/service_details_step.dart` |
| معلومات إضافية | `steps/additional_details_step.dart` |
| المحتوى | `steps/content_step.dart` |
| اللغة والموقع | `steps/language_location_step.dart` |
| خريطة النطاق | `steps/map_radius_picker_screen.dart` |
| SEO | `steps/seo_step.dart` |

#### شاشات عامة
| الشاشة | الملف |
|--------|-------|
| الإشعارات | `notifications_screen.dart` |
| إعدادات الإشعارات | `notification_settings_screen.dart` |
| المحادثات | `my_chats_screen.dart` |
| تفاصيل المحادثة | `chat_detail_screen.dart` |
| ملف المزوّد (عام) | `provider_profile_screen.dart` |
| تفاصيل الخدمة | `service_detail_screen.dart` |
| خريطة المزودين | `providers_map_screen.dart` |
| الخطط والأسعار | `plans_screen.dart` |
| خدمات إضافية | `additional_services_screen.dart` |
| إعدادات الدخول | `login_settings_screen.dart` |
| الشروط والأحكام | `terms_screen.dart` |
| حول المنصة | `about_screen.dart` |
| تواصل معنا | `contact_screen.dart` |
| نموذج طلب خدمة | `service_request_form_screen.dart` |
| التوثيق | `verification_screen.dart` |

### Widgets المشتركة

| Widget | الملف | الوظيفة |
|--------|-------|---------|
| `CustomAppBar` | `app_bar.dart` | شريط علوي شفاف مع بحث + إشعارات + محادثات |
| `CustomBottomNav` | `bottom_nav.dart` | شريط تنقل سفلي منحني + زر "خدمة" عائم |
| `CustomDrawer` | `custom_drawer.dart` | قائمة جانبية مع بيانات المستخدم من API |
| `AutoScrollingReelsRow` | `auto_scrolling_reels_row.dart` | شريط Reels يتحرك تلقائياً |
| `BannerWidget` | `banner_widget.dart` | بانر إعلاني |
| `ProfilesSlider` | `profiles_slider.dart` | شريط مزودين مُميّزين |
| `ServiceGrid` | `service_grid.dart` | شبكة خدمات |
| `TestimonialsSlider` | `testimonials_slider.dart` | شريط آراء العملاء |
| `ProviderMediaGrid` | `provider_media_grid.dart` | شبكة وسائط المزود |
| `VideoReels` | `video_reels.dart` | مشغل فيديو عمودي |
| `VideoFullScreen` | `video_full_screen.dart` | عرض فيديو ملء الشاشة |
| `PlatformReportDialog` | `platform_report_dialog.dart` | حوار الإبلاغ |

---

## 5. هيكلية Backend — Django

### التطبيقات والنماذج الرئيسية

| التطبيق | النماذج الأساسية | الكود التلقائي |
|---------|------------------|----------------|
| **accounts** | `User` (phone-based), `Wallet`, `OTP` | — |
| **providers** | `Category`, `SubCategory`, `ProviderProfile`, `ProviderService`, `ProviderPortfolioItem`, `ProviderSpotlightItem`, `ProviderFollow`, `ProviderLike` | — |
| **marketplace** | `ServiceRequest`, `Offer`, `RequestStatusLog`, `ServiceRequestAttachment` | — |
| **messaging** | `Thread`, `Message`, `MessageRead`, `ThreadUserState` | — |
| **notifications** | `EventLog`, `Notification`, `NotificationPreference`, `DeviceToken` | — |
| **reviews** | `Review` (5 محاور تقييم + نظام مراجعة) | — |
| **billing** | `Invoice`, `InvoiceLineItem`, `PaymentAttempt`, `WebhookEvent` | `IV-XXXX` |
| **support** | `SupportTeam`, `SupportTicket`, `SupportAttachment`, `SupportComment` | `HD-XXXX` |
| **verification** | `VerificationRequest`, `VerificationDocument`, `VerifiedBadge` | `AD-XXXX` |
| **promo** | `PromoRequest`, `PromoAsset`, `PromoAdPrice` | `MD-XXXX` |
| **subscriptions** | `SubscriptionPlan`, `Subscription` | — |
| **audit** | `AuditLog` (60+ نوع عملية) | — |
| **unified_requests** | `UnifiedRequest`, `UnifiedRequestMetadata` | — |
| **backoffice** | `Dashboard`, `UserAccessProfile` (5 مستويات) | — |

### قاعدة البيانات

| البيئة | المحرك |
|--------|--------|
| التطوير | SQLite3 |
| الإنتاج | PostgreSQL عبر `dj-database-url` (`conn_max_age=600`) |

### الـ Middleware (بالترتيب)

1. `CorsMiddleware`
2. `SecurityMiddleware`
3. `WhiteNoiseMiddleware` (ملفات ثابتة)
4. `SessionMiddleware`
5. `CommonMiddleware`
6. `CsrfViewMiddleware`
7. `AuthenticationMiddleware`
8. **`SubscriptionRefreshMiddleware`** — يُحدّث حالة الاشتراك مع كل طلب مُصادق
9. `MessageMiddleware`
10. `XFrameOptionsMiddleware`
11. `CSPMiddleware` *(إنتاج فقط)*

---

## 6. الأمان والمصادقة

### 🔐 آلية المصادقة

```
[رقم الجوال] → OTP/send → [كود OTP] → OTP/verify → [JWT Access + Refresh]
                                                        ↓
                                              حفظ في SharedPreferences
                                                        ↓
                                            كل طلب API → Bearer Token
```

| العنصر | التفاصيل |
|--------|----------|
| **نوع التوكن** | JWT — Bearer |
| **مدة Access Token** | 60 دقيقة (قابل للتعديل عبر `JWT_ACCESS_MIN`) |
| **مدة Refresh Token** | 30 يوم (قابل للتعديل عبر `JWT_REFRESH_DAYS`) |
| **تجديد تلقائي** | `ApiClient` يعيد المحاولة بتوكن جديد عند 401 |
| **تسجيل الخروج** | يُبطل Refresh Token بالسيرفر + يمسح محلياً |
| **نموذج المستخدم** | `accounts.User` — `USERNAME_FIELD = "phone"` |

### 🛡️ حدود OTP

| القيد | القيمة |
|-------|--------|
| فترة الانتظار بين الإرسال | 60 ثانية |
| الحد الأقصى لكل رقم/ساعة | 5 محاولات |
| الحد الأقصى لكل رقم/يوم | 10 محاولات |
| الحد الأقصى لكل IP/ساعة | 50 محاولة |
| بيئة التطوير | أي كود من 4 أرقام مقبول |
| بيئة الإنتاج | التحقق الحقيقي إجباري |

### ⚡ حدود الاستخدام (Throttling)

| النطاق | الحد |
|--------|------|
| مستخدم مُصادق | **200 طلب/دقيقة** |
| زائر مجهول | **60 طلب/دقيقة** |
| نقاط OTP | **5 طلب/دقيقة** |
| نقاط المصادقة | **15 طلب/دقيقة** |
| تجديد التوكن | **60 طلب/دقيقة** |

### 🔒 أمان الإنتاج

| التدبير | التفاصيل |
|---------|----------|
| SSL | `SECURE_SSL_REDIRECT = True` (يستثني `/health/`) |
| HSTS | 30 يوم + subdomains + preload |
| CSP | `default-src 'self'`، صور من أي HTTPS |
| CORS | قائمة بيضاء: `nawafeth.app`، `admin.nawafeth.app`، `*.onrender.com` |
| Cookies | `SESSION_COOKIE_SECURE + CSRF_COOKIE_SECURE` |
| X-Frame | `DENY` |
| Referrer | `same-origin` |
| Sentry | مراقبة الأخطاء مع `send_default_pii=False` |

### 🔑 تخزين التوكنات في التطبيق

| المفتاح | النوع | المصدر |
|---------|-------|--------|
| `access_token` | String | JWT Access |
| `refresh_token` | String | JWT Refresh |
| `user_id` | int | من OTP verify |
| `role_state` | String | من OTP verify |
| `isProvider` | bool | وضع الحساب النشط |
| `isProviderRegistered` | bool | هل سجّل كمزود |

> ⚠️ **ملاحظة أمنية:** يُخزن حالياً في `SharedPreferences` (غير مشفر). يُنصح بالترقية إلى `flutter_secure_storage` لبيئة الإنتاج.

---

## 7. طبقة API والخدمات

### بنية `ApiClient` — الأساس

```dart
ApiClient
├── baseUrl        ← من AppEnv.apiBaseUrl
├── get(path)      ← GET + Bearer Auth
├── post(path, body) ← POST + JSON
├── patch(path, body) ← PATCH + JSON
├── put(path, body)   ← PUT + JSON
├── delete(path)      ← DELETE + Bearer Auth
├── _request()     ← المنطق المركزي:
│   ├── إضافة Authorization header تلقائياً
│   ├── Timeout: 15 ثانية
│   ├── تجديد التوكن تلقائياً عند 401
│   └── معالجة أخطاء الاتصال
├── parseResponse() ← تحليل JSON + فصل النجاح/الخطأ
└── buildMediaUrl() ← بناء URL كامل للوسائط
```

### جدول الخدمات

| الخدمة | الملف | الأساليب | تدعم Mode |
|--------|-------|----------|-----------|
| `AuthService` | `auth_service.dart` | حفظ/قراءة التوكنات، تسجيل الخروج | ❌ |
| `AuthApiService` | `auth_api_service.dart` | `sendOtp`, `verifyOtp`, `completeRegistration` | ❌ |
| `AccountModeService` | `account_mode_service.dart` | `isProviderMode`, `setProviderMode`, `apiMode` | — |
| `ProfileService` | `profile_service.dart` | user/provider fetch + update (4 methods) | ❌ |
| `HomeService` | `home_service.dart` | categories, providers, banners | ❌ |
| `MarketplaceService` | `marketplace_service.dart` | 17 method — CRUD طلبات/عروض/عاجل/تنافسي | ❌ |
| `MessagingService` | `messaging_service.dart` | 12 method — threads, messages, reports | ✅ `mode` |
| `NotificationService` | `notification_service.dart` | 11 method — كلها تدعم `mode` | ✅ `mode` |
| `InteractiveService` | `interactive_service.dart` | following, followers, favorites | ❌ |
| `ReviewsService` | `reviews_service.dart` | reviews, rating, reply | ❌ |
| `ProviderServicesService` | `provider_services_service.dart` | CRUD خدمات المزود | ❌ |
| `SubscriptionsService` | `subscriptions_service.dart` | plans, subscribe | ❌ |
| `PromoService` | `promo_service.dart` | إعلانات — إنشاء، قائمة، رفع أصول | ❌ |
| `VerificationService` | `verification_service.dart` | طلبات التوثيق + رفع مستندات | ❌ |

### نمط رفع الملفات (Multipart)

```dart
// يُستخدم في: Messaging, Marketplace, Promo, Verification
http.MultipartRequest('POST', uri)
  ..headers['Authorization'] = 'Bearer $token'
  ..files.add(await http.MultipartFile.fromPath('file', filePath))
  ..fields['field'] = 'value'
// Timeout: 30-60 ثانية حسب الخدمة
```

---

## 8. التنقل والمسارات

### المسارات المُسمّاة (`main.dart`)

| المسار | الشاشة | الحماية |
|--------|--------|---------|
| `/onboarding` | `OnboardingScreen` | — (شاشة البداية) |
| `/home` | `HomeScreen` | — |
| `/chats` | `MyChatsScreen` | — |
| `/orders` | `OrdersHubScreen` | — (يوزّع حسب الوضع) |
| `/interactive` | `InteractiveScreen` | — |
| `/profile` | `MyProfileScreen` | — |
| `/login` | `LoginScreen` | — |
| `/add_service` | `AddServiceScreen` | 🔒 `_ModeRouteGuard(allowProviderMode: false)` |
| `/search_provider` | `SearchProviderScreen` | 🔒 `_ModeRouteGuard(allowProviderMode: false)` |
| `/urgent_request` | `UrgentRequestScreen` | 🔒 `_ModeRouteGuard(allowProviderMode: false)` |
| `/request_quote` | `RequestQuoteScreen` | 🔒 `_ModeRouteGuard(allowProviderMode: false)` |

### نمط التنقل

```dart
// تنقل بين الشاشات الرئيسية — replacement (لا يرجع)
Navigator.pushReplacementNamed(context, '/home');

// تنقل لشاشات فرعية — push (يرجع)
Navigator.push(context, MaterialPageRoute(builder: (_) => Screen()));

// تسجيل الخروج — إزالة كل المسارات
Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => LoginScreen()), (_) => false);
```

### نظام الحماية المزدوج

```
المستوى 1: Route Guard (_ModeRouteGuard في main.dart)
    ↓ يمرر
المستوى 2: Screen Guard (_ensureClientAccount/_ensureProviderAccount في الشاشة)
    ↓ يمرر
عرض المحتوى
```

---

## 9. نظام عزل الحسابات

### المفهوم

التطبيق يدعم حسابين لنفس المستخدم: **عميل** و **مزود خدمة**. يتم الفصل الصارم بينهما:

### `AccountModeService` — المصدر المركزي

```dart
class AccountModeService {
  // قراءة الوضع الحالي
  static Future<bool> isProviderMode();

  // تعيين الوضع
  static Future<void> setProviderMode(bool isProvider);

  // للاستخدام في طلبات API
  static Future<String> apiMode(); // → 'client' أو 'provider'
}
```

### ما يتأثر بالوضع

| المكوّن | سلوك العميل | سلوك المزود |
|---------|-------------|-------------|
| **الشريط السفلي** | يظهر "طلباتي" | يختفي "طلباتي" |
| **صفحة الطلبات** | `ClientOrdersScreen` | `ProviderOrdersScreen` |
| **نافذتي (البروفايل)** | ملف العميل | `ProviderHomeScreen` |
| **الإشعارات** | `mode=client` | `mode=provider` |
| **المحادثات** | `mode=client` | `mode=provider` |
| **تفاعلي** | 2 تبويبات | 3 تبويبات (+ المتابعون) |
| **إعدادات الإشعارات** | تفضيلات العميل | تفضيلات المزود |
| **المسارات المحمية** | متاحة | محجوبة + تحويل |

### قواعد إلزامية للعزل

1. **قراءة الوضع:** دائماً عبر `AccountModeService` — **لا تقرأ `SharedPreferences` مباشرة**
2. **API Mode:** أضف `mode` parameter لأي endpoint يعرض بيانات مختلفة حسب الدور
3. **حماية الشاشات:** كل شاشة خاصة بدور يجب أن تحتوي على guard
4. **التبديل:** يحدث فقط في `MyProfileScreen` و `ProviderHomeScreen`

---

## 10. النماذج (Models)

### النماذج النشطة (مع `fromJson`)

| النموذج | الملف | مصدر API | الحقول الرئيسية |
|---------|-------|----------|-----------------|
| `UserProfile` | `user_profile.dart` | `/api/accounts/me/` | 21 حقل — بيانات شخصية + إحصائيات المزود |
| `ProviderProfileModel` | `provider_profile_model.dart` | `/api/providers/me/profile/` | 28 حقل — ملف كامل مع نسبة الإكمال |
| `ProviderPublicModel` | `provider_public_model.dart` | `/api/providers/list/` | 21 حقل — العرض العام للمزود |
| `UserPublicModel` | `user_public_model.dart` | — | مستخدم مُبسّط (متابعون) |
| `ServiceRequest` | `service_request_model.dart` | `/api/marketplace/...` | 40+ حقل — النموذج الموحد للطلبات |
| `ChatThread` | `chat_thread_model.dart` | `/api/messaging/...` | معلومات المحادثة + حالات |
| `ChatMessage` | `chat_message_model.dart` | `/api/messaging/...` | رسالة + مرفقات + إيصالات القراءة |
| `NotificationModel` | `notification_model.dart` | `/api/notifications/` | إشعار مع pin/follow-up/mode |
| `NotificationPreference` | `notification_model.dart` | `/api/notifications/preferences/` | تفضيل مع tier locking |
| `CategoryModel` | `category_model.dart` | `/api/providers/categories/` | تصنيف + تصنيفات فرعية |
| `BannerModel` | `banner_model.dart` | `/api/promo/banners/home/` | بانر إعلاني |
| `MediaItemModel` | `media_item_model.dart` | — | عنصر وسائط (معرض/spotlight) |
| `ServiceProviderLocation` | `service_provider_location.dart` | — | موقع على الخريطة |

### النماذج القديمة (بدون `fromJson` — للواجهة فقط)

| النموذج | الملف | الملاحظة |
|---------|-------|----------|
| `ClientOrder` | `client_order.dart` | **قديم** — يُستبدل بـ `ServiceRequest` |
| `ProviderOrder` | `provider_order.dart` | **قديم** — يُستبدل بـ `ServiceRequest` |
| `Ticket` | `ticket_model.dart` | **للواجهة** — غير مربوط بـ API بعد |

### نمط تحليل JSON

```dart
// النمط المُتّبع في جميع النماذج:
factory Model.fromJson(Map<String, dynamic> json) {
  return Model(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    rating: _parseDouble(json['rating_avg']),  // helper method
  );
}

// helpers شائعة:
static double _parseDouble(dynamic v) { ... }  // يتعامل مع String/num/null
static int _parseInt(dynamic v) { ... }
static bool _parseBool(dynamic v) { ... }
static String _parseString(dynamic v) { ... }
```

---

## 11. التخزين المؤقت والأداء

### ⚠️ الوضع الحالي

| الطبقة | حالة التخزين المؤقت |
|--------|---------------------|
| **Frontend (Flutter)** | ❌ لا يوجد cache layer — كل فتح شاشة = طلب API جديد |
| **Backend (Django)** | ❌ `LocMemCache` (افتراضي) — لا Redis/Memcached cache |
| **HTTP** | ❌ لا يوجد ETag/Last-Modified أو Cache-Control headers |

### ✅ أنماط الأداء المُطبّقة حالياً

| النمط | التفاصيل | الموقع |
|-------|----------|--------|
| **`Future.wait`** | تحميل بيانات متعددة بالتوازي | `HomeScreen`, `InteractiveScreen`, `ServicesTab` |
| **`RefreshIndicator`** | سحب لتحديث البيانات يدوياً | `HomeScreen`, `ClientOrdersScreen` |
| **Infinite Scroll** | تحميل تدريجي عند الوصول لنهاية القائمة | `NotificationsScreen` (limit/offset) |
| **`mounted` guard** | يمنع setState بعد dispose | كل شاشة StatefulWidget |
| **Timeout** | 15 ثانية للطلبات العادية، 30-60 للملفات | `ApiClient`, Multipart uploads |
| **`DebouncedSaveRunner`** | تأخير الحفظ 700ms لتجنب طلبات متكررة | `debounced_save_runner.dart` |
| **`embedded` flag** | الشاشات تعمل standalone أو مُضمّنة بدون إعادة بناء shell | orders, reviews_tab |
| **تحميل شرطي** | followers تُحمّل فقط في وضع المزود | `InteractiveScreen` |
| **Video لا صوت** | فيديو الخلفية `setVolume(0)` + `setLooping(true)` | `HomeScreen` |

### 🎯 توصيات الأداء (للتطبيق المستقبلي)

| التوصية | الأولوية | التأثير |
|---------|----------|---------|
| إضافة **طبقة cache محلية** للبيانات المتكررة (categories, profile) | عالية | تقليل طلبات API بنسبة 40%+ |
| استخدام **`cached_network_image`** لصور المزودين | عالية | تقليل استهلاك البيانات |
| إضافة **Redis cache** للبيانات الثابتة في Backend | متوسطة | تسريع الاستجابة |
| تفعيل **ETag / If-Modified-Since** | متوسطة | تقليل حجم الاستجابات |
| استخدام **`flutter_secure_storage`** بدل SharedPreferences | عالية | أمان التوكنات |
| إضافة **Pagination** لكل قوائم الخدمات والمزودين | متوسطة | تقليل حجم الاستجابة الأولية |
| **Connection pooling** في ApiClient | منخفضة | تقليل latency |

---

## 12. أنماط التطوير المتبعة

### أنماط Flutter

| النمط | التفاصيل |
|-------|----------|
| **Static Services** | كل الخدمات تستخدم static methods — بدون DI أو Instance |
| **InheritedWidget** | `MyThemeController` للثيم واللغة |
| **StatefulWidget** | أغلب الشاشات — مع `mounted` checks |
| **Screen Guards** | فحص الدور في `initState` مع `addPostFrameCallback` للتحويل |
| **مخاطبة الـ API** | الشاشة → Service (static) → ApiClient → Backend |
| **Result Wrappers** | `ProfileResult<T>`, `ListResult<T>`, `ApiResponse` |
| **تحميل/خطأ/بيانات** | كل شاشة تدير 3 حالات: `_isLoading`, `_errorMessage`, data |
| **Silent Reload** | `_loadData({bool silent = false})` — لا يظهر مؤشر تحميل عند التحديث |
| **Arabic→API Mapping** | Maps ثابتة لتحويل حالات عربية إلى قيم API |

### أنماط Django

| النمط | التفاصيل |
|-------|----------|
| **Phone-first Identity** | لا بريد/كلمة مرور — كل شيء عبر الجوال + OTP |
| **Auto-generated Codes** | رموز مقروءة (IV, HD, AD, MD) تُنشأ تلقائياً |
| **Unified Request Engine** | كل أنواع الطلبات تُجمع في محرك واحد |
| **Multi-tier RBAC** | 5 مستويات وصول في BackOffice |
| **Subscription Middleware** | تحديث حالة الاشتراك مع كل طلب |
| **Comprehensive Audit** | 60+ نوع عملية مُسجّلة |
| **Saudi VAT** | ضريبة 15% مُدمجة في الفوترة |
| **WebSocket** | Django Channels + Daphne للرسائل الفورية |

---

## 13. قواعد إلزامية قبل أي تعديل

### ❗ قواعد عامة

1. **اللغة:** كل النصوص المرئية بالعربية أولاً — الكود والتعليقات بالعربية مقبولة
2. **الخط:** دائماً `fontFamily: 'Cairo'` — لا تستخدم خط آخر
3. **الاتجاه:** كل شيء RTL — اختبر الاتجاه بعد أي تعديل بصري
4. **الثيم:** ادعم Light + Dark — استخدم `isDark` check في build
5. **الألوان:** استخدم `AppColors` و `Colors.deepPurple` — لا تختلق ألوان جديدة
6. **التحقق:** شغّل `flutter analyze --no-pub` بعد كل تعديل — **صفر أخطاء شرط**

### ❗ قواعد الأمان

7. **التوكن:** لا تطبع/تسجل access أو refresh token إلا في بيئة التطوير
8. **الوضع:** اقرأ الوضع (client/provider) عبر `AccountModeService` فقط
9. **Guards:** كل شاشة خاصة بدور تحتاج guard — استخدم النمط الموجود
10. **API Auth:** كل endpoint جديد يجب أن يمر عبر `ApiClient` — لا `http.get` مباشر
11. **Multipart:** استخدم timeout ≥ 30 ثانية لرفع الملفات
12. **OTP:** لا تقبل أي كود في الإنتاج — `OTP_DEV_ACCEPT_ANY_CODE` يجب أن يكون False

### ❗ قواعد الأداء

13. **mounted:** تحقق من `mounted` قبل كل `setState`
14. **dispose:** تخلص من Controllers و Timers و Subscriptions في `dispose()`
15. **Future.wait:** إذا كنت تحمّل بيانات مستقلة — حمّلها بالتوازي
16. **embedded:** إذا الشاشة تعمل standalone ومُضمّنة — استخدم `embedded` flag
17. **تحميل صامت:** استخدم `silent` flag عند إعادة التحميل بدون مؤشر
18. **لا تكرر API:** لا تطلب نفس البيانات في `initState` + `build`

### ❗ قواعد الهيكلية

19. **النماذج:** أنشئ model مع `fromJson` لأي بيانات API جديدة
20. **الخدمات:** أنشئ service في `lib/services/` — كل methods static
21. **الشاشات:** ضعها في `lib/screens/` (أو مجلد فرعي للمجموعات)
22. **Widgets:** المكوّنات المشتركة في `lib/widgets/`
23. **ثوابت:** ألوان في `colors.dart`، نصوص في `app_texts.dart`
24. **Import style:** استخدم `import '../relative/path.dart'` للمشروع المحلي

### ❗ قواعد Backend

25. **Endpoints:** اتبع نمط `/api/{app}/{resource}/` — REST conventions
26. **Serializers:** Field-level validation في Serializer — لا في View
27. **Audit:** سجّل كل عملية مهمة في `AuditLog`
28. **الضريبة:** كل مبلغ مالي يشمل VAT 15% — لا تنسَ
29. **Pagination:** استخدم `LimitOffsetPagination` لكل list endpoint
30. **Mode:** إذا البيانات تختلف بين عميل/مزود — أضف `?mode=` parameter

---

## 14. مصفوفة نقاط الـ API

### المصادقة (`/api/accounts/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/otp/send/` | POST | إرسال OTP |
| `/otp/verify/` | POST | التحقق → JWT |
| `/complete/` | POST | إكمال التسجيل |
| `/me/` | GET/PATCH | بيانات المستخدم |
| `/token/refresh/` | POST | تجديد التوكن |
| `/logout/` | POST | إبطال Refresh Token |
| `/delete/` | DELETE | حذف الحساب |

### المزودون (`/api/providers/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/categories/` | GET | قائمة التصنيفات |
| `/list/` | GET | قائمة المزودين (عام) |
| `/me/profile/` | GET/PATCH | ملف المزود الخاص |
| `/me/services/` | GET/POST | خدمات المزود |
| `/me/services/{id}/` | PATCH/DELETE | تعديل/حذف خدمة |
| `/me/following/` | GET | من أتابعهم |
| `/me/followers/` | GET | متابعوني |
| `/me/favorites/` | GET | المفضلات (معرض) |
| `/me/favorites/spotlights/` | GET | المفضلات (spotlights) |
| `/{id}/follow/` | POST | متابعة مزود |
| `/{id}/unfollow/` | POST | إلغاء المتابعة |

### السوق (`/api/marketplace/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/requests/create/` | POST | إنشاء طلب (multipart) |
| `/client/requests/` | GET | طلبات العميل |
| `/client/requests/{id}/` | GET/PATCH | تفاصيل/تعديل طلب عميل |
| `/provider/requests/` | GET | طلبات المزود |
| `/provider/requests/{id}/detail/` | GET | تفاصيل طلب للمزود |
| `/provider/requests/{id}/accept/` | POST | قبول طلب |
| `/provider/requests/{id}/reject/` | POST | رفض طلب |
| `/requests/{id}/start/` | POST | بدء التنفيذ |
| `/provider/requests/{id}/progress-update/` | POST | تحديث التقدم |
| `/requests/{id}/complete/` | POST | إتمام الطلب |
| `/provider/urgent/available/` | GET | طلبات عاجلة متاحة |
| `/requests/urgent/accept/` | POST | قبول طلب عاجل |
| `/provider/competitive/available/` | GET | طلبات تنافسية متاحة |
| `/requests/{id}/offers/create/` | POST | تقديم عرض |
| `/requests/{id}/offers/` | GET | عروض الطلب |
| `/offers/{id}/accept/` | POST | قبول عرض |

### المحادثات (`/api/messaging/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/direct/threads/` | GET | قائمة المحادثات |
| `/threads/states/` | GET | حالات المحادثات |
| `/direct/thread/{id}/messages/` | GET | رسائل محادثة |
| `/direct/thread/{id}/messages/send/` | POST | إرسال رسالة |
| `/direct/thread/{id}/messages/read/` | POST | تحديد كمقروء |
| `/thread/{id}/unread/` | POST | تحديد كغير مقروء |
| `/thread/{id}/favorite/` | POST | تفضيل |
| `/thread/{id}/block/` | POST | حظر |
| `/thread/{id}/archive/` | POST | أرشفة |
| `/thread/{id}/report/` | POST | إبلاغ |
| `/thread/{id}/messages/{mid}/delete/` | POST | حذف رسالة |
| `/direct/thread/` | POST | إنشاء/فتح محادثة مباشرة |

### الإشعارات (`/api/notifications/`)

| Endpoint | Method | الوصف | Mode |
|----------|--------|-------|------|
| `/` | GET | قائمة الإشعارات | ✅ |
| `/unread-count/` | GET | عداد غير المقروءة | ✅ |
| `/mark-read/{id}/` | POST | قراءة إشعار | ✅ |
| `/mark-all-read/` | POST | قراءة الكل | ✅ |
| `/actions/{id}/` | POST/DELETE | تثبيت/متابعة/حذف | ✅ |
| `/preferences/` | GET/PATCH | تفضيلات الإشعارات | ✅ |
| `/device-token/` | POST | تسجيل توكن الجهاز | ❌ |
| `/delete-old/` | POST | حذف القديمة | ✅ |

### التقييمات (`/api/reviews/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/providers/{id}/reviews/` | GET | تقييمات مزود |
| `/providers/{id}/rating/` | GET | متوسط التقييم |
| `/reviews/{id}/provider-reply/` | POST | رد المزود |

### الاشتراكات (`/api/subscriptions/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/plans/` | GET | قائمة الخطط |
| `/my/` | GET | اشتراكاتي |
| `/subscribe/{id}/` | POST | اشتراك |

### الإعلانات (`/api/promo/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/requests/create/` | POST | إنشاء طلب إعلان |
| `/requests/my/` | GET | طلباتي الإعلانية |
| `/requests/{id}/` | GET | تفاصيل طلب |
| `/requests/{id}/assets/` | POST | رفع أصول (multipart) |
| `/banners/home/` | GET | بانرات الصفحة الرئيسية |

### التوثيق (`/api/verification/`)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/requests/create/` | POST | طلب توثيق |
| `/requests/my/` | GET | طلباتي |
| `/requests/{id}/` | GET | تفاصيل |
| `/requests/{id}/documents/` | POST | رفع مستندات (multipart) |

---

## 15. البيئات والنشر

### بيئة API (`AppEnv`)

```dart
// التحكم عبر --dart-define:
// flutter run --dart-define=API_TARGET=local     → محلي
// flutter run --dart-define=API_TARGET=render    → السيرفر
// flutter run --dart-define=API_TARGET=auto      → تلقائي (افتراضي)

// الافتراضيات حسب المنصة:
// Android Emulator → http://10.0.2.2:8000
// iOS/Desktop      → http://127.0.0.1:8000
// Web              → http://localhost:8000
// Render           → https://nawafeth-2290.onrender.com
```

### إعداد Backend

```bash
# تطوير
cd backend
python manage.py runserver 0.0.0.0:8000

# إنتاج (Render)
# render.yaml يحدد build + start commands
# DJANGO_ENV=prod
# DATABASE_URL → PostgreSQL
# SENTRY_DSN → مراقبة الأخطاء
```

### ملفات النشر

| الملف | الوظيفة |
|-------|---------|
| `render.yaml` (root) | تعريف خدمة Render |
| `backend/render.yaml` | إعدادات backend على Render |
| `backend/scripts/render_build.sh` | بناء الإنتاج |
| `backend/scripts/render_start.sh` | تشغيل الإنتاج |

---

## 16. الملحقات

### خريطة التبعيات (Flutter)

| المكتبة | الإصدار | الاستخدام |
|---------|---------|-----------|
| `http` | ^1.2.0 | HTTP Client |
| `shared_preferences` | ^2.3.3 | تخزين محلي |
| `video_player` | ^2.9.2 | تشغيل الفيديو |
| `image_picker` | ^1.1.2 | اختيار الصور |
| `file_picker` | ^8.1.2 | اختيار الملفات |
| `flutter_sound` | ^9.2.13 | تسجيل/تشغيل الصوت |
| `permission_handler` | ^11.3.1 | إدارة الأذونات |
| `url_launcher` | ^6.3.1 | فتح روابط خارجية |
| `geolocator` | ^13.0.2 | تحديد الموقع |
| `share_plus` | ^10.1.2 | مشاركة المحتوى |
| `flutter_map` | ^7.0.2 | خرائط OpenStreetMap |
| `latlong2` | ^0.9.1 | إحداثيات جغرافية |
| `flutter_rating_bar` | ^4.0.1 | تقييم بالنجوم |
| `multi_select_flutter` | ^4.1.3 | قوائم اختيار متعدد |
| `font_awesome_flutter` | ^10.7.0 | أيقونات إضافية |
| `animate_do` | ^3.3.4 | مؤثرات حركية |
| `intl` | ^0.20.2 | تنسيق التواريخ والأرقام |

### خريطة التبعيات (Backend)

| المكتبة | الاستخدام |
|---------|-----------|
| Django ≥ 5.0 | الإطار الأساسي |
| djangorestframework ≥ 3.15 | REST API |
| djangorestframework-simplejwt ≥ 5.3 | JWT |
| django-cors-headers ≥ 4.3 | CORS |
| django-filter ≥ 24.0 | فلترة |
| django-csp ≥ 3.7 | سياسة المحتوى |
| channels ≥ 4.1 | WebSocket |
| daphne ≥ 4.1 | خادم ASGI |
| psycopg[binary] ≥ 3.1 | PostgreSQL |
| whitenoise ≥ 6.6 | ملفات ثابتة |
| Pillow ≥ 10.0 | معالجة الصور |
| sentry-sdk ≥ 2.0 | مراقبة الأخطاء |
| openpyxl 3.1.5 | تصدير Excel |
| reportlab 4.2.2 | توليد PDF |
| arabic-reshaper 3.0.0 | تشكيل النص العربي |
| python-bidi 0.4.2 | نص ثنائي الاتجاه |

### مخطط دورة حياة الطلب

```
[عميل] → إنشاء طلب (normal/urgent/competitive)
    ↓
[مزود] → قبول / رفض
    ↓ (قبول)
[مزود] → بدء التنفيذ (start) + تعديل مبالغ/تواريخ
    ↓
[مزود] → تحديث التقدم (progress-update)
    ↓
[مزود] → إتمام (complete) + مبلغ فعلي + تاريخ فعلي
    ↓
[عميل] → تقييم (review) — 5 محاور
    ↓
[النظام] → فاتورة (invoice) + سجل مراجعة (audit)
```

### أنواع الطلبات الثلاثة

| النوع | الوصف | آلية القبول |
|-------|-------|-------------|
| **عادي (normal)** | العميل يختار مزود ويطلب مباشرة | المزود يقبل/يرفض |
| **عاجل (urgent)** | طلب مستعجل يظهر لكل المزودين المتاحين | أول مزود يقبل يفوز |
| **تنافسي (competitive)** | طلب عروض أسعار من عدة مزودين | العميل يختار أفضل عرض |

---

> **⚙️ آخر تحقق:** `flutter analyze --no-pub` → **No issues found** ✅  
> **📋 هذا المرجع يُحدّث مع كل تغيير هيكلي في المشروع**
