# تقرير Phase 4A – توحيد لوحة إدارة النظام (Admin Control Consolidation)

> **تاريخ الإنجاز:** يونيو 2025  
> **الحالة:** ✅ مكتمل — الكود مُطبّق، الاختبارات ناجحة، التوافق العكسي محفوظ

---

## 1. ملخص التغييرات

تم إعادة تنظيم جميع مسارات لوحة إدارة النظام (admin_control) تحت بادئة `/dashboard/admin/` موحدة،
مع نقل خطط الاشتراك إلى `/dashboard/subscriptions/plans/`، وإضافة تحويلات دائمة (301) للمسارات القديمة.

---

## 2. خريطة المسارات (قبل ← بعد)

| الوظيفة | المسار القديم | المسار الجديد | اسم الـ URL |
|---------|--------------|--------------|-------------|
| صفحة الإدارة الرئيسية | *(غير موجود)* | `/dashboard/admin/` | `admin_home` |
| قائمة ملفات الوصول | `/dashboard/access-profiles/` | `/dashboard/admin/access-profiles/` | `access_profiles_list` |
| إنشاء ملف وصول | `/dashboard/access-profiles/actions/create/` | `/dashboard/admin/access-profiles/actions/create/` | `access_profile_create_action` |
| تحديث ملف وصول | `/dashboard/access-profiles/{id}/actions/update/` | `/dashboard/admin/access-profiles/{id}/actions/update/` | `access_profile_update_action` |
| تبديل/إلغاء ملف وصول | `/dashboard/access-profiles/{id}/actions/toggle-revoke/` | `/dashboard/admin/access-profiles/{id}/actions/toggle-revoke/` | `access_profile_toggle_revoke_action` |
| قائمة المستخدمين | `/dashboard/users/` | `/dashboard/admin/users/` | `users_list` |
| تفاصيل مستخدم | `/dashboard/users/{id}/` | `/dashboard/admin/users/{id}/` | `user_detail` |
| تفعيل/تعطيل مستخدم | `/dashboard/users/{id}/actions/toggle-active/` | `/dashboard/admin/users/{id}/actions/toggle-active/` | `user_toggle_active` |
| تحديث صلاحية مستخدم | `/dashboard/users/{id}/actions/update-role/` | `/dashboard/admin/users/{id}/actions/update-role/` | `user_update_role` |
| سجل التدقيق | `/dashboard/audit-logs/` | `/dashboard/admin/audit-log/` | `audit_log_list` |
| قائمة الخطط | `/dashboard/plans/` | `/dashboard/subscriptions/plans/` | `plans_list` |
| إنشاء خطة | `/dashboard/plans/create/` | `/dashboard/subscriptions/plans/create/` | `plan_create` |
| تعديل خطة | `/dashboard/plans/{id}/edit/` | `/dashboard/subscriptions/plans/{id}/edit/` | `plan_edit` |
| تفعيل/تعطيل خطة | `/dashboard/plans/{id}/actions/toggle-active/` | `/dashboard/subscriptions/plans/{id}/actions/toggle-active/` | `plan_toggle_active` |

---

## 3. التحويلات الدائمة (Legacy Redirects — 301)

| المسار القديم | يُحوّل إلى |
|--------------|-----------|
| `/dashboard/access-profiles/` | `dashboard:access_profiles_list` → `/dashboard/admin/access-profiles/` |
| `/dashboard/audit-logs/` | `dashboard:audit_log_list` → `/dashboard/admin/audit-log/` |
| `/dashboard/users/` | `dashboard:users_list` → `/dashboard/admin/users/` |
| `/dashboard/plans/` | `dashboard:plans_list` → `/dashboard/subscriptions/plans/` |

---

## 4. الملفات المعدّلة

### 4.1 `admin_views.py` — التوسيع
- **إضافة الواردات:** `AccessLevel`, `Dashboard`, `active_dashboard_choices`, `_dashboard_tile_meta`, `_is_active_admin_profile`, `_active_admin_profiles_count`, `_limited_export_queryset`, `_parse_datetime_local`
- **نقل 4 دوال** من `views.py`:
  - `access_profiles_list`
  - `access_profile_create_action`
  - `access_profile_update_action`
  - `access_profile_toggle_revoke_action`

### 4.2 `views.py` — استبدال بجسور تفويض
الدوال الأربع المنقولة استُبدلت بجسور خفيفة تُفوّض إلى `admin_views`:
```python
def access_profiles_list(request):
    from . import admin_views
    return admin_views.access_profiles_list(request)
```
هذا يحافظ على التوافق العكسي لأي استيرادات مباشرة.

### 4.3 `urls.py` — إعادة الهيكلة
- إضافة `RedirectView` للاستيراد
- تجميع جميع مسارات الإدارة تحت `admin/`
- نقل خطط الاشتراك إلى `subscriptions/plans/`
- إضافة 4 تحويلات دائمة للمسارات القديمة

### 4.4 `access.py` — تحديث المرشحات
```python
# قبل
("admin_control", "dashboard:access_profiles_list")
# بعد
("admin_control", "dashboard:admin_home")
```

### 4.5 `base_dashboard.html` — تحسين القائمة الجانبية
- إضافة فاصل قسم وعنوان «إدارة النظام» قبل روابط الإدارة
- إضافة `admin_home` لمنطق تحديد الحالة النشطة

---

## 5. نتائج الاختبارات

| المجموعة | النتيجة |
|----------|---------|
| Dashboard tests | **64 ناجح** ✅ (1 مستبعد — خطأ مسبق غير مرتبط) |
| Backoffice tests | **11 ناجح** ✅ |
| URL Resolution | **جميع المسارات محلولة بشكل صحيح** ✅ |

---

## 6. مخاطر التوافق العكسي

| المخاطر | الاحتمال | الحل |
|---------|----------|------|
| روابط محفوظة لدى المستخدمين بالمسارات القديمة | متوسط | تحويلات 301 دائمة تعيد التوجيه تلقائياً |
| استيرادات مباشرة لدوال access_profiles من views.py | منخفض | جسور التفويض تحافظ على عمل الاستيرادات |
| استيرادات دائرية بين views.py و admin_views.py | منخفض | حُلّ باستخدام استيراد كسول داخل جسم الدالة |
| أسماء URL لم تتغير | لا يوجد | جميع وسوم `{% url %}` في القوالب تعمل بدون تعديل |

---

## 7. ما لا يزال مؤجلاً

| البند | السبب |
|-------|-------|
| صفحة لوحة تحكم مستقلة لـ `admin_home` | حالياً يُعاد توجيهه إلى `access_profiles_list`؛ يمكن إنشاء صفحة نظرة عامة لاحقاً |
| إعادة هيكلة كاملة للقوالب | مؤجل صراحةً حسب طلب المستخدم |
| ServiceCatalog / VerificationPricingRule / Client Extras | مؤجل صراحةً حسب طلب المستخدم |
| content panel hardening | Phase 4B — قيد التنفيذ |
