# Phase 5 — Pricing & Tax Centralization — تقرير الإنجاز

**التاريخ:** 2026-03-19  
**الحالة:** ✅ مكتمل

---

## 1. الملفات التي تغيّرت

| الملف | نوع التغيير |
|---|---|
| `apps/extras/models.py` | ✅ إضافة `ServiceCatalog` model |
| `apps/verification/models.py` | ✅ إضافة `VerificationPricingRule` model |
| `apps/core/models.py` | ✅ إضافة حقل `extras_vat_percent` إلى `PlatformConfig` |
| `apps/billing/pricing.py` | ✅ **ملف جديد** — طبقة التسعير المركزية |
| `apps/extras/services.py` | ✅ ربط `get_extra_catalog()` و `create_extra_purchase_checkout()` بطبقة التسعير |
| `apps/verification/services.py` | ✅ تحديث `_fee_for_badge()` — DB first via `VerificationPricingRule` |
| `apps/extras/admin.py` | ✅ تسجيل `ServiceCatalogAdmin` |
| `apps/verification/admin.py` | ✅ تسجيل `VerificationPricingRuleAdmin` |
| `apps/core/admin.py` | ✅ إضافة `extras_vat_percent` إلى fieldset الخدمات الإضافية |
| `apps/extras/tests/test_extras.py` | ✅ تحديث الاختبارات لتنظيف `ServiceCatalog` عند استخدام settings fallback |

---

## 2. المايغريشنز المنفذة

| # | التطبيق | اسم المايغريشن | الوصف |
|---|---|---|---|
| 1 | `extras` | `0002_add_service_catalog` | إنشاء جدول `ServiceCatalog` |
| 2 | `extras` | `0003_seed_service_catalog` | بذر 5 عناصر من `settings.EXTRA_SKUS` الحالية |
| 3 | `verification` | `0005_add_verification_pricing_rule` | إنشاء جدول `VerificationPricingRule` |
| 4 | `core` | `0004_add_extras_vat_percent` | إضافة حقل `extras_vat_percent` (default=15%) |

---

## 3. نقاط الربط التي تم تحديثها

### طبقة التسعير المركزية (`billing/pricing.py`)

| الدالة | الوصف |
|---|---|
| `apply_vat(subtotal, vat_percent)` | حساب الضريبة الموحد |
| `get_extras_catalog()` | كتالوج الإضافات — DB first → settings fallback |
| `calculate_extras_price(sku)` | تسعير إضافة واحدة مع VAT من `extras_vat_percent` |
| `calculate_verification_price(badge_type)` | تسعير التوثيق — `VerificationPricingRule` → plan fallback |
| `calculate_promo_price(promo_request=...)` | Delegation إلى `calc_promo_quote` الحالي بصيغة موحدة |
| `get_vat_percent(domain)` | نسبة الضريبة حسب المجال |

### ناتج جميع دوال التسعير (موحد):
```python
{
    "subtotal": Decimal,
    "vat_percent": Decimal,
    "vat_amount": Decimal,
    "total": Decimal,
    "currency": str,
    "meta": dict,   # source, sku/badge_type, etc.
}
```

### نقاط الربط في الكود:
- **`extras/services.py` → `get_extra_catalog()`**: يفوّض إلى `billing.pricing.get_extras_catalog()`
- **`extras/services.py` → `create_extra_purchase_checkout()`**: يستخدم `calculate_extras_price()` ويُمرر `vat_percent` صراحةً إلى Invoice
- **`verification/services.py` → `_fee_for_badge()`**: يبحث أولاً في `VerificationPricingRule` ثم يرجع لـ `SubscriptionPlan`

---

## 4. نتائج الاختبارات

| مجموعة الاختبارات | النتيجة |
|---|---|
| Dashboard | ✅ 183 passed, 1 deselected |
| Backoffice | ✅ 11 passed |
| Extras | ✅ 6 passed |
| Verification + Billing | ✅ 43 passed |
| Promo | ✅ 38 passed |
| **الإجمالي** | **✅ 281 passed, 0 failures** |

---

## 5. Legacy Paths المتبقية intentionally

| المسار | السبب |
|---|---|
| `settings.EXTRA_SKUS` | Fallback عندما تكون `ServiceCatalog` فارغة — لن يُزال حتى التأكد من أن جميع البيئات لديها بيانات DB |
| `SubscriptionPlan.verification_*_fee` | Fallback عندما لا توجد `VerificationPricingRule` نشطة — لن يُزال حتى تفعيل القواعد في كل البيئات |
| `settings.PROMO_BASE_PRICES` / `PROMO_POSITION_MULTIPLIER` / `PROMO_FREQUENCY_MULTIPLIER` | لم يتم لمسها — promo pricing logic لم يُعاد كتابته (delegation فقط) |
| `settings.DEFAULT_VAT_PERCENT` / `PROMO_VAT_PERCENT` | يبقى كـ reference — القيم الفعلية تُقرأ من `PlatformConfig` |

---

## 6. النماذج الجديدة

### `ServiceCatalog` (extras)
```
sku          CharField(80, unique)
title        CharField(160)
price        DecimalField(10,2)
currency     CharField(10, default="SAR")
is_active    BooleanField(default=True)
sort_order   PositiveIntegerField(default=0)
created_at   DateTimeField(auto_now_add)
updated_at   DateTimeField(auto_now)
```

### `VerificationPricingRule` (verification)
```
badge_type   CharField(20, choices, unique)
fee          DecimalField(10,2)
currency     CharField(10, default="SAR")
is_active    BooleanField(default=True)
note         CharField(300, blank)
created_at   DateTimeField(auto_now_add)
updated_at   DateTimeField(auto_now)
```

### `PlatformConfig` — حقل جديد
```
extras_vat_percent  DecimalField(5,2, default=15.00)
```

---

## 7. ما لم يتم تنفيذه (حسب التوجيه)

- ❌ Client Extras Portal
- ❌ إعادة تصميم القوالب
- ❌ إزالة fallback القديم
- ❌ إعادة كتابة promo pricing logic
