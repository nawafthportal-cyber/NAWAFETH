from django.contrib import admin

from .models import Review, ReviewModerationStatus


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
	list_display = (
		"id",
		"request",
		"provider",
		"client",
		"rating",
		"moderation_status",
		"moderated_by",
		"created_at",
	)
	list_filter = ("rating", "moderation_status")
	search_fields = ("client__phone", "provider__display_name", "comment", "moderation_note")
	ordering = ("-id",)
	list_select_related = ("request", "provider", "provider__user", "client", "moderated_by")
	readonly_fields = (
		"created_at",
		"provider_liked_at",
		"provider_reply_at",
		"provider_reply_edited_at",
		"moderated_at",
		"management_reply_at",
	)
	fieldsets = (
		("التقييم الأساسي", {
			"fields": (
				"request",
				"provider",
				"client",
				"rating",
				("response_speed", "cost_value"),
				("quality", "credibility", "on_time"),
				"comment",
				"created_at",
			),
		}),
		("رد المختص", {
			"fields": ("provider_liked", "provider_liked_at", "provider_reply", "provider_reply_at", "provider_reply_edited_at"),
			"classes": ("collapse",),
		}),
		("رد الإدارة", {
			"fields": ("management_reply", "management_reply_at", "management_reply_by"),
			"classes": ("collapse",),
		}),
		("الاعتدال", {
			"fields": ("moderation_status", "moderation_note", "moderated_at", "moderated_by"),
		}),
	)
