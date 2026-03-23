from django.contrib import admin

from .models import Offer, RequestStatusLog, ServiceRequest, ServiceRequestAttachment, ServiceRequestDispatch


class ServiceRequestAttachmentInline(admin.TabularInline):
	model = ServiceRequestAttachment
	extra = 0
	readonly_fields = ("created_at",)


class ServiceRequestDispatchInline(admin.TabularInline):
	model = ServiceRequestDispatch
	extra = 0
	readonly_fields = ("dispatched_at", "dispatch_attempts", "last_error", "idempotency_key", "created_at", "updated_at")


@admin.register(ServiceRequest)
class ServiceRequestAdmin(admin.ModelAdmin):
	list_display = (
		"id",
		"title",
		"request_type",
		"status",
		"city",
		"created_at",
	)
	list_filter = ("request_type", "status", "city")
	search_fields = ("title", "description")
	inlines = [ServiceRequestAttachmentInline, ServiceRequestDispatchInline]
	list_select_related = ("client", "provider")


@admin.register(Offer)
class OfferAdmin(admin.ModelAdmin):
	list_display = ("id", "request", "provider", "price", "status", "created_at")
	list_filter = ("status",)
	search_fields = ("request__title", "provider__display_name", "provider__user__phone")
	list_select_related = ("request", "provider", "provider__user")


@admin.register(RequestStatusLog)
class RequestStatusLogAdmin(admin.ModelAdmin):
	list_display = ("id", "request", "actor", "from_status", "to_status", "created_at")
	list_filter = ("from_status", "to_status")
	search_fields = ("request__title", "actor__phone")
	list_select_related = ("request", "actor")


@admin.register(ServiceRequestAttachment)
class ServiceRequestAttachmentAdmin(admin.ModelAdmin):
	list_display = ("id", "request", "file_type", "created_at")
	list_filter = ("file_type",)
	search_fields = ("request__title", "request__client__phone")
	list_select_related = ("request", "request__client")
	readonly_fields = ("created_at",)


@admin.register(ServiceRequestDispatch)
class ServiceRequestDispatchAdmin(admin.ModelAdmin):
	list_display = (
		"id",
		"request",
		"dispatch_tier",
		"dispatch_status",
		"available_at",
		"dispatched_at",
		"dispatch_attempts",
		"updated_at",
	)
	list_filter = ("dispatch_tier", "dispatch_status")
	search_fields = ("request__title", "idempotency_key", "last_error")
	list_select_related = ("request",)
	readonly_fields = ("created_at", "updated_at")
