# Phase 2 — تثبيت الأساس المشترك للنظام

> **تاريخ التنفيذ**: Phase 2  
> **الحالة**: ✅ مكتمل — 15 اختبار ناجح

---

## 1. PlatformConfig — إعدادات المنصة المركزية

### الملفات
| الملف | التغيير |
|---|---|
| `apps/core/models.py` | إنشاء `PlatformConfig` (Singleton) + `ReminderLog` |
| `apps/core/admin.py` | تسجيل Admin مع fieldsets مصنّفة |
| `apps/core/migrations/0001_initial.py` | Migration جديدة |

### الحقول القابلة للتعديل من Admin

| المجموعة | الحقل | القيمة الافتراضية |
|---|---|---|
| **الضريبة** | `vat_percent` | 15.00% |
| **الاشتراكات** | `subscription_grace_days` | 7 أيام |
| | `subscription_yearly_duration_days` | 365 يوم |
| | `subscription_monthly_duration_days` | 30 يوم |
| | `subscription_reminder_days_before` | "7,3,1" |
| **التوثيق** | `verification_validity_days` | 365 يوم |
| | `verification_currency` | SAR |
| | `verification_reminder_days_before` | 30 يوم |
| **الترويج** | `promo_vat_percent` | 15.00% |
| | `promo_min_campaign_hours` | 24 ساعة |
| **الإضافية** | `extras_default_duration_days` | 30 يوم |
| **التميز** | `excellence_review_cycle_days` | 90 يوم |
| | `excellence_min_rating` | 4.50 |
| | `excellence_min_orders` | 5 |
| | `excellence_top_n_club` | 100 |
| **الحدود** | `upload_max_file_size_mb` | 100 MB |
| | `export_pdf_max_rows` | 200 |
| | `export_xlsx_max_rows` | 2000 |

### آلية العمل
- **Singleton**: `pk=1` دائمًا — لا يمكن حذفه ولا إنشاء أكثر من صف.
- **Cache**: يُخزّن مؤقتًا لـ 5 دقائق، ويُمسح عند كل `save()`.
- **الاستخدام**: `PlatformConfig.load()` في أي مكان بالكود.

---

## 2. Client RBAC Scope — تقييد مستوى العميل

### الملفات المعدّلة
| الملف | التغيير |
|---|---|
| `apps/backoffice/models.py` | إضافة `CLIENT_ALLOWED_DASHBOARDS` + تقييد `is_allowed()` |
| `apps/dashboard/access.py` | تقييد `dashboard_allowed()` + `access_profile_grants_any_dashboard()` |

### السلوك الجديد
| المستوى | الوصول |
|---|---|
| **Admin / Power** | جميع اللوحات بدون قيد |
| **User** | اللوحات المعيّنة في M2M فقط |
| **QA** | مثل User لكن قراءة فقط (read-only) |
| **Client** | `extras` فقط — بغض النظر عن M2M |

> **ملاحظة**: القائمة `CLIENT_ALLOWED_DASHBOARDS = {"extras"}` ثابتة في الكود. يمكن التوسيع لاحقًا إذا لزم الأمر.

---

## 3. ReminderLog — منع تكرار التنبيهات

| الحقل | الوصف |
|---|---|
| `user` | المستخدم |
| `reminder_type` | `sub_expiry` / `ver_expiry` / `promo_complete` |
| `reference_id` | PK للكائن المرتبط |
| `days_before` | عدد الأيام قبل الانتهاء |
| `sent_at` | وقت الإرسال |

- **unique_together**: `(user, reminder_type, reference_id, days_before)` — يمنع التكرار.
- **Admin**: للقراءة فقط — لا يمكن إضافة أو تعديل يدويًا.

---

## 4. Celery Tasks الجديدة

| اسم المهمة | الجدولة | الوظيفة |
|---|---|---|
| `core.send_subscription_renewal_reminders` | كل 6 ساعات | تنبيه المستخدمين قبل انتهاء الاشتراك |
| `core.send_verification_expiry_reminders` | كل 12 ساعة | تنبيه قبل انتهاء التوثيق |
| `core.auto_complete_expired_promos` | كل ساعة | إتمام الحملات الترويجية المنتهية |

### الملفات
| الملف | التغيير |
|---|---|
| `apps/core/tasks.py` | 3 مهام Celery جديدة |
| `config/settings/base.py` | إضافة 3 إدخالات في `CELERY_BEAT_SCHEDULE` |

---

## 5. الاختبارات

| اسم الاختبار | النتيجة |
|---|---|
| `PlatformConfigTests` (6 اختبارات) | ✅ |
| `ClientRBACTests` (5 اختبارات) | ✅ |
| `SubscriptionReminderTaskTests` (2 اختبار) | ✅ |
| `VerificationReminderTaskTests` (1 اختبار) | ✅ |
| `PromoAutoCompleteTaskTests` (1 اختبار) | ✅ |
| **المجموع** | **15 / 15 ✅** |

---

## 6. ملاحظات للمراحل التالية

1. **ربط PlatformConfig بالكود الحالي**: القيم الحالية (`DEFAULT_VAT_PERCENT`, `SUBS_GRACE_DAYS`, إلخ) في `settings/base.py` لا تزال موجودة. يُفضل تدريجيًا استبدال القراءة من `settings.X` بـ `PlatformConfig.load().field` في المراحل القادمة.
2. **OTP Bypass**: تم تأجيله كما طلب المستخدم.
3. **Client portal views**: الـ RBAC يقيّد الدخول. واجهات العميل في `extras` تحتاج بناء في مرحلة لاحقة.
