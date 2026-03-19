# RBAC Rules Matrix — Phase 2
# مصفوفة صلاحيات الوصول الموحدة

**التاريخ:** 2026-03-18  
**المرحلة:** Phase 2 — Core RBAC Enhancement  
**الحالة:** مرجع تنفيذي معتمد

---

## 1. مستويات الصلاحيات (Access Levels)

| المستوى | الكود | القيمة | الوصف |
|---------|-------|--------|-------|
| Admin | `admin` | أعلى (99) | صلاحية كاملة، كل اللوحات، كل الإجراءات |
| Power User | `power` | عالي | مثل Admin في الوصول، لكن يمكن تقييده بالصلاحيات الدقيقة لاحقاً |
| User | `user` | قياسي | لوحات محددة فقط (حسب `allowed_dashboards`) + صلاحيات دقيقة (`granted_permissions`) |
| QA | `qa` | قراءة فقط | نفس نطاق User لكن **قراءة فقط** — لا يسمح بأي عملية كتابة |
| Client | `client` | بوابة العميل | `client_extras` فقط — لا يدخل أي لوحة داخلية |

---

## 2. اللوحات الـ 8 المطلوبة + اللوحات المساندة

### اللوحات الرئيسية (8)
| # | الكود | الاسم العربي | الوصف |
|---|-------|-------------|-------|
| 1 | `admin_control` | إدارة الصلاحيات والتقارير | إدارة المستخدمين، ملفات الصلاحيات، سجل التدقيق، التقارير |
| 2 | `support` | الدعم والمساعدة | تذاكر الدعم، التعيين، الحل |
| 3 | `content` | إدارة المحتوى | المحتوى، الوثائق، المعرض، اللمحات، المراجعات |
| 4 | `promo` | الإعلانات والترويج | الحملات، التسعير، البنرات، الاستفسارات |
| 5 | `verify` | التوثيق | طلبات التوثيق، المستندات، الشارات |
| 6 | `subs` | الاشتراكات والترقية | خطط الاشتراك، الاشتراكات، العمليات |
| 7 | `extras` | الخدمات الإضافية | الكتالوج، المشتريات، العملاء |
| 8 | `client_extras` | بوابة العميل | خدمات العميل، مشترياته، فواتيره |

### اللوحات المساندة (تبقى كما هي)
| الكود | الاسم | الوصف |
|-------|-------|-------|
| `moderation` | مركز الإشراف | حالات الإشراف والقرارات |
| `excellence` | إدارة التميز | شارات التميز |
| `analytics` | التحليلات | KPIs والتصدير |
| `billing` | الفوترة | الفواتير والمدفوعات |

---

## 3. مصفوفة الوصول الكاملة

### الجدول الرئيسي: Level × Dashboard → Access Type

