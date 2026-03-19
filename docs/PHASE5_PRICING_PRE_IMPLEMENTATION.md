# Phase 5 — Pricing & Tax Centralization: تقرير ما قبل التنفيذ

> **تاريخ الإعداد:** مارس 2026  
> **الحالة:** مُعدّ للمراجعة قبل التنفيذ

---

## 1. الوضع الحالي — مصادر التسعير

| المصدر | النوع | المشكلة |
|--------|-------|---------|
| `settings.EXTRA_SKUS` | Hardcoded dict | أسعار الإضافات ثابتة في الكود — لا يمكن تعديلها من Admin |
| `settings.PROMO_BASE_PRICES` | Hardcoded dict | أسعار الترويج القديمة ثابتة — مكررة مع `PlatformConfig.promo_base_prices` |
| `SubscriptionPlan.verification_*_fee` | DB model | رسوم التوثيق مربوطة بالباقة — تعمل ✅ |
| `SubscriptionPlan.price` | DB model | أسعار الاشتراك مُدارة من Admin — تعمل ✅ |
| `PromoPricingRule` | DB model | تسعير الترويج الجديد (service-based) — يعمل ✅ |
| `PromoAdPrice` | DB model | أسعار الترويج القديم (per ad_type) — يعمل ✅ |
| `PlatformConfig.vat_percent` | Singleton | ضريبة عامة — تعمل ✅ |
| `PlatformConfig.promo_vat_percent` | Singleton | ضريبة الترويج — تعمل ✅ |
| `PlatformConfig.promo_base_prices` | JSONField | مكرر مع `settings.PROMO_BASE_PRICES` |

### ما يعمل ولا يحتاج تغيير

- **SubscriptionPlan**: أسعار الباقات + رسوم التوثيق — مُدارة من Admin ✅
- **PromoPricingRule**: الترويج الجديد بالقواعد — يعمل من Admin ✅
- **PromoAdPrice**: الترويج القديم (per ad_type) — يعمل من Admin ✅
- **PlatformConfig.vat_percent** و **promo_vat_percent** — مُدارة من Admin ✅
- **Invoice.recalc()** — حساب VAT مركزي يعمل ✅

### ما يحتاج تغيير

| الفجوة | التأثير |
|--------|---------|
| `EXTRA_SKUS` hardcoded في settings | لا يمكن تعديل أسعار الإضافات بدون deploy |
| لا يوجد `extras_vat_percent` | الإضافات تستخدم default الفاتورة (15%) بدلاً من قيمة مُدارة |
| لا يوجد `VerificationPricingRule` | رسوم التوثيق الأساسية مخزنة في `bootstrap.py` — القراءة تمر عبر `canonical_subscription_plan_for_tier(BASIC)` وهو نمط غير مباشر |
| لا توجد طبقة تسعير مركزية | كل service يحسب الـ VAT/subtotal/total بشكل مستقل |

---

## 2. Schema النماذج الجديدة

### 2.1 `ServiceCatalog` — كتالوج الخدمات الإضافية

**الموقع:** `apps/extras/models.py`  
**الهدف:** استبدال `settings.EXTRA_SKUS` بنموذج DB قابل للإدارة من Admin

```python
class ServiceCatalog(models.Model):
    sku = models.CharField(max_length=80, unique=True)       # uploads_10gb_month
    title = models.CharField(max_length=160)                  # زيادة سعة مرفقات 10GB (شهري)
    extra_type = models.CharField(max_length=20, choices=ExtraType.choices, default=ExtraType.TIME_BASED)
    price = models.DecimalField(max_digits=12, decimal_places=2)  # 59.00
    credits = models.PositiveIntegerField(default=0)          # tickets_100 → 100
    duration_days = models.PositiveIntegerField(default=30)   # مدة الصلاحية
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)
```

**Admin:** list_display سيشمل sku, title, price, extra_type, is_active  
**Migration:** ستزرع بيانات `EXTRA_SKUS` الحالية كصفوف أولية

### 2.2 `VerificationPricingRule` — قواعد تسعير التوثيق

**الموقع:** `apps/verification/models.py`  
**الهدف:** فصل رسوم التوثيق الأساسية عن الباقات — مرجع مستقل قابل للإدارة

