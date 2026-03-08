from django import forms
from django.contrib import admin

from apps.verification.services import verification_pricing_for_plan

from .capabilities import plan_capabilities_for_plan, plan_capabilities_for_tier
from .models import PlanTier, SubscriptionPlan, Subscription
from .offers import subscription_offer_for_plan, subscription_offer_for_tier


def _split_text_values(value: str) -> list[str]:
    items = []
    for raw in str(value or "").replace(",", "\n").splitlines():
        text = raw.strip()
        if text:
            items.append(text)
    return items


def _join_text_values(values) -> str:
    return "\n".join(str(value).strip() for value in values or [] if str(value).strip())


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

    def _set_initial_if_missing(self, field_name: str, current_value, fallback):
        if current_value not in (None, ""):
            return
        self.fields[field_name].initial = fallback

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
        "direct_chat_quota_display",
        "upload_limit_display",
        "is_active",
    )
    list_filter = ("tier", "period", "is_active")
    search_fields = ("code", "title", "description")
    readonly_fields = ("normalized_tier_preview", "created_at")
    fieldsets = (
        ("بيانات الباقة", {"fields": ("normalized_tier_preview", "code", "tier", "title", "description", "period", "price", "is_active", "created_at")}),
        ("المزايا والعرض", {"fields": ("features_text", "feature_bullets_text")}),
        ("قيود الوصول والمحادثات", {"fields": (
            "notifications_enabled",
            "competitive_visibility_delay_hours",
            "competitive_visibility_label",
            "banner_images_limit",
            "banner_images_label",
            "direct_chat_quota",
            "direct_chat_label",
        )}),
        ("الترويج والتذكير", {"fields": (
            "promotional_chat_messages_enabled",
            "promotional_notification_messages_enabled",
            "reminder_schedule_hours_text",
            "reminder_policy_label",
        )}),
        ("الدعم والتخزين", {"fields": (
            "support_priority",
            "support_is_priority",
            "support_sla_hours",
            "support_sla_label",
            "storage_policy",
            "storage_label",
            "storage_multiplier",
            "storage_upload_max_mb",
        )}),
        ("رسوم التوثيق", {"fields": ("verification_blue_fee", "verification_green_fee")}),
    )

    @admin.display(description="التصنيف الفعلي")
    def normalized_tier_preview(self, obj):
        if obj is None:
            return "-"
        return obj.normalized_tier()

    @admin.display(description="حد المحادثات")
    def direct_chat_quota_display(self, obj):
        return plan_capabilities_for_plan(obj)["messaging"]["direct_chat_quota"]

    @admin.display(description="حد الرفع MB")
    def upload_limit_display(self, obj):
        return plan_capabilities_for_plan(obj)["storage"]["upload_max_mb"]


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "plan", "status", "start_at", "end_at", "grace_end_at", "auto_renew")
    list_filter = ("status", "auto_renew")
    search_fields = ("user__phone", "plan__code")
    ordering = ("-id",)
