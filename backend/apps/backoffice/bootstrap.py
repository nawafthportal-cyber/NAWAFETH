from __future__ import annotations

from django.db import transaction

from .models import AccessPermission, Dashboard


DASHBOARD_ROWS = [
    {"code": "admin_control", "name_ar": "إدارة الصلاحيات والتقارير", "sort_order": 1},
    {"code": "support", "name_ar": "الدعم والمساعدة", "sort_order": 10},
    {"code": "content", "name_ar": "إدارة المحتوى", "sort_order": 20},
    {"code": "moderation", "name_ar": "الإشراف", "sort_order": 25},
    {"code": "reviews", "name_ar": "المراجعات", "sort_order": 27},
    {"code": "promo", "name_ar": "الترويج", "sort_order": 30},
    {"code": "verify", "name_ar": "التوثيق", "sort_order": 40},
    {"code": "subs", "name_ar": "الاشتراكات", "sort_order": 50},
    {"code": "extras", "name_ar": "الخدمات الإضافية", "sort_order": 60},
    {"code": "analytics", "name_ar": "التحليلات", "sort_order": 70},
    {"code": "client_extras", "name_ar": "بوابة العميل", "sort_order": 90},
]

PERMISSION_ROWS = [
    {
        "code": "admin_control.manage_access",
        "name_ar": "إدارة ملفات صلاحيات المستخدمين",
        "dashboard_code": "admin_control",
        "description": "يتيح إدارة وتعديل ملفات صلاحيات المستخدمين.",
        "sort_order": 1,
    },
    {
        "code": "admin_control.view_audit",
        "name_ar": "عرض سجل التدقيق",
        "dashboard_code": "admin_control",
        "description": "يتيح تصفح وعرض سجل التدقيق.",
        "sort_order": 2,
    },
    {
        "code": "admin_control.view_reports",
        "name_ar": "عرض تقارير المنصة",
        "dashboard_code": "admin_control",
        "description": "يتيح الاطلاع على تقارير المنصة الإحصائية.",
        "sort_order": 3,
    },
    {
        "code": "moderation.assign",
        "name_ar": "إسناد حالات الإشراف",
        "dashboard_code": "moderation",
        "description": "يتيح إسناد حالات مركز الإشراف.",
        "sort_order": 10,
    },
    {
        "code": "moderation.resolve",
        "name_ar": "معالجة حالات الإشراف",
        "dashboard_code": "moderation",
        "description": "يتيح تغيير حالة القضية وتسجيل القرار النهائي.",
        "sort_order": 20,
    },
    {
        "code": "content.manage",
        "name_ar": "إدارة محتوى المنصة",
        "dashboard_code": "content",
        "description": "يتيح تعديل البلوكات والمستندات القانونية وروابط المنصة.",
        "sort_order": 20,
    },
    {
        "code": "content.hide_delete",
        "name_ar": "إخفاء/حذف المحتوى",
        "dashboard_code": "content",
        "description": "إجراء حساس على المحتوى العام.",
        "sort_order": 30,
    },
    {
        "code": "reviews.moderate",
        "name_ar": "إدارة مراجعات العملاء",
        "dashboard_code": "content",
        "description": "يتيح اعتماد/إخفاء/رفض المراجعات داخل لوحة المحتوى.",
        "sort_order": 35,
    },
    {
        "code": "support.assign",
        "name_ar": "إسناد تذاكر الدعم",
        "dashboard_code": "support",
        "description": "يتيح إسناد تذاكر الدعم للمشغلين.",
        "sort_order": 40,
    },
    {
        "code": "support.resolve",
        "name_ar": "إغلاق/معالجة تذاكر الدعم",
        "dashboard_code": "support",
        "description": "يتيح تحديث حالة التذكرة إلى مغلقة أو معالَجة.",
        "sort_order": 50,
    },
    {
        "code": "promo.quote_activate",
        "name_ar": "تسعير/تفعيل الترويج",
        "dashboard_code": "promo",
        "description": "يتيح تسعير الحملات أو تفعيلها.",
        "sort_order": 60,
    },
    {
        "code": "verification.finalize",
        "name_ar": "اعتماد التوثيق",
        "dashboard_code": "verify",
        "description": "يتيح إنهاء طلبات التوثيق.",
        "sort_order": 70,
    },
    {
        "code": "analytics.export",
        "name_ar": "تصدير التقارير",
        "dashboard_code": "analytics",
        "description": "يتيح تصدير بيانات وتقارير التحليلات.",
        "sort_order": 80,
    },
    {
        "code": "subscriptions.manage",
        "name_ar": "إدارة تشغيل الاشتراكات",
        "dashboard_code": "subs",
        "description": "يتيح إسناد ومعالجة وتفعيل طلبات وحسابات الاشتراكات داخل التشغيل الداخلي.",
        "sort_order": 85,
    },
    {
        "code": "extras.manage",
        "name_ar": "إدارة تشغيل الخدمات الإضافية",
        "dashboard_code": "extras",
        "description": "يتيح إسناد ومعالجة وتفعيل الخدمات الإضافية داخل التشغيل الداخلي.",
        "sort_order": 86,
    },
]

_DASHBOARD_CODES = frozenset(row["code"] for row in DASHBOARD_ROWS)
_PERMISSION_CODES = frozenset(row["code"] for row in PERMISSION_ROWS)


def ensure_backoffice_access_catalog(*, force_update: bool = False) -> bool:
    if not force_update:
        dashboard_codes = set(
            Dashboard.objects.filter(code__in=_DASHBOARD_CODES).values_list("code", flat=True)
        )
        permission_codes = set(
            AccessPermission.objects.filter(code__in=_PERMISSION_CODES).values_list("code", flat=True)
        )
        if dashboard_codes == _DASHBOARD_CODES and permission_codes == _PERMISSION_CODES:
            return False

    with transaction.atomic():
        for row in DASHBOARD_ROWS:
            Dashboard.objects.update_or_create(
                code=row["code"],
                defaults={
                    "name_ar": row["name_ar"],
                    "sort_order": row["sort_order"],
                    "is_active": True,
                },
            )
        for row in PERMISSION_ROWS:
            AccessPermission.objects.update_or_create(
                code=row["code"],
                defaults={
                    "name_ar": row["name_ar"],
                    "dashboard_code": row["dashboard_code"],
                    "description": row["description"],
                    "sort_order": row["sort_order"],
                    "is_active": True,
                },
            )
    return True