| اللوحة | Admin | Power User | User | QA | Client |
|--------|-------|------------|------|----|--------|
| `admin_control` | ✅ R+W | ✅ R+W | ❌ (إلا إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `support` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `content` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `promo` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `verify` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `subs` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `extras` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `client_extras` | ❌ | ❌ | ❌ | ❌ | ✅ R+W |
| `moderation` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `excellence` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `analytics` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |
| `billing` | ✅ R+W | ✅ R+W | ✅ R+W (إذا مُنحت) | 👁️ R (إذا مُنحت) | ❌ |

**مفتاح:**
- ✅ R+W = قراءة وكتابة (تلقائي بدون حاجة لتعيين)
- ✅ R+W (إذا مُنحت) = قراءة وكتابة فقط إذا وُجدت اللوحة في `allowed_dashboards`
- 👁️ R = قراءة فقط (QA level = readonly globally)
- ❌ = ممنوع

---

## 4. الصلاحيات الدقيقة (Fine-Grained Permissions)

### ملاحظة مهمة حول `read_only_dashboards`

بعد فحص البنية الحالية، لا حاجة لإضافة M2M `read_only_dashboards` لأن:
1. **QA level** يطبق readonly على كل اللوحات بالفعل عبر `is_readonly()`.
2. **User level** يمكن التحكم في write عبر `granted_permissions` — إذا لم يملك permission الكتابة، فهو عملياً readonly.
3. إضافة M2M ثاني يخلق تعقيداً غير مبرر ولا يضيف قيمة.

**القرار:** بدلاً من `read_only_dashboards`، سنستخدم النمط الحالي:
- Level = QA → readonly لكل اللوحات
- Level = User → `allowed_dashboards` (دخول) + `granted_permissions` (إجراءات محددة)
- عدم امتلاك permission كتابة = readonly عملياً على ذلك الإجراء

### كتالوج الصلاحيات الدقيقة الكامل

#### لوحة admin_control
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `admin_control.manage_access` | إدارة ملفات صلاحيات المستخدمين | admin_control |
| `admin_control.view_audit` | عرض سجل التدقيق | admin_control |
| `admin_control.view_reports` | عرض تقارير المنصة | admin_control |

#### لوحة support
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `support.assign` | تعيين تذاكر الدعم ✅ (موجود) | support |
| `support.resolve` | حل تذاكر الدعم ✅ (موجود) | support |

#### لوحة content
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `content.hide_delete` | إخفاء/حذف محتوى ✅ (موجود) | content |
| `reviews.moderate` | إدارة مراجعات العملاء ✅ (موجود) | content |

#### لوحة promo
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `promo.quote_activate` | تسعير وتفعيل الحملات ✅ (موجود) | promo |

#### لوحة verify
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `verification.finalize` | إنهاء طلبات التوثيق ✅ (موجود) | verify |

#### لوحة subs
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `subscriptions.manage` | إدارة تشغيل الاشتراكات ✅ (موجود) | subs |

#### لوحة extras
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `extras.manage` | إدارة تشغيل الخدمات الإضافية ✅ (موجود) | extras |

#### لوحات مساندة
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `moderation.assign` | تعيين حالات الإشراف ✅ (موجود) | moderation |
| `moderation.resolve` | حل حالات الإشراف ✅ (موجود) | moderation |
| `analytics.export` | تصدير التحليلات ✅ (موجود) | analytics |

---

## 5. قاعدة الحسم النهائية (Access Resolution Algorithm)

```
can_access_dashboard(user, panel_code, write=False):

  1. هل المستخدم مصادق؟
     → لا → ❌ ممنوع

  2. هل المستخدم superuser؟
     → نعم → ✅ مسموح (R+W)

  3. هل يوجد access_profile فعال (غير منتهي، غير ملغي)؟
     → لا → ❌ ممنوع

  4. هل write=True و access_profile.level == QA؟
     → نعم → ❌ ممنوع (QA = read-only)

  5. هل access_profile.level ∈ {admin, power}؟
     → نعم:
       • هل panel_code == "client_extras"؟
         → نعم → ❌ ممنوع (admin/power لا يدخلون بوابة العميل)
         → لا  → ✅ مسموح

  6. هل access_profile.level == client؟
     → نعم:
       • هل panel_code == "client_extras"؟
         → نعم → ✅ مسموح
         → لا  → ❌ ممنوع

  7. هل access_profile.level ∈ {user, qa}؟
     → نعم:
       • هل panel_code في allowed_dashboards (M2M) و is_active؟
         → لا  → ❌ ممنوع
         → نعم → ✅ مسموح (R إذا QA، R+W إذا User)

  8. حالة افتراضية → ❌ ممنوع
```

```
has_action_permission(user, permission_code):

  1. هل المستخدم مصادق؟
     → لا → ❌

  2. هل المستخدم superuser؟
     → نعم → ✅

  3. هل يوجد access_profile فعال؟
     → لا → ❌

  4. هل access_profile.level ∈ {admin, power}؟
     → نعم → ✅ (كل الصلاحيات)

  5. هل access_profile.level == QA؟
     → نعم → ❌ (QA لا يملك صلاحيات write)

  6. هل access_profile.level == client؟
     → نعم → ❌ (client لا يملك صلاحيات داخلية)

  7. هل permission_code في granted_permissions (M2M) و is_active؟
     → نعم → ✅
     → لا  → ❌
```

---

## 6. التغييرات المطلوبة على النماذج

### 6.1 تغييرات `AccessPermission` — بدون تعديل

بعد التحليل الدقيق، **لا حاجة لإضافة `permission_type` field** إلى `AccessPermission`.  
السبب: التمييز بين read و write يتم بالفعل عبر:
- `access_profile.level == QA` → readonly عالمي
- `dashboard_allowed(user, code, write=True)` → فحص الكتابة
- Policy Engines → فحص الإجراء المحدد (كلها write بطبيعتها)

إضافة حقل permission_type ستكون over-engineering بدون حالة استخدام حقيقية.

### 6.2 تغييرات `UserAccessProfile` — بدون تعديل هيكلي

**لا حاجة لإضافة `read_only_dashboards` M2M**.  
البنية الحالية كافية:
- `allowed_dashboards` M2M → اللوحات المسموحة للـ User/QA
- `is_readonly()` → يعيد True لـ QA level
- `granted_permissions` M2M → الإجراءات المسموحة للـ User

### 6.3 التغيير الوحيد: توسيع `CLIENT_ALLOWED_DASHBOARDS`

```python
# من:
CLIENT_ALLOWED_DASHBOARDS = frozenset({"extras"})

# إلى:
CLIENT_ALLOWED_DASHBOARDS = frozenset({"client_extras"})
```

### 6.4 seed data مطلوب

#### لوحات جديدة:
| الكود | الاسم | ترتيب | ملاحظة |
|-------|-------|-------|--------|
| `admin_control` | إدارة الصلاحيات والتقارير | 1 | 🆕 جديد |
| `client_extras` | بوابة العميل | 70 | 🆕 جديد |

#### تحديث لوحات موجودة (ترتيب فقط):
| الكود | الاسم | ترتيب جديد |
|-------|-------|------------|
| `support` | الدعم والمساعدة | 10 |
| `content` | إدارة المحتوى | 20 |
| `promo` | الإعلانات والترويج | 30 |
| `verify` | التوثيق | 40 |
| `subs` | الاشتراكات والترقية | 50 |
| `extras` | الخدمات الإضافية | 60 |

#### صلاحيات جديدة:
| الكود | الوصف | اللوحة |
|-------|-------|--------|
| `admin_control.manage_access` | إدارة ملفات صلاحيات المستخدمين | admin_control |
| `admin_control.view_audit` | عرض سجل التدقيق | admin_control |
| `admin_control.view_reports` | عرض تقارير المنصة | admin_control |

---

## 7. ملخص الملفات المتأثرة

| الملف | نوع التغيير | التفاصيل |
|-------|-----------|---------|
| `backoffice/models.py` | Refactor | تحديث `CLIENT_ALLOWED_DASHBOARDS` |
| `backoffice/migrations/0005_*.py` | 🆕 | seed dashboards + permissions جديدة |
| `dashboard/access.py` | Refactor | تحديث `DASHBOARD_ROUTE_CANDIDATES` + إضافة `can_access_dashboard` + `has_action_permission` |
| `dashboard/views.py` | Refactor | تحديث `_dashboard_tile_meta` + `_dashboard_allowed` → استخدام الطبقة الموحدة |
| `backoffice/policies.py` | بدون تغيير | تعمل بالفعل مع النظام الحالي |
| `backoffice/admin.py` | بدون تغيير | — |
| `backoffice/serializers.py` | Refactor طفيف | تحديث لدعم `client_extras` |

---

## 8. المخاطر

| # | المخاطرة | الاحتمال | الحل |
|---|---------|---------|------|
| 1 | تأثير تغيير `CLIENT_ALLOWED_DASHBOARDS` على الـ extras_portal | منخفض | الـ extras_portal يستخدم مصادقة مستقلة — لا يعتمد على RBAC |
| 2 | الـ views الحالية التي تفحص `_dashboard_allowed(user, "access")` ستحتاج تحديث | متوسط | نضيف alias: `access` → `admin_control` |
| 3 | seed data قد يتعارض مع records موجودة | منخفض | نستخدم `update_or_create` |
