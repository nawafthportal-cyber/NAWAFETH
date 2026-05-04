from django import forms
from django.contrib import admin
from django.utils.html import format_html

from apps.verification.services import verification_pricing_for_plan

from .capabilities import plan_capabilities_for_plan, plan_capabilities_for_tier
from .models import PlanTier, SubscriptionPlan, Subscription, SubscriptionInquiryProfile, SubscriptionStatus
from .offers import subscription_offer_for_plan, subscription_offer_for_tier


FIELD_HELP_TEXTS = {
    "code": "معرف داخلي ثابت للباقة. يفضل عدم تغييره بعد اعتماد الباقة في النظام.",
    "tier": "التصنيف المرجعي للباقة: أساسية أو ريادية أو احترافية. بعض الحقول التشغيلية ستظهر أو تختفي تلقائياً حسب هذا الاختيار لتقليل الالتباس.",
    "title": "الاسم الظاهر لمقدم الخدمة في صفحات الاشتراك ولوحة المقارنة.",
    "description": "وصف مختصر تسويقي يظهر مع الباقة في الواجهة.",
    "period": "الدورية المعتمدة لهذه الباقة عند إنشاء طلب الاشتراك.",
    "price": "السعر الأساسي للباقة قبل أي معالجة إضافية في الفاتورة.",
    "is_active": "عند الإلغاء لن تظهر الباقة كخيار جديد للمستخدمين.",
    "notifications_enabled": "تحدد ما إذا كانت التنبيهات الأساسية مفعلة ضمن الباقة.",
    "competitive_visibility_delay_hours": "عدد الساعات قبل ظهور الطلبات التنافسية لصاحب هذه الباقة.",
    "competitive_visibility_label": "النص الظاهر في الواجهة لوصف توقيت ظهور الطلبات التنافسية.",
    "urgent_visibility_delay_hours": "عدد الساعات قبل وصول الطلبات العاجلة لصاحب هذه الباقة.",
    "urgent_visibility_label": "النص الظاهر في الواجهة لوصف توقيت وصول الطلبات العاجلة.",
    "banner_images_limit": "عدد صور الخلفية التي يمكن أن تظهر خلف الصورة الشخصية للمزود ضمن الباقة.",
    "banner_images_label": "النص الظاهر للمستخدم لوصف عدد خلفيات الملف الشخصي.",
    "spotlight_quota": "الحد الأقصى لعدد اللمحات التي يمكن للمزود الاحتفاظ بها في نفس الوقت.",
    "spotlight_label": "النص الظاهر للمستخدم لوصف حد اللمحات المتاحة.",
    "direct_chat_quota": "الحد العددي للمحادثات المباشرة المتاحة.",
    "direct_chat_label": "النص الظاهر للمستخدم لوصف حد المحادثات المباشرة.",
    "promotional_chat_messages_enabled": "السماح باستخدام الرسائل الدعائية داخل المحادثات.",
    "promotional_notification_messages_enabled": "السماح باستخدام الرسائل الدعائية كتنبيهات خارج المحادثة.",
    "reminder_policy_label": "الصياغة التجارية الظاهرة للمستخدم حول سياسة التذكير.",
    "support_priority": "رمز أولوية الدعم المستخدم داخلياً في تشغيل الدعم.",
    "support_is_priority": "يفعل معاملة الطلبات كأولوية مرتفعة ضمن الدعم.",
    "support_sla_hours": "عدد الساعات المستهدفة لخدمة الدعم لهذه الباقة.",
    "support_sla_label": "النص الظاهر للمستخدم لوصف سرعة الدعم.",
    "storage_policy": "السياسة الداخلية المعتمدة للسعة التخزينية.",
    "storage_label": "النص الظاهر للمستخدم لوصف السعة التخزينية.",
    "storage_multiplier": "مضاعف السعة مقارنة بالسعة المجانية الأساسية. اتركه فارغاً عند السعة المفتوحة.",
    "storage_upload_max_mb": "أقصى حجم للرفع بالميجابايت لكل ملف عند الحاجة التشغيلية.",
    "verification_blue_fee": "رسوم التوثيق الأزرق لهذه الباقة. ضع 0 إذا كان مشمولاً.",
    "verification_green_fee": "رسوم التوثيق الأخضر لهذه الباقة. ضع 0 إذا كان مشمولاً.",
}


