from django.contrib import admin

from .models import PlatformConfig, ReminderLog


@admin.register(PlatformConfig)
class PlatformConfigAdmin(admin.ModelAdmin):
    fieldsets = (
        ("الضريبة", {
            "fields": ("vat_percent",),
        }),
        ("الاشتراكات", {
            "fields": (
                "subscription_grace_days",
                "subscription_yearly_duration_days",
                "subscription_monthly_duration_days",
                "subscription_reminder_days_before",
            ),
        }),
        ("التوثيق", {
            "fields": (
                "verification_validity_days",
                "verification_currency",
                "verification_reminder_days_before",
            ),
        }),
        ("الترويج", {
            "fields": (
                "promo_vat_percent",
                "promo_min_campaign_hours",
                "promo_base_prices",
                "promo_position_multipliers",
            ),
        }),
        ("الخدمات الإضافية", {
            "fields": (
                "extras_vat_percent",
                "extras_default_duration_days",
                "extras_short_duration_days",
                "extras_currency",
            ),
        }),
        ("التميز", {
            "fields": (
                "excellence_review_cycle_days",
                "excellence_min_rating",
                "excellence_min_orders",
                "excellence_top_n_club",
            ),
        }),
        ("حدود الرفع والتصدير", {
            "fields": (
                "upload_max_file_size_mb",
                "promo_asset_image_max_file_size_mb",
                "promo_asset_video_max_file_size_mb",
                "promo_asset_pdf_max_file_size_mb",
                "promo_asset_other_max_file_size_mb",
                "promo_home_banner_image_max_file_size_mb",
                "promo_home_banner_video_max_file_size_mb",
                "export_pdf_max_rows",
                "export_xlsx_max_rows",
            ),
        }),
    )
    list_display = ("__str__", "vat_percent", "subscription_grace_days", "updated_at")

    def has_add_permission(self, request):
        # Only allow one instance
        return not PlatformConfig.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(ReminderLog)
class ReminderLogAdmin(admin.ModelAdmin):
    list_display = ("reminder_type", "user", "reference_id", "days_before", "sent_at")
    list_filter = ("reminder_type", "days_before")
    search_fields = ("user__phone",)
    readonly_fields = ("user", "reminder_type", "reference_id", "days_before", "sent_at")
    ordering = ("-sent_at",)

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
