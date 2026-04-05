from __future__ import annotations

import re

from django.apps import apps
from django.utils.text import camel_case_to_spaces


_ARABIC_RE = re.compile(r"[\u0600-\u06FF]")
_APPLIED = False


APP_LABEL_OVERRIDES = {
    "accounts": "الحسابات والمستخدمون",
    "providers": "مزودو الخدمات",
    "marketplace": "سوق الخدمات",
    "messaging": "المحادثات",
    "dashboard": "لوحات المتابعة",
    "backoffice": "صلاحيات البوابة الداخلية",
    "unified_requests": "محرك الطلبات الموحد",
    "support": "الدعم الفني",
    "billing": "الفوترة والمدفوعات",
    "verification": "التوثيق",
    "promo": "الترويج والإعلانات",
    "subscriptions": "الاشتراكات",
    "extras": "الخدمات الإضافية",
    "extras_portal": "بوابة الخدمات الإضافية",
    "features": "المزايا والاشتراطات",
    "analytics": "التحليلات",
    "audit": "السجل والتدقيق",
    "notifications": "الإشعارات",
    "reviews": "التقييمات",
    "content": "إدارة المحتوى",
    "core": "النواة المشتركة",
}


MODEL_LABEL_OVERRIDES = {
    "User": "مستخدم",
    "Wallet": "محفظة",
    "OTP": "رمز تحقق",
    "Dashboard": "لوحة",
    "UserAccessProfile": "ملف صلاحيات مستخدم",
    "Invoice": "فاتورة",
    "InvoiceLineItem": "بند فاتورة",
    "PaymentAttempt": "محاولة دفع",
    "WebhookEvent": "حدث Webhook",
    "AuditLog": "سجل تدقيق",
    "ExtraPurchase": "شراء خدمة إضافية",
    "ExtrasPortalSubscription": "اشتراك بوابة الإضافات",
    "ExtrasPortalFinanceSettings": "إعدادات مالية للإضافات",
    "ExtrasPortalScheduledMessage": "رسالة مجدولة",
    "ExtrasPortalScheduledMessageRecipient": "مستلم رسالة مجدولة",
    "SiteContentBlock": "كتلة محتوى",
    "SiteLegalDocument": "مستند قانوني",
    "SiteLinks": "روابط الموقع",
    "Category": "تصنيف",
    "SubCategory": "تصنيف فرعي",
    "ProviderProfile": "ملف مقدم الخدمة",
    "ProviderPortfolioItem": "عنصر أعمال مقدم الخدمة",
    "ProviderSpotlightItem": "عنصر إبراز مقدم الخدمة",
    "ProviderPortfolioLike": "إعجاب بمعرض الأعمال",
    "ProviderPortfolioSave": "حفظ من معرض الأعمال",
    "ProviderSpotlightLike": "إعجاب بعنصر إبراز",
    "ProviderSpotlightSave": "حفظ عنصر إبراز",
    "ProviderCategory": "تصنيف مقدم خدمة",
    "ProviderService": "خدمة مقدم",
    "ProviderFollow": "متابعة مقدم",
    "ProviderLike": "إعجاب بمقدم",
    "ServiceRequest": "طلب خدمة",
    "Offer": "عرض",
    "RequestStatusLog": "سجل حالة الطلب",
    "ServiceRequestAttachment": "مرفق طلب خدمة",
    "Thread": "محادثة",
    "Message": "رسالة",
    "MessageRead": "قراءة رسالة",
    "ThreadUserState": "حالة مستخدم في المحادثة",
    "Notification": "إشعار",
    "NotificationPreference": "تفضيل إشعارات",
    "DeviceToken": "رمز جهاز",
    "EventLog": "سجل حدث",
    "PromoRequest": "طلب ترويج",
    "PromoAsset": "مادة ترويجية",
    "PromoAdPrice": "سعر إعلان ترويجي",
    "Review": "تقييم",
    "SubscriptionPlan": "خطة اشتراك",
    "Subscription": "اشتراك",
    "SupportTeam": "فريق دعم",
    "SupportTicket": "تذكرة دعم",
    "SupportAttachment": "مرفق تذكرة",
    "SupportComment": "تعليق دعم",
    "SupportStatusLog": "سجل حالة الدعم",
    "UnifiedRequest": "طلب موحد",
    "UnifiedRequestMetadata": "بيانات إضافية للطلب الموحد",
    "UnifiedRequestAssignmentLog": "سجل تحويل الطلب الموحد",
    "UnifiedRequestStatusLog": "سجل حالة الطلب الموحد",
    "VerificationRequest": "طلب توثيق",
    "VerificationDocument": "مستند توثيق",
    "VerificationRequirement": "متطلب توثيق",
    "VerificationRequirementAttachment": "مرفق متطلب توثيق",
    "VerifiedBadge": "شارة موثقة",
}