FIELD_PLACEHOLDERS = {
    "code": "مثال: pro",
    "title": "مثال: الاحترافية",
    "description": "مثال: أعلى باقة اشتراك بمزايا دعائية كاملة وتوثيق مشمول ودعم فني سريع.",
    "features_text": "مثال:\nverify_blue\npromo_ads\npriority_support",
    "feature_bullets_text": "مثال:\nتشمل مزايا الأساسية والريادية مع كامل الصلاحيات الاحترافية.\nوصول لحظي للطلبات التنافسية ورسائل دعائية كاملة.",
    "reminder_schedule_hours_text": "مثال: 24, 120, 240",
    "competitive_visibility_label": "مثال: بعد 24 ساعة",
    "urgent_visibility_label": "مثال: لحظياً",
    "banner_images_label": "مثال: 3 خلفيات",
    "spotlight_label": "مثال: 3 لمحات",
    "direct_chat_label": "مثال: 10 محادثات مباشرة",
    "reminder_policy_label": "مثال: أول تنبيه + إرسال ثاني تنبيه بعد اكتمال الطلب بـ 120 ساعة",
    "support_sla_label": "مثال: خلال يومين",
    "storage_label": "مثال: ضعف السعة المجانية المتاحة",
}


def _split_text_values(value: str) -> list[str]:
    items = []
    for raw in str(value or "").replace(",", "\n").splitlines():
        text = raw.strip()
        if text:
            items.append(text)
    return items


def _join_text_values(values) -> str:
    return "\n".join(str(value).strip() for value in values or [] if str(value).strip())


def _preview_html(value: str, *, empty_message: str = "-"):
    text = str(value or "").strip()
    if not text:
        text = empty_message
    return format_html('<div style="white-space: normal; line-height: 1.7; max-width: 420px;">{}</div>', text)


