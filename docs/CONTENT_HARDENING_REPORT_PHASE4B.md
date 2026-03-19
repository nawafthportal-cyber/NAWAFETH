# تقرير Phase 4B – تعزيز أمان لوحة المحتوى (Content Panel Hardening)

> **تاريخ الإنجاز:** يونيو 2025  
> **الحالة:** ✅ مكتمل — Policy gates مُطبّقة، اختبارات ناجحة، migration مُنفّذ

---

## 1. ملخص التدقيق

| المقياس | القيمة |
|---------|--------|
| إجمالي write views في content panel | **17** |
| محمية مسبقاً بـ Policy Engine | **4** |
| **تم تعزيزها في هذه المرحلة** | **7** |
| تبقى بـ `write=True` فقط (كافية) | **6** |
| سياسات جديدة | **1** (`ContentManagePolicy`) |
| صلاحيات جديدة | **1** (`content.manage`) |
| اختبارات جديدة | **5** |

---

## 2. التصنيف: Policy Engine مقابل write=True

### ✅ محمية مسبقاً (لا تغيير)

| الدالة | السياسة | الملف |
|--------|---------|-------|
| `portfolio_item_delete_action` | `ContentHideDeletePolicy` | content_views.py |
| `spotlight_item_delete_action` | `ContentHideDeletePolicy` | content_views.py |
| `reviews_dashboard_moderate_action` | `ReviewModerationPolicy` | reviews_views.py |

### 🔒 تم تعزيزها بـ Policy Engine (7 دوال)

| الدالة | السياسة المستخدمة | المبرر |
|--------|-------------------|--------|
| `category_toggle_active` | `ContentHideDeletePolicy` | إخفاء تصنيف كامل يؤثر على كل خدماته |
| `subcategory_toggle_active` | `ContentHideDeletePolicy` | إخفاء تصنيف فرعي يؤثر على الخدمات المرتبطة |
| `provider_service_toggle_active` | `ContentHideDeletePolicy` | تعطيل خدمة يؤثر على ظهورها في المنصة |
| `content_block_update_action` | `ContentManagePolicy` (**جديدة**) | تعديل محتوى عالمي يراه جميع المستخدمين |
| `content_doc_upload_action` | `ContentManagePolicy` | مستندات قانونية — مخاطر امتثال عالية |
| `content_links_update_action` | `ContentManagePolicy` | تعديل روابط المنصة — خطر تصيّد |
| `reviews_dashboard_respond_action` | `ReviewModerationPolicy` | توحيد مع `moderate_action` — ردود إدارية عامة |

### ⚡ تبقى بـ write=True فقط (كافية)

| الدالة | المبرر |
|--------|--------|
| `category_create` | عملية إنشاء CRUD عادية، غير مدمرة |
| `category_edit` | عملية تعديل CRUD عادية |
| `subcategory_create` | عملية إنشاء CRUD عادية |
| `subcategory_edit` | عملية تعديل CRUD عادية |
| `request_accept/start/complete/cancel/send` | `execute_action()` لديه فحوصات أدوار مدمجة |

---

## 3. الملفات المعدّلة

### 3.1 `backoffice/policies.py`
- إضافة `CONTENT_MANAGE = "content.manage"` إلى `PermissionCode`
- إضافة `ContentManagePolicy` (dashboard_code="content", permission_code="content.manage")

### 3.2 `dashboard/views.py` — 3 toggle views
- `provider_service_toggle_active` → إضافة `ContentHideDeletePolicy.evaluate_and_log()`
- `category_toggle_active` → إضافة `ContentHideDeletePolicy.evaluate_and_log()`
- `subcategory_toggle_active` → إضافة `ContentHideDeletePolicy.evaluate_and_log()`

### 3.3 `dashboard/content_views.py` — 3 content mgmt views
- إضافة `ContentManagePolicy` إلى الاستيرادات
- `content_block_update_action` → إضافة `ContentManagePolicy.evaluate_and_log()`
- `content_doc_upload_action` → إضافة `ContentManagePolicy.evaluate_and_log()`
- `content_links_update_action` → إضافة `ContentManagePolicy.evaluate_and_log()`

### 3.4 `dashboard/reviews_views.py` — 1 respond view
- `reviews_dashboard_respond_action` → إضافة `ReviewModerationPolicy.evaluate_and_log()`

### 3.5 Migration جديد
- `backoffice/migrations/0006_seed_content_manage_permission.py`
- يزرع صلاحية `content.manage` (إدارة محتوى المنصة)

---

## 4. نتائج الاختبارات

| المجموعة | النتيجة |
|----------|---------|
| Dashboard tests | **69 ناجح** ✅ (64 سابقة + 5 جديدة) |
| Backoffice tests | **11 ناجح** ✅ |
| **الإجمالي** | **80 ناجح** |

### الاختبارات الجديدة (5)

| الاختبار | ما يتحقق منه |
|----------|-------------|
| `test_content_block_update_requires_content_manage_policy` | User بدون `content.manage` → ممنوع؛ مع الصلاحية → مسموح |
| `test_content_links_update_requires_content_manage_policy` | نفس النمط لتعديل الروابط |
| `test_category_toggle_requires_content_hide_delete_policy` | User بدون `content.hide_delete` → لا يتم التبديل؛ مع الصلاحية → يتم التبديل |
| `test_review_respond_requires_reviews_moderate_policy` | User بدون `reviews.moderate` → لا يُحفظ الرد؛ مع الصلاحية → يُحفظ |
| `test_admin_and_power_bypass_content_policy` | Admin يمر بدون صلاحية صريحة |

> جميع اختبارات Phase 4B تستخدم `@override_settings(FEATURE_RBAC_ENFORCE=True)` لاختبار السلوك الفعلي عند تفعيل الإنفاذ.

---

## 5. سلوك Feature Flags

| العلم | القيمة الافتراضية | التأثير |
|-------|-------------------|--------|
| `FEATURE_RBAC_ENFORCE` | `False` | Policy gates تسجّل فقط (audit-only) — لا تمنع |
| `RBAC_AUDIT_ONLY` | `True` | يُسجّل قرارات السماح/المنع في سجل التدقيق |

عند تفعيل `FEATURE_RBAC_ENFORCE=True`:
- **Admin/Power** → يمر بدون صلاحيات صريحة (dashboard_allowed كافية)
- **User** → يحتاج الصلاحية المحددة (`content.manage`, `content.hide_delete`, `reviews.moderate`)
- **QA** → ممنوع (readonly)
- **Client** → ممنوع (ليس لديه content dashboard)

---

## 6. خريطة الصلاحيات المحدّثة لـ content panel

| كود الصلاحية | الاسم | الدوال المحمية |
|-------------|-------|---------------|
| `content.hide_delete` | إخفاء وحذف المحتوى | portfolio_delete, spotlight_delete, category_toggle, subcategory_toggle, service_toggle |
| `content.manage` | إدارة محتوى المنصة | content_block_update, content_doc_upload, content_links_update |
| `reviews.moderate` | إدارة المراجعات | reviews_moderate, reviews_respond |

---

## 7. ما لا يزال مؤجلاً

| البند | السبب |
|-------|-------|
| Policy على `execute_action()` لدورة الطلبات | حماية مدمجة كافية حالياً |
| سير عمل موافقة للمستندات القانونية | يتطلب بنية تحتية إضافية |
| التحقق من صحة URLs في content_links | يتطلب قائمة بيضاء URLs |
| ServiceCatalog / VerificationPricingRule | مؤجل صراحةً حسب طلب المستخدم |
