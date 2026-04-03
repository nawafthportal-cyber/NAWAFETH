from django.contrib import admin
from .models import (
    VerifiedBadge,
    VerificationBlueProfile,
    VerificationDocument,
    VerificationInquiryProfile,
    VerificationPricingRule,
    VerificationRequest,
    VerificationRequirement,
    VerificationRequirementAttachment,
)


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
    readonly_fields = ("uploaded_by", "uploaded_at", "decided_by", "decided_at")


class VerificationRequirementInline(admin.TabularInline):
    model = VerificationRequirement
    extra = 0
    readonly_fields = ("decided_by", "decided_at", "created_at")


@admin.register(VerificationRequest)
class VerificationRequestAdmin(admin.ModelAdmin):
    list_display = ("code", "requester", "badge_type", "status", "invoice", "requested_at", "expires_at")
    list_filter = ("badge_type", "status")
    search_fields = ("code", "requester__phone")
    ordering = ("-id",)
    inlines = [VerificationDocumentInline, VerificationRequirementInline]
    list_select_related = ("requester", "assigned_to", "invoice")
    readonly_fields = ("requested_at", "reviewed_at", "approved_at", "activated_at", "expires_at", "updated_at")


@admin.register(VerifiedBadge)
class VerifiedBadgeAdmin(admin.ModelAdmin):
    list_display = ("user", "badge_type", "is_active", "activated_at", "expires_at")
    list_filter = ("badge_type", "is_active")
    search_fields = ("user__phone",)
    ordering = ("-id",)
    list_select_related = ("user", "request")


@admin.register(VerificationBlueProfile)
class VerificationBlueProfileAdmin(admin.ModelAdmin):
    list_display = ("request", "subject_type", "verified_name", "is_name_approved", "verified_at", "updated_at")
    list_filter = ("subject_type", "is_name_approved", "verification_source")
    search_fields = ("request__code", "official_number", "verified_name")
    ordering = ("-updated_at", "-id")
    list_select_related = ("request",)


@admin.register(VerificationDocument)
class VerificationDocumentAdmin(admin.ModelAdmin):
    list_display = ("id", "request", "doc_type", "title", "is_approved", "uploaded_by", "uploaded_at")
    list_filter = ("doc_type", "is_approved")
    search_fields = ("request__code", "title", "decision_note", "uploaded_by__phone")
    ordering = ("-id",)
    list_select_related = ("request", "uploaded_by", "decided_by")
    readonly_fields = ("uploaded_at", "decided_at")


@admin.register(VerificationInquiryProfile)
class VerificationInquiryProfileAdmin(admin.ModelAdmin):
    list_display = ("ticket", "linked_request", "updated_at")
    search_fields = ("ticket__code", "linked_request__code", "operator_comment")
    ordering = ("-updated_at", "-id")
    list_select_related = ("ticket", "linked_request")


@admin.register(VerificationRequirement)
class VerificationRequirementAdmin(admin.ModelAdmin):
    list_display = ("id", "request", "badge_type", "code", "title", "is_approved", "sort_order", "created_at")
    list_filter = ("badge_type", "is_approved")
    search_fields = ("request__code", "code", "title", "decision_note")
    ordering = ("request", "sort_order", "id")
    list_select_related = ("request", "decided_by")
    readonly_fields = ("created_at", "decided_at")


@admin.register(VerificationRequirementAttachment)
class VerificationRequirementAttachmentAdmin(admin.ModelAdmin):
    list_display = ("id", "requirement", "uploaded_by", "uploaded_at")
    search_fields = ("requirement__request__code", "requirement__code", "uploaded_by__phone", "uploaded_by__username")
    ordering = ("-id",)
    list_select_related = ("requirement", "uploaded_by", "requirement__request")
    readonly_fields = ("uploaded_at",)