class SubscriptionPlanAdminForm(forms.ModelForm):
    features_text = forms.CharField(
        required=False,
        label="مفاتيح الميزات",
        help_text="أدخل كل ميزة في سطر مستقل أو افصل بينها بفواصل.",
        widget=forms.Textarea(attrs={"rows": 4}),
    )
    feature_bullets_text = forms.CharField(
        required=False,
        label="نقاط عرض الباقة",
        help_text="النقاط التي تظهر في بطاقات وخلاصة الباقة.",
        widget=forms.Textarea(attrs={"rows": 5}),
    )
    reminder_schedule_hours_text = forms.CharField(
        required=False,
        label="ساعات التذكير",
        help_text="مثال: 24, 120, 240",
    )
    notifications_enabled = forms.BooleanField(required=False, label="تفعيل الإشعارات")
    promotional_chat_messages_enabled = forms.BooleanField(required=False, label="السماح بالرسائل الدعائية داخل المحادثات")
    promotional_notification_messages_enabled = forms.BooleanField(required=False, label="السماح بالرسائل الدعائية كإشعارات")
    support_is_priority = forms.BooleanField(required=False, label="دعم أولوية")

    class Meta:
        model = SubscriptionPlan
        fields = "__all__"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        plan = self.instance if getattr(self.instance, "pk", None) else None
        tier_value = getattr(self.instance, "tier", None) or self.initial.get("tier") or PlanTier.BASIC
        capabilities = plan_capabilities_for_plan(plan) if plan is not None else plan_capabilities_for_tier(tier_value)
        offer = subscription_offer_for_plan(plan) if plan is not None else subscription_offer_for_tier(tier_value)
        verification = verification_pricing_for_plan(plan)
        verification_prices = verification.get("prices") or {}

        self.fields["features_text"].initial = _join_text_values(getattr(plan, "feature_keys", lambda: [])())
        self.fields["feature_bullets_text"].initial = _join_text_values(offer.get("feature_bullets") or [])
        self.fields["reminder_schedule_hours_text"].initial = ", ".join(
            str(value) for value in (getattr(plan, "reminder_schedule", lambda: [])() or capabilities["reminders"]["schedule_hours"])
        )

        self._set_initial_if_missing("notifications_enabled", getattr(plan, "notifications_enabled", None), capabilities["notifications_enabled"])
        self._set_initial_if_missing(
            "competitive_visibility_delay_hours",
            getattr(plan, "competitive_visibility_delay_hours", None),
            capabilities["competitive_requests"]["visibility_delay_hours"],
        )
        self._set_initial_if_missing(
            "competitive_visibility_label",
            getattr(plan, "competitive_visibility_label", ""),
            capabilities["competitive_requests"]["visibility_label"],
        )
        self._set_initial_if_missing(
            "urgent_visibility_delay_hours",
            getattr(plan, "urgent_visibility_delay_hours", None),
            capabilities["urgent_requests"]["visibility_delay_hours"],
        )
        self._set_initial_if_missing(
            "urgent_visibility_label",
            getattr(plan, "urgent_visibility_label", ""),
            capabilities["urgent_requests"]["visibility_label"],
        )
        self._set_initial_if_missing(
            "banner_images_limit",
            getattr(plan, "banner_images_limit", None),
            capabilities["banner_images"]["limit"],
        )
        self._set_initial_if_missing(
            "banner_images_label",
            getattr(plan, "banner_images_label", ""),
            capabilities["banner_images"]["label"],
        )
        self._set_initial_if_missing(
            "spotlight_quota",
            getattr(plan, "spotlight_quota", None),
            capabilities["spotlights"]["quota"],
        )
        self._set_initial_if_missing(
            "spotlight_label",
            getattr(plan, "spotlight_label", ""),
            capabilities["spotlights"]["label"],
        )
        self._set_initial_if_missing(
            "direct_chat_quota",
            getattr(plan, "direct_chat_quota", None),
            capabilities["messaging"]["direct_chat_quota"],
        )
        self._set_initial_if_missing(
            "direct_chat_label",
            getattr(plan, "direct_chat_label", ""),
            capabilities["messaging"]["label"],
        )
        self._set_initial_if_missing(
            "promotional_chat_messages_enabled",
            getattr(plan, "promotional_chat_messages_enabled", None),
            capabilities["promotional_controls"]["chat_messages"],
        )
        self._set_initial_if_missing(
            "promotional_notification_messages_enabled",
            getattr(plan, "promotional_notification_messages_enabled", None),
            capabilities["promotional_controls"]["notification_messages"],
        )
        self._set_initial_if_missing(
            "reminder_policy_label",
            getattr(plan, "reminder_policy_label", ""),
            capabilities["reminders"]["label"],
        )
        self._set_initial_if_missing(
            "support_priority",
            getattr(plan, "support_priority", ""),
            capabilities["support"]["priority"],
        )
        self._set_initial_if_missing(
            "support_is_priority",
            getattr(plan, "support_is_priority", None),
            capabilities["support"]["is_priority"],
        )
        self._set_initial_if_missing(
            "support_sla_hours",
            getattr(plan, "support_sla_hours", None),
            capabilities["support"]["sla_hours"],
        )
        self._set_initial_if_missing(
            "support_sla_label",
            getattr(plan, "support_sla_label", ""),
            capabilities["support"]["sla_label"],
        )
        self._set_initial_if_missing(
            "storage_policy",
            getattr(plan, "storage_policy", ""),
            capabilities["storage"]["policy"],
        )
        self._set_initial_if_missing(
            "storage_label",
            getattr(plan, "storage_label", ""),
            capabilities["storage"]["label"],
        )
        self._set_initial_if_missing(
            "storage_multiplier",
            getattr(plan, "storage_multiplier", None),
            capabilities["storage"]["multiplier"],
        )
        self._set_initial_if_missing(
            "storage_upload_max_mb",
            getattr(plan, "storage_upload_max_mb", None),
            capabilities["storage"]["upload_max_mb"],
        )
        self._set_initial_if_missing(
            "verification_blue_fee",
            getattr(plan, "verification_blue_fee", None),
            (verification_prices.get("blue") or {}).get("amount"),
        )
        self._set_initial_if_missing(
            "verification_green_fee",
            getattr(plan, "verification_green_fee", None),
            (verification_prices.get("green") or {}).get("amount"),
        )
        self._configure_field_ui()

    def _set_initial_if_missing(self, field_name: str, current_value, fallback):
        if field_name not in self.fields:
            return
        if current_value not in (None, ""):
            return
        self.fields[field_name].initial = fallback

    def _configure_field_ui(self):
        for field_name, help_text in FIELD_HELP_TEXTS.items():
            if field_name in self.fields:
                self.fields[field_name].help_text = help_text

        for field_name, placeholder in FIELD_PLACEHOLDERS.items():
            if field_name not in self.fields:
                continue
            widget = self.fields[field_name].widget
            widget.attrs["placeholder"] = placeholder

        for field_name in ("code", "title", "description"):
            if field_name in self.fields:
                self.fields[field_name].widget.attrs.setdefault("style", "width: 100%;")

        if "description" in self.fields:
            self.fields["description"].widget = forms.Textarea(attrs={
                "rows": 3,
                "placeholder": FIELD_PLACEHOLDERS["description"],
            })

        if "reminder_schedule_hours_text" in self.fields:
            self.fields["reminder_schedule_hours_text"].widget.attrs["dir"] = "ltr"

    def clean_features_text(self):
        return _split_text_values(self.cleaned_data.get("features_text", ""))

    def clean_feature_bullets_text(self):
        return _split_text_values(self.cleaned_data.get("feature_bullets_text", ""))

    def clean_reminder_schedule_hours_text(self):
        values = []
        for item in _split_text_values(self.cleaned_data.get("reminder_schedule_hours_text", "")):
            try:
                values.append(int(item))
            except ValueError as exc:
                raise forms.ValidationError("ساعات التذكير يجب أن تكون أرقامًا صحيحة مفصولة بفواصل أو أسطر.") from exc
        return values

    def save(self, commit=True):
        obj = super().save(commit=False)
        obj.features = self.cleaned_data.get("features_text", [])
        obj.feature_bullets = self.cleaned_data.get("feature_bullets_text", [])
        obj.reminder_schedule_hours = self.cleaned_data.get("reminder_schedule_hours_text", [])
        if commit:
            obj.save()
            self.save_m2m()
        return obj


