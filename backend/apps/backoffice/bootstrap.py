from __future__ import annotations

from django.db import transaction

from .models import AccessPermission, Dashboard


DASHBOARD_ROWS = [
    {"code": "admin_control", "name_ar": "إدارة الصلاحيات والتقارير", "name_en": "Access Management & Reports", "sort_order": 1},
    {"code": "support", "name_ar": "الدعم والمساعدة", "name_en": "Support & Help", "sort_order": 10},
    {"code": "content", "name_ar": "إدارة المحتوى", "name_en": "Content Management", "sort_order": 20},
    {"code": "moderation", "name_ar": "الإشراف", "name_en": "Moderation", "sort_order": 25},
    {"code": "reviews", "name_ar": "المراجعات", "name_en": "Reviews", "sort_order": 27},
    {"code": "promo", "name_ar": "الترويج", "name_en": "Promotions", "sort_order": 30},
    {"code": "verify", "name_ar": "التوثيق", "name_en": "Verification", "sort_order": 40},
    {"code": "subs", "name_ar": "الاشتراكات", "name_en": "Subscriptions", "sort_order": 50},
    {"code": "extras", "name_ar": "الخدمات الإضافية", "name_en": "Additional Services", "sort_order": 60},
    {"code": "analytics", "name_ar": "التحليلات", "name_en": "Analytics", "sort_order": 70},
    {"code": "client_extras", "name_ar": "بوابة العميل", "name_en": "Client Portal", "sort_order": 90},
]

PERMISSION_ROWS = [
    {
        "code": "admin_control.manage_access",
        "name_ar": "إدارة ملفات صلاحيات المستخدمين",
        "name_en": "Manage User Access Profiles",
        "dashboard_code": "admin_control",
        "description": "يتيح إدارة وتعديل ملفات صلاحيات المستخدمين.",
        "description_en": "Allows managing and updating user access profiles.",
        "sort_order": 1,
    },
    {
        "code": "admin_control.view_audit",
        "name_ar": "عرض سجل التدقيق",
        "name_en": "View Audit Log",
        "dashboard_code": "admin_control",
        "description": "يتيح تصفح وعرض سجل التدقيق.",
        "description_en": "Allows browsing and viewing the audit log.",
        "sort_order": 2,
    },
    {
        "code": "admin_control.view_reports",
        "name_ar": "عرض تقارير المنصة",
        "name_en": "View Platform Reports",
        "dashboard_code": "admin_control",
        "description": "يتيح الاطلاع على تقارير المنصة الإحصائية.",
        "description_en": "Allows viewing platform analytics reports.",
        "sort_order": 3,
    },
    {
        "code": "moderation.assign",
        "name_ar": "إسناد حالات الإشراف",
        "name_en": "Assign Moderation Cases",
        "dashboard_code": "moderation",
        "description": "يتيح إسناد حالات مركز الإشراف.",
        "description_en": "Allows assigning moderation center cases.",
        "sort_order": 10,
    },
    {
        "code": "moderation.resolve",
        "name_ar": "معالجة حالات الإشراف",
        "name_en": "Resolve Moderation Cases",
        "dashboard_code": "moderation",
        "description": "يتيح تغيير حالة القضية وتسجيل القرار النهائي.",
        "description_en": "Allows changing case status and recording the final decision.",
        "sort_order": 20,
    },
    {
        "code": "content.manage",
        "name_ar": "إدارة محتوى المنصة",
        "name_en": "Manage Platform Content",
        "dashboard_code": "content",
        "description": "يتيح تعديل البلوكات والمستندات القانونية وروابط المنصة.",
        "description_en": "Allows editing content blocks, legal documents, and platform links.",
        "sort_order": 20,
    },
    {
        "code": "content.hide_delete",
        "name_ar": "إخفاء/حذف المحتوى",
        "name_en": "Hide/Delete Content",
        "dashboard_code": "content",
        "description": "إجراء حساس على المحتوى العام.",
        "description_en": "Sensitive action on public content.",
        "sort_order": 30,
    },
    {
        "code": "reviews.moderate",
        "name_ar": "إدارة مراجعات العملاء",
        "name_en": "Manage Client Reviews",
        "dashboard_code": "content",
        "description": "يتيح اعتماد/إخفاء/رفض المراجعات داخل لوحة المحتوى.",
        "description_en": "Allows approving, hiding, or rejecting reviews in the content dashboard.",
        "sort_order": 35,
    },
    {
        "code": "support.assign",
        "name_ar": "إسناد تذاكر الدعم",
        "name_en": "Assign Support Tickets",
        "dashboard_code": "support",
        "description": "يتيح إسناد تذاكر الدعم للمشغلين.",
        "description_en": "Allows assigning support tickets to operators.",
        "sort_order": 40,
    },
    {
        "code": "support.resolve",
        "name_ar": "إغلاق/معالجة تذاكر الدعم",
        "name_en": "Resolve Support Tickets",
        "dashboard_code": "support",
        "description": "يتيح تحديث حالة التذكرة إلى مغلقة أو معالَجة.",
        "description_en": "Allows updating ticket status to resolved or closed.",
        "sort_order": 50,
    },
    {
        "code": "promo.quote_activate",
        "name_ar": "تسعير/تفعيل الترويج",
        "name_en": "Price/Activate Promotions",
        "dashboard_code": "promo",
        "description": "يتيح تسعير الحملات أو تفعيلها.",
        "description_en": "Allows pricing campaigns or activating them.",
        "sort_order": 60,
    },
    {
        "code": "verification.finalize",
        "name_ar": "اعتماد التوثيق",
        "name_en": "Finalize Verification",
        "dashboard_code": "verify",
        "description": "يتيح إنهاء طلبات التوثيق.",
        "description_en": "Allows finalizing verification requests.",
        "sort_order": 70,
    },
    {
        "code": "analytics.export",
        "name_ar": "تصدير التقارير",
        "name_en": "Export Reports",
        "dashboard_code": "analytics",
        "description": "يتيح تصدير بيانات وتقارير التحليلات.",
        "description_en": "Allows exporting analytics data and reports.",
        "sort_order": 80,
    },
    {
        "code": "subscriptions.manage",
        "name_ar": "إدارة تشغيل الاشتراكات",
        "name_en": "Manage Subscription Operations",
        "dashboard_code": "subs",
        "description": "يتيح إسناد ومعالجة وتفعيل طلبات وحسابات الاشتراكات داخل التشغيل الداخلي.",
        "description_en": "Allows assigning, processing, and activating subscription requests and accounts in backoffice operations.",
        "sort_order": 85,
    },
    {
        "code": "extras.manage",
        "name_ar": "إدارة تشغيل الخدمات الإضافية",
        "name_en": "Manage Additional Services Operations",
        "dashboard_code": "extras",
        "description": "يتيح إسناد ومعالجة وتفعيل الخدمات الإضافية داخل التشغيل الداخلي.",
        "description_en": "Allows assigning, processing, and activating additional services in backoffice operations.",
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
                    "name_en": row["name_en"],
                    "sort_order": row["sort_order"],
                    "is_active": True,
                },
            )
        for row in PERMISSION_ROWS:
            AccessPermission.objects.update_or_create(
                code=row["code"],
                defaults={
                    "name_ar": row["name_ar"],
                    "name_en": row["name_en"],
                    "dashboard_code": row["dashboard_code"],
                    "description": row["description"],
                    "description_en": row["description_en"],
                    "sort_order": row["sort_order"],
                    "is_active": True,
                },
            )
    return True