FIELD_LABEL_OVERRIDES = {
    "id": "المعرّف",
    "code": "الرمز",
    "phone": "رقم الجوال",
    "email": "البريد الإلكتروني",
    "username": "اسم المستخدم",
    "password": "كلمة المرور",
    "first_name": "الاسم الأول",
    "last_name": "الاسم الأخير",
    "city": "المدينة",
    "role_state": "حالة الدور",
    "terms_accepted_at": "وقت قبول الشروط",
    "is_active": "نشط",
    "is_staff": "موظف",
    "is_superuser": "مدير عام",
    "is_used": "مستخدم",
    "is_internal": "داخلي",
    "is_read": "مقروء",
    "is_pinned": "مثبّت",
    "is_follow_up": "يتطلب متابعة",
    "is_urgent": "عاجل",
    "is_direct": "مباشر",
    "is_favorite": "مفضل",
    "is_archived": "مؤرشف",
    "is_blocked": "محظور",
    "is_verified_blue": "موثق بالأزرق",
    "is_verified_green": "موثق بالأخضر",
    "created_at": "تاريخ الإنشاء",
    "updated_at": "تاريخ التحديث",
    "uploaded_at": "تاريخ الرفع",
    "last_seen_at": "آخر ظهور",
    "last_login": "آخر تسجيل دخول",
    "start_at": "بداية الفترة",
    "end_at": "نهاية الفترة",
    "started_at": "تاريخ البداية",
    "ends_at": "تاريخ الانتهاء",
    "expires_at": "تاريخ الانتهاء",
    "created_by": "أنشأ بواسطة",
    "updated_by": "آخر تحديث بواسطة",
    "uploaded_by": "رُفع بواسطة",
    "changed_by": "تم التغيير بواسطة",
    "assigned_to": "مُسند إلى",
    "assigned_at": "تاريخ الإسناد",
    "assigned_team": "الفريق المسند",
    "assigned_user": "المستخدم المسند",
    "requester": "مقدم الطلب",
    "user": "المستخدم",
    "provider": "مقدم الخدمة",
    "client": "العميل",
    "actor": "المنفّذ",
    "title": "العنوان",
    "description": "الوصف",
    "summary": "الملخص",
    "body": "المحتوى",
    "text": "النص",
    "note": "ملاحظة",
    "comment": "تعليق",
    "status": "الحالة",
    "priority": "الأولوية",
    "request_type": "نوع الطلب",
    "ticket_type": "نوع التذكرة",
    "ad_type": "نوع الإعلان",
    "provider_type": "نوع مقدم الخدمة",
    "kind": "النوع",
    "level": "المستوى",
    "platform": "المنصة",
    "currency": "العملة",
    "amount": "المبلغ",
    "subtotal": "المجموع الفرعي",
    "total": "الإجمالي",
    "vat_percent": "نسبة الضريبة",
    "vat_amount": "قيمة الضريبة",
    "price": "السعر",
    "price_from": "السعر من",
    "price_to": "السعر إلى",
    "price_unit": "وحدة السعر",
    "price_per_day": "السعر اليومي",
    "balance": "الرصيد",
    "duration_days": "المدة بالأيام",
    "total_days": "إجمالي الأيام",
    "period": "الفترة",
    "grace_end_at": "نهاية فترة السماح",
    "auto_renew": "تجديد تلقائي",
    "category": "التصنيف",
    "subcategory": "التصنيف الفرعي",
    "name": "الاسم",
    "name_ar": "الاسم بالعربية",
    "display_name": "اسم العرض",
    "bio": "نبذة",
    "website": "الموقع الإلكتروني",
    "website_url": "رابط الموقع",
    "x_url": "رابط X",
    "instagram_url": "رابط إنستغرام",
    "snapchat_url": "رابط سناب شات",
    "tiktok_url": "رابط تيك توك",
    "youtube_url": "رابط يوتيوب",
    "whatsapp": "واتساب",
    "whatsapp_url": "رابط واتساب",
    "android_store": "متجر أندرويد",
    "ios_store": "متجر iOS",
    "profile_image": "صورة الملف",
    "cover_image": "صورة الغلاف",
    "thumbnail": "الصورة المصغرة",
    "file": "الملف",
    "file_type": "نوع الملف",
    "attachment": "مرفق",
    "attachment_type": "نوع المرفق",
    "attachment_name": "اسم المرفق",
    "item": "العنصر",
    "request": "الطلب",
    "ticket": "التذكرة",
    "thread": "المحادثة",
    "message": "الرسالة",
    "sender": "المرسل",
    "read_at": "وقت القراءة",
    "event_type": "نوع الحدث",
    "event_id": "معرف الحدث",
    "reference_type": "نوع المرجع",
    "reference_id": "معرف المرجع",
    "request_id": "معرف الطلب",
    "source_app": "التطبيق المصدر",
    "source_model": "الموديل المصدر",
    "source_object_id": "معرف الكيان المصدر",
    "payload": "البيانات",
    "meta": "بيانات إضافية",
    "request_payload": "بيانات الطلب",
    "response_payload": "بيانات الاستجابة",
    "token": "الرمز",
    "idempotency_key": "مفتاح عدم التكرار",
    "provider_reference": "مرجع المزود",
    "checkout_url": "رابط الدفع",
    "redirect_url": "رابط التحويل",
    "action": "الإجراء",
    "user_agent": "وكيل المستخدم",
    "ip_address": "عنوان IP",
    "attempts": "عدد المحاولات",
    "from_status": "من حالة",
    "to_status": "إلى حالة",
    "from_user": "من مستخدم",
    "to_user": "إلى مستخدم",
    "from_team_code": "رمز الفريق المصدر",
    "to_team_code": "رمز الفريق الهدف",
    "assigned_team_code": "رمز الفريق المسند",
    "assigned_team_name": "اسم الفريق المسند",
    "reviewed_at": "تاريخ المراجعة",
    "activated_at": "تاريخ التفعيل",
    "approved_at": "تاريخ الاعتماد",
    "closed_at": "تاريخ الإغلاق",
    "cancelled_at": "تاريخ الإلغاء",
    "canceled_at": "تاريخ الإلغاء",
    "cancel_reason": "سبب الإلغاء",
    "reject_reason": "سبب الرفض",
    "decided_by": "صاحب القرار",
    "decided_at": "تاريخ القرار",
    "decision_note": "ملاحظة القرار",
    "quote_note": "ملاحظة التسعير",
    "quote_deadline": "مهلة التسعير",
    "expected_delivery_at": "التسليم المتوقع",
    "delivered_at": "تاريخ التسليم",
    "estimated_service_amount": "القيمة التقديرية للخدمة",
    "actual_service_amount": "القيمة الفعلية للخدمة",
    "received_amount": "المبلغ المستلم",
    "remaining_amount": "المبلغ المتبقي",
    "provider_inputs_approved": "اعتماد مدخلات المقدم",
    "provider_inputs_decided_at": "تاريخ قرار مدخلات المقدم",
    "provider_inputs_decision_note": "ملاحظة قرار مدخلات المقدم",
    "frequency": "التكرار",
    "position": "الموضع",
    "target_city": "المدينة المستهدفة",
    "target_category": "التصنيف المستهدف",
    "target_provider": "مقدم الخدمة المستهدف",
    "target_portfolio_item": "عنصر الأعمال المستهدف",
    "message_title": "عنوان الرسالة",
    "message_body": "نص الرسالة",
    "asset_type": "نوع المادة",
    "doc_type": "نوع المستند",
    "version": "الإصدار",
    "published_at": "تاريخ النشر",
    "key": "المفتاح",
    "title_ar": "العنوان بالعربية",
    "body_ar": "المحتوى بالعربية",
    "sort_order": "ترتيب العرض",
    "badge_type": "نوع الشارة",
    "verification_code": "رمز التوثيق",
    "verification_title": "عنوان التوثيق",
    "management_reply": "رد الإدارة",
    "management_reply_at": "تاريخ رد الإدارة",
    "management_reply_by": "رد الإدارة بواسطة",
    "provider_reply": "رد مقدم الخدمة",
    "provider_reply_at": "تاريخ رد مقدم الخدمة",
    "provider_reply_edited_at": "تاريخ تعديل رد مقدم الخدمة",
    "moderation_status": "حالة الإشراف",
    "moderated_at": "تاريخ الإشراف",
    "moderated_by": "الإشراف بواسطة",
    "moderation_note": "ملاحظة الإشراف",
    "features": "المزايا",
    "notes": "ملاحظات",
    "error": "الخطأ",
    "audience_mode": "نمط الجمهور",
    "quality": "الجودة",
    "response_speed": "سرعة الاستجابة",
    "credibility": "الموثوقية",
    "on_time": "الالتزام بالوقت",
    "enable": "تفعيل",
}