@admin.register(SubscriptionPlan)
class SubscriptionPlanAdmin(admin.ModelAdmin):
    form = SubscriptionPlanAdminForm
    list_display = (
        "code",
        "title",
        "tier",
        "period",
        "price",
        "spotlight_quota_display",
        "upload_limit_display",
        "is_active",
    )
    list_filter = ("tier", "period", "is_active")
    search_fields = ("code", "title", "description")
    readonly_fields = (
        "core_services_note",
        "normalized_tier_preview",
        "derived_request_access_preview",
        "derived_competitive_request_access_preview",
        "derived_banner_images_preview",
        "derived_spotlight_preview",
        "derived_direct_chat_preview",
        "derived_reminder_policy_preview",
        "derived_promotional_permissions_preview",
        "derived_notifications_preview",
        "derived_support_sla_preview",
        "derived_storage_preview",
        "derived_verification_effect_preview",
        "created_at",
    )
    fieldsets = (
        ("البند الأساسي الثابت", {
            "description": "هذا البند ثابت في الواجهة ولا يُعدل من الآدمن، وهو موضح هنا فقط للتأكيد على فريق التشغيل.",
            "classes": ("wide", "subscription-plan-fieldset", "is-core"),
            "fields": ("core_services_note",),
        }),
        ("تعريف الباقة وسعر الباقة", {
            "description": "هذا القسم يضبط اسم الباقة وتصنيفها ودوريتها وسعر الباقة كما تظهر في بطاقة الباقة والجدول المقارن.",
            "classes": ("wide", "subscription-plan-fieldset", "is-identity"),
            "fields": (
                ("title", "code"),
                ("normalized_tier_preview", "tier"),
                ("period", "price"),
                "description",
                ("is_active", "created_at"),
            ),
        }),
        ("المحتوى الظاهر داخل بطاقة الباقة", {
            "description": "حرر هنا الوصف ونقاط العرض المختصرة التي تظهر للمستخدم داخل بطاقة الباقة قبل جدول المقارنة.",
            "classes": ("wide", "subscription-plan-fieldset", "is-content"),
            "fields": ("features_text", "feature_bullets_text"),
        }),
        ("وقت استقبال الطلبات العاجلة والتنافسية", {
            "description": "اضبط هنا النص والقيمة الفعلية للبندين: وقت استقبال الطلبات العاجلة ووقت استقبال الطلبات التنافسية.",
            "classes": ("wide", "subscription-plan-fieldset", "is-request-access"),
            "fields": (
                ("urgent_visibility_delay_hours", "urgent_visibility_label"),
                ("competitive_visibility_delay_hours", "competitive_visibility_label"),
            ),
        }),
        ("عدد صور شعار المنصة وعدد اللمحات المتاحة", {
            "description": "هذا القسم يتحكم مباشرة في بندي عدد صور شعار المنصة وعدد اللمحات المتاحة كما يظهران في جدول الباقات.",
            "classes": ("wide", "subscription-plan-fieldset", "is-promo-surfaces"),
            "fields": (
                ("banner_images_limit", "banner_images_label"),
                ("spotlight_quota", "spotlight_label"),
            ),
        }),
        ("الإشعارات والمحادثات المباشرة والرسائل الدعائية وسياسة التذكير", {
            "description": "ستجد هنا البنود المرتبطة بـ الإشعارات، حد المحادثات المباشرة، التحكم برسائل المحادثات والتنبيهات الدعائية، وسياسة رسائل التذكير.",
            "classes": ("wide", "subscription-plan-fieldset", "is-messaging"),
            "fields": (
                "notifications_enabled",
                ("direct_chat_quota", "direct_chat_label"),
                ("promotional_chat_messages_enabled", "promotional_notification_messages_enabled"),
                "reminder_schedule_hours_text",
                "reminder_policy_label",
            ),
        }),
        ("زمن الدعم الفني وأولوية الدعم وسعة التخزين والرفع", {
            "description": "هذا القسم يطابق بنود زمن الدعم الفني وأولوية الدعم وسعة التخزين والرفع الظاهرة في المقارنة.",
            "classes": ("wide", "subscription-plan-fieldset", "is-support-storage"),
            "fields": (
                ("support_priority", "support_is_priority"),
                ("support_sla_hours", "support_sla_label"),
                ("storage_policy", "storage_label"),
                ("storage_multiplier", "storage_upload_max_mb"),
            ),
        }),
        ("التوثيق الأزرق والأخضر", {
            "description": "اضبط هنا رسوم التوثيق الأزرق والتوثيق الأخضر. القيمة 0 تعني أن التوثيق مشمول داخل الباقة.",
            "classes": ("wide", "subscription-plan-fieldset", "is-verification"),
            "fields": (("verification_blue_fee", "verification_green_fee"),),
        }),
        ("المعاينات النهائية المطابقة لجدول الباقات", {
            "description": "راجع هنا الصياغة النهائية لكل بند كما ستظهر للمستخدم داخل جدول المقارنة، وبالترتيب الأقرب للواجهة.",
            "classes": ("wide", "subscription-plan-fieldset", "is-preview"),
            "fields": (
                ("derived_notifications_preview", "derived_storage_preview"),
                ("derived_request_access_preview", "derived_competitive_request_access_preview"),
                ("derived_banner_images_preview", "derived_spotlight_preview"),
                ("derived_direct_chat_preview", "derived_promotional_permissions_preview"),
                ("derived_reminder_policy_preview", "derived_support_sla_preview"),
                "derived_verification_effect_preview",
            ),
        }),
    )

    class Media:
        css = {"all": ("subscriptions/css/subscription_plan_admin.css",)}
        js = ("subscriptions/js/subscription_plan_admin.js",)

    @admin.display(description="التصنيف الفعلي")
    def normalized_tier_preview(self, obj):
        if obj is None:
            return "-"
        return obj.normalized_tier()

    @admin.display(description="الخدمة الأساسية الثابتة")
    def core_services_note(self, obj):
        return "جميع الخدمات الأساسية للمنصة كعميل وكمختص مفعلة دائماً لكل الباقات ولا تُعدل من الآدمن. بقية البنود أدناه قابلة للتعديل بالكامل لكل باقة."

    def _derived_preview_message(self, obj, value: str):
        if obj is None:
            return _preview_html("ستظهر هذه المعاينة بعد حفظ الباقة أول مرة.")
        return _preview_html(value)

    def _offer_preview(self, obj, key: str):
        if obj is None:
            return self._derived_preview_message(obj, "")
        offer = subscription_offer_for_plan(obj)
        return self._derived_preview_message(obj, offer.get(key) or "")

    @admin.display(description="معاينة وقت استقبال الطلبات العاجلة")
    def derived_request_access_preview(self, obj):
        return self._offer_preview(obj, "request_access_label")

    @admin.display(description="معاينة وقت استقبال الطلبات التنافسية")
    def derived_competitive_request_access_preview(self, obj):
        return self._offer_preview(obj, "competitive_request_access_label")

    @admin.display(description="معاينة صور الـ Banner")
    def derived_banner_images_preview(self, obj):
        return self._offer_preview(obj, "banner_images_label")

    @admin.display(description="معاينة عدد اللمحات المتاحة")
    def derived_spotlight_preview(self, obj):
        return self._offer_preview(obj, "spotlights_label")

    @admin.display(description="معاينة حد المحادثات المباشرة")
    def derived_direct_chat_preview(self, obj):
        return self._offer_preview(obj, "direct_chat_label")

    @admin.display(description="معاينة رسائل التذكير")
    def derived_reminder_policy_preview(self, obj):
        return self._offer_preview(obj, "reminder_policy_label")

    @admin.display(description="معاينة التحكم برسائل المحادثات والتنبيهات الدعائية")
    def derived_promotional_permissions_preview(self, obj):
        return self._offer_preview(obj, "promotional_permissions_label")

    @admin.display(description="معاينة الإشعارات")
    def derived_notifications_preview(self, obj):
        return self._offer_preview(obj, "notifications_label")

    @admin.display(description="معاينة زمن الدعم الفني")
    def derived_support_sla_preview(self, obj):
        return self._offer_preview(obj, "support_sla_label")

    @admin.display(description="معاينة سعة التخزين والرفع")
    def derived_storage_preview(self, obj):
        return self._offer_preview(obj, "storage_label")

    @admin.display(description="معاينة التوثيق الأزرق والأخضر")
    def derived_verification_effect_preview(self, obj):
        return self._offer_preview(obj, "verification_effect_label")

    @admin.display(description="حد اللمحات")
    def spotlight_quota_display(self, obj):
        return plan_capabilities_for_plan(obj)["spotlights"]["quota"]

    @admin.display(description="حد الرفع MB")
    def upload_limit_display(self, obj):
        return plan_capabilities_for_plan(obj)["storage"]["upload_max_mb"]


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "plan", "status", "start_at", "end_at", "grace_end_at", "auto_renew")
    list_filter = ("status", "auto_renew", "plan__tier")
    search_fields = ("user__phone", "plan__code", "plan__title")
    ordering = ("-id",)
    list_select_related = ("user", "plan")


@admin.register(SubscriptionInquiryProfile)
class SubscriptionInquiryProfileAdmin(admin.ModelAdmin):
    list_display = ("ticket", "linked_subscription", "updated_at")
    search_fields = ("ticket__code", "ticket__requester__phone", "operator_comment")
    ordering = ("-updated_at", "-id")
    list_select_related = ("ticket", "ticket__requester")

    @admin.display(description="الاشتراك المرتبط")
    def linked_subscription(self, obj):
        requester = getattr(obj.ticket, "requester", None)
        if requester is None:
            return "-"
        subscription = requester.subscriptions.filter(
            status__in=(SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE)
        ).select_related("plan").order_by("-end_at", "-id").first()
        return subscription or "-"
