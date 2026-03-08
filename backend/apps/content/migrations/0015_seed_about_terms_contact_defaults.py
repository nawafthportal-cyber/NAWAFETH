from django.db import migrations


def seed_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")

    defaults = {
        "about_hero_title": {"title_ar": "منصة نوافذ", "body_ar": "", "is_active": True},
        "about_hero_subtitle": {
            "title_ar": "حلول رقمية واضحة تربط العملاء بمزودي الخدمات بسرعة وموثوقية.",
            "body_ar": "",
            "is_active": True,
        },
        "about_section_about": {
            "title_ar": "من نحن",
            "body_ar": "نوافذ منصة سعودية تساعد الأفراد والمنشآت على الوصول إلى مزودي الخدمات وإدارة التواصل معهم عبر تجربة موحدة وواضحة.",
            "is_active": True,
        },
        "about_section_vision": {
            "title_ar": "رؤيتنا",
            "body_ar": "أن تكون نوافذ نقطة الوصول الأولى للخدمات في المملكة عبر تجربة عالية الموثوقية وسهلة الاستخدام.",
            "is_active": True,
        },
        "about_section_goals": {
            "title_ar": "أهدافنا",
            "body_ar": "تقليل وقت الوصول إلى الخدمة، وتحسين جودة التواصل، ورفع شفافية التعامل بين جميع أطراف المنصة.",
            "is_active": True,
        },
        "about_section_values": {
            "title_ar": "قيمنا",
            "body_ar": "الوضوح، السرعة، الجودة، والالتزام بتجربة استخدام عملية ومفهومة.",
            "is_active": True,
        },
        "about_section_app": {
            "title_ar": "عن التطبيق",
            "body_ar": "يمكنك عبر تطبيق نوافذ استعراض الخدمات، إدارة الطلبات، والتواصل مع مزودي الخدمة من مكان واحد.",
            "is_active": True,
        },
        "about_social_title": {"title_ar": "تواصل معنا", "body_ar": "", "is_active": True},
        "about_website_label": {"title_ar": "الموقع الرسمي", "body_ar": "", "is_active": True},
        "terms_page_title": {"title_ar": "الشروط والأحكام", "body_ar": "", "is_active": True},
        "terms_empty_label": {"title_ar": "لا توجد مستندات متاحة حالياً", "body_ar": "", "is_active": True},
        "terms_open_document_label": {"title_ar": "عرض المستند", "body_ar": "", "is_active": True},
        "terms_file_only_hint": {
            "title_ar": "اضغط على زر عرض المستند لفتح النسخة الرسمية.",
            "body_ar": "",
            "is_active": True,
        },
        "terms_missing_document_hint": {
            "title_ar": "لا توجد بيانات متاحة لهذا المستند حالياً.",
            "body_ar": "",
            "is_active": True,
        },
        "contact_gate_title": {"title_ar": "سجّل دخولك", "body_ar": "", "is_active": True},
        "contact_gate_description": {
            "title_ar": "يجب تسجيل الدخول لعرض تذاكر الدعم وفتح بلاغ جديد.",
            "body_ar": "",
            "is_active": True,
        },
        "contact_gate_login_label": {"title_ar": "تسجيل الدخول", "body_ar": "", "is_active": True},
        "contact_page_title": {"title_ar": "تواصل مع منصة نوافذ", "body_ar": "", "is_active": True},
        "contact_refresh_label": {"title_ar": "تحديث", "body_ar": "", "is_active": True},
        "contact_new_ticket_label": {"title_ar": "بلاغ جديد", "body_ar": "", "is_active": True},
        "contact_list_title": {"title_ar": "قائمة البلاغات", "body_ar": "", "is_active": True},
        "contact_create_title": {"title_ar": "إنشاء بلاغ جديد", "body_ar": "", "is_active": True},
        "contact_detail_title": {"title_ar": "تفاصيل البلاغ", "body_ar": "", "is_active": True},
        "contact_empty_label": {"title_ar": "لا توجد بلاغات حتى الآن", "body_ar": "", "is_active": True},
        "contact_team_placeholder": {"title_ar": "اختر فريق الدعم", "body_ar": "", "is_active": True},
        "contact_description_label": {"title_ar": "التفاصيل", "body_ar": "", "is_active": True},
        "contact_attachments_label": {"title_ar": "مرفقات (اختياري)", "body_ar": "", "is_active": True},
        "contact_cancel_label": {"title_ar": "إلغاء", "body_ar": "", "is_active": True},
        "contact_submit_label": {"title_ar": "إرسال البلاغ", "body_ar": "", "is_active": True},
        "contact_reply_placeholder": {"title_ar": "اكتب تعليقك...", "body_ar": "", "is_active": True},
        "contact_reply_submit_label": {"title_ar": "إرسال التعليق", "body_ar": "", "is_active": True},
    }

    for key, payload in defaults.items():
        SiteContentBlock.objects.get_or_create(key=key, defaults=payload)


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0014_add_about_terms_contact_content_keys"),
    ]

    operations = [
        migrations.RunPython(seed_blocks, noop_reverse),
    ]