```python
class VerificationPricingRule(models.Model):
    badge_type = models.CharField(max_length=10, choices=VerificationBadgeType.choices, unique=True)
    base_fee = models.DecimalField(max_digits=12, decimal_places=2)     # الرسم الأساسي (100.00)
    tax_inclusive = models.BooleanField(default=True)                     # هل السعر شامل الضريبة
    is_active = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)
```

**Admin:** list_display سيشمل badge_type, base_fee, tax_inclusive, is_active  
**الاستخدام:** `_fee_for_badge()` ستقرأ أولاً من `VerificationPricingRule` — إذا غير موجود ترجع للباقة الأساسية (backward compat)

### 2.3 `PlatformConfig` — إضافة `extras_vat_percent`

**الموقع:** `apps/core/models.py` (حقل جديد على النموذج الموجود)

```python
extras_vat_percent = models.DecimalField(
    "نسبة ضريبة الخدمات الإضافية (%)",
    max_digits=5, decimal_places=2, default=Decimal("15.00"),
)
```

**Admin:** سيُضاف تحت fieldset "الخدمات الإضافية"

---

## 3. طبقة التسعير المركزية (Pricing Service Layer)

**الموقع:** `apps/billing/pricing.py` (ملف جديد)  
**السبب:** `billing` هو التطبيق الأنسب — يمتلك Invoice و InvoiceLineItem ويُستخدم من جميع الخدمات

### الدوال:

```python
# ── VAT ──
def apply_vat(subtotal: Decimal, vat_percent: Decimal) -> dict:
    """يُرجع {subtotal, vat_percent, vat_amount, total}"""

# ── Extras ──
def calculate_extras_price(sku: str) -> dict:
    """يقرأ من ServiceCatalog أولاً، ثم EXTRA_SKUS كـ fallback"""
    """يُرجع {subtotal, vat_percent, vat_amount, total, currency, title}"""

# ── Verification ──
def calculate_verification_price(badge_type: str, user=None) -> dict:
    """يقرأ من VerificationPricingRule أولاً، ثم الباقة كـ fallback"""
    """يُرجع {amount, tax_inclusive, vat_percent, currency}"""

# ── Promo (delegation فقط) ──
def calculate_promo_price(promo_request) -> dict:
    """يفوّض إلى calc_promo_quote الموجودة — لا إعادة كتابة"""
    """يُضيف VAT من PlatformConfig.promo_vat_percent"""

# ── Utility ──
def get_vat_percent(service_type: str) -> Decimal:
    """يُرجع نسبة الضريبة حسب نوع الخدمة من PlatformConfig"""
```

### قرارات التصميم:

| القرار | السبب |
|-------|-------|
| ملف واحد `billing/pricing.py` | مكان طبيعي بجوار Invoice — يتجنب circular imports |
| Fallback دائماً | `ServiceCatalog` → `settings.EXTRA_SKUS` — لا كسر |
| لا إعادة كتابة promo | `PromoPricingRule` + `calc_promo_quote()` تعمل جيداً |
| delegation pattern | الطبقة تُغلّف المصادر الحالية ولا تستبدلها |

---

## 4. نقاط الربط التي ستتأثر

### 4.1 `extras/services.py`

| الدالة | التغيير |
|--------|---------|
| `get_extra_catalog()` | ستقرأ من `ServiceCatalog.objects.filter(is_active=True)` أولاً، ثم `settings.EXTRA_SKUS` كـ fallback |
| `sku_info()` | نفس المنطق — DB أولاً |
| `create_extra_purchase_checkout()` | ستستخدم `calculate_extras_price()` بدلاً من قراءة `info["price"]` مباشرة |
| `infer_extra_type()` | سيقرأ `extra_type` من `ServiceCatalog` إذا وُجد |
| `infer_duration()` | سيقرأ `duration_days` من `ServiceCatalog` إذا وُجد |
| `infer_credits()` | سيقرأ `credits` من `ServiceCatalog` إذا وُجد |

### 4.2 `verification/services.py`

| الدالة | التغيير |
|--------|---------|
| `_fee_for_badge()` | ستقرأ من `VerificationPricingRule` أولاً، ثم canonical plan كـ fallback |

### 4.3 `billing` Invoice creation