TOKEN_TRANSLATIONS = {
    "provider": "مقدم",
    "request": "طلب",
    "requests": "طلبات",
    "user": "مستخدم",
    "users": "مستخدمون",
    "ticket": "تذكرة",
    "status": "حالة",
    "log": "سجل",
    "message": "رسالة",
    "messages": "رسائل",
    "thread": "محادثة",
    "subscription": "اشتراك",
    "subscriptions": "اشتراكات",
    "plan": "خطة",
    "notification": "إشعار",
    "notifications": "إشعارات",
    "review": "تقييم",
    "invoice": "فاتورة",
    "payment": "دفع",
    "attempt": "محاولة",
    "event": "حدث",
    "document": "مستند",
    "attachment": "مرفق",
    "profile": "ملف",
    "service": "خدمة",
    "category": "تصنيف",
    "content": "محتوى",
    "support": "دعم",
    "team": "فريق",
    "code": "رمز",
    "type": "نوع",
    "at": "في",
}


def _contains_arabic(value: str) -> bool:
    return bool(_ARABIC_RE.search(value or ""))


def _normalize_spaces(value: str) -> str:
    return " ".join((value or "").strip().split()).lower()


def _translate_identifier(value: str) -> str | None:
    if not value:
        return None
    normalized = camel_case_to_spaces(value).replace("-", " ").replace("_", " ")
    tokens = [token for token in normalized.lower().split() if token]
    if not tokens:
        return None

    translated_tokens = []
    mapped_any = False
    for token in tokens:
        translated = TOKEN_TRANSLATIONS.get(token)
        if translated:
            translated_tokens.append(translated)
            mapped_any = True
        else:
            translated_tokens.append(token)
    if not mapped_any:
        return None
    return " ".join(translated_tokens)


