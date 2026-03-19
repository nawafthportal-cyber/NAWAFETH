from django.contrib import admin
from .models import VerificationRequest, VerificationDocument, VerifiedBadge, VerificationPricingRule


@admin.register(VerificationPricingRule)
class VerificationPricingRuleAdmin(admin.ModelAdmin):
    list_display = ("badge_type", "fee", "currency", "is_active", "note", "updated_at")
    list_filter = ("is_active", "badge_type")
    search_fields = ("note",)
    list_editable = ("fee", "is_active")
    ordering = ("badge_type",)


class VerificationDocumentInline(admin.TabularInline):
    model = VerificationDocument
    extra = 0


@admin.register(VerificationRequest)
class VerificationRequestAdmin(admin.ModelAdmin):
    list_display = ("code", "requester", "badge_type", "status", "invoice", "requested_at", "expires_at")
    list_filter = ("badge_type", "status")
    search_fields = ("code", "requester__phone")
    ordering = ("-id",)
    inlines = [VerificationDocumentInline]


@admin.register(VerifiedBadge)
class VerifiedBadgeAdmin(admin.ModelAdmin):
    list_display = ("user", "badge_type", "is_active", "activated_at", "expires_at")
    list_filter = ("badge_type", "is_active")
    search_fields = ("user__phone",)
    ordering = ("-id",)
