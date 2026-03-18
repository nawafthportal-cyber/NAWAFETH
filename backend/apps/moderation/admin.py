from django.contrib import admin

from .models import ModerationActionLog, ModerationCase, ModerationDecision


@admin.register(ModerationCase)
class ModerationCaseAdmin(admin.ModelAdmin):
    list_display = ("code", "status", "severity", "source_label", "reporter", "assigned_to", "created_at")
    list_filter = ("status", "severity", "source_app", "source_model")
    search_fields = ("code", "source_object_id", "source_label", "reason", "reporter__phone")
    ordering = ("-id",)


@admin.register(ModerationActionLog)
class ModerationActionLogAdmin(admin.ModelAdmin):
    list_display = ("case", "action_type", "created_by", "created_at")
    list_filter = ("action_type",)
    search_fields = ("case__code", "note")
    ordering = ("-id",)


@admin.register(ModerationDecision)
class ModerationDecisionAdmin(admin.ModelAdmin):
    list_display = ("case", "decision_code", "is_final", "applied_by", "applied_at")
    list_filter = ("decision_code", "is_final")
    search_fields = ("case__code", "note")
    ordering = ("-id",)