| الموقع | التغيير |
|--------|---------|
| `extras/services.py:create_extra_purchase_checkout()` | ستستخدم `get_vat_percent("extras")` بدلاً من default |
| `promo/services.py:_sync_invoice_from_items()` | لا تغيير — تستخدم `PlatformConfig.promo_vat_percent` بالفعل ✅ |
| `verification/services.py:finalize_request_and_create_invoice()` | لا تغيير — `VERIFICATION_ADDITIONAL_VAT_PERCENT=0.00` صحيح (tax-inclusive) ✅ |

### 4.4 `core/admin.py` — PlatformConfig Admin

| التغيير |
|---------|
| إضافة `extras_vat_percent` في fieldset "الخدمات الإضافية" |

---

## 5. خطة Migration الآمنة

### Migration 1: `extras/0002_servicecatalog.py`
```
1. إنشاء جدول ServiceCatalog
2. RunPython: زرع بيانات من settings.EXTRA_SKUS (5 صفوف)
3. Reverse: حذف الصفوف المزروعة
```

### Migration 2: `verification/0002_verificationpricingrule.py`
```
1. إنشاء جدول VerificationPricingRule
2. RunPython: زرع blue=100.00 و green=100.00 (الرسوم الأساسية الحالية)
3. Reverse: حذف الصفوف المزروعة
```

### Migration 3: `core/0003_platformconfig_extras_vat_percent.py`
```
1. AddField: extras_vat_percent (default=15.00)
```

### ترتيب التنفيذ:
```
extras 0002 → verification 0002 → core 0003
    ↓
pricing.py (service layer)
    ↓
wire extras/services.py
    ↓
wire verification/services.py
    ↓
admin registrations
    ↓
tests
```

---

## 6. التوافق العكسي (Backward Compatibility)

| المكون | الإستراتيجية |
|--------|-------------|
| `settings.EXTRA_SKUS` | يبقى كـ fallback — لا يُحذف |
| `settings.PROMO_BASE_PRICES` | يبقى — لا يتأثر (promo يعمل من `PromoPricingRule`) |
| `PlatformConfig.promo_base_prices` (JSON) | يبقى — legacy ولا يُحذف |
| `_fee_for_badge()` fallback | يبقى canonical plan fallback عند عدم وجود `VerificationPricingRule` |
| `get_extra_catalog()` | DB أولاً → settings fallback |
| `infer_extra_type/duration/credits` | DB أولاً → inference من SKU string كـ fallback |
| VAT على invoices | يُمرر صراحة من `get_vat_percent()` — لا تغيير على `Invoice.recalc()` |

**القاعدة:** أي مكون جديد يقرأ من DB أولاً، وإذا لم يجد بيانات يرجع للسلوك السابق — **لا كسر**.

---

## 7. ما لن يتغير

| المكون | السبب |
|--------|-------|
| `SubscriptionPlan.price` | يُدار من Admin بالفعل ✅ |
| `SubscriptionPlan.verification_*_fee` | ستبقى — لكن `VerificationPricingRule` سيكون المرجع الأساسي |
| `PromoPricingRule` | يعمل من Admin بالفعل ✅ |
| `PromoAdPrice` | يعمل من Admin بالفعل ✅ |
| `calc_promo_quote()` / `calc_promo_item_quote()` | لا إعادة كتابة — تعمل جيداً |
| `Invoice.recalc()` | لا تغيير |
| القوالب | لا تغيير (خارج النطاق صراحةً) |
| بوابة العميل | لا تغيير (خارج النطاق صراحةً) |

---

## 8. ملخص التأثير

| المكون | عمليات الكتابة | عمليات القراءة |
|--------|---------------|---------------|
| **نماذج جديدة** | 2 (ServiceCatalog + VerificationPricingRule) |  |
| **حقول جديدة** | 1 (extras_vat_percent على PlatformConfig) |  |
| **Migrations** | 3 |  |
| **Service Layer** | 1 ملف جديد (billing/pricing.py) | ~5 دوال |
| **ملفات مُعدّلة** | | extras/services.py, verification/services.py, core/admin.py, extras/admin.py, verification/admin.py |
| **ملفات لن تتأثر** | | promo/*, subscriptions/*, billing/models.py, Invoice |