def _is_local_project_model(model) -> bool:
    return (model.__module__ or "").startswith("apps.")


def _is_default_model_verbose(model) -> bool:
    current = _normalize_spaces(str(model._meta.verbose_name))
    default = _normalize_spaces(camel_case_to_spaces(model.__name__))
    return current == default


def _is_default_model_plural(model) -> bool:
    singular_default = _normalize_spaces(camel_case_to_spaces(model.__name__))
    plural_default = f"{singular_default}s"
    current = _normalize_spaces(str(model._meta.verbose_name_plural))
    return current in {singular_default, plural_default}


def _is_default_field_verbose(field) -> bool:
    current = _normalize_spaces(str(getattr(field, "verbose_name", "")))
    default = _normalize_spaces(field.name.replace("_", " "))
    if field.name == "id":
        return current in {"id", "pk", "identifier", ""}
    return current in {default, _normalize_spaces(field.name)}


def _apply_model_translation(model) -> None:
    if not _is_local_project_model(model):
        return

    translated_model_name = MODEL_LABEL_OVERRIDES.get(model.__name__) or _translate_identifier(model.__name__)
    if translated_model_name and _is_default_model_verbose(model):
        model._meta.verbose_name = translated_model_name
    if translated_model_name and _is_default_model_plural(model):
        model._meta.verbose_name_plural = translated_model_name

    for field in [*model._meta.fields, *model._meta.many_to_many]:
        if not hasattr(field, "name") or not hasattr(field, "verbose_name"):
            continue
        if not _is_default_field_verbose(field):
            continue
        translated_field_name = FIELD_LABEL_OVERRIDES.get(field.name) or _translate_identifier(field.name)
        if translated_field_name and not _contains_arabic(str(field.verbose_name)):
            field.verbose_name = translated_field_name


def apply_admin_arabic_localization() -> None:
    global _APPLIED
    if _APPLIED:
        return

    for app_config in apps.get_app_configs():
        translated_app_label = APP_LABEL_OVERRIDES.get(app_config.label)
        if translated_app_label:
            app_config.verbose_name = translated_app_label

    for model in apps.get_models():
        _apply_model_translation(model)

    _APPLIED = True
