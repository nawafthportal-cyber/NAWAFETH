from django.contrib import admin, messages

from apps.audit.models import AuditAction
from apps.audit.services import log_action

from .models import Invoice, InvoiceLineItem, PaymentAttempt, WebhookEvent, TRUSTED_PAYMENT_REFERENCE_TYPES


class InvoiceLineItemInline(admin.TabularInline):
    model = InvoiceLineItem
    extra = 0
    fields = ("item_code", "title", "amount", "sort_order", "created_at")
    readonly_fields = ("created_at",)


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    list_display = ("code", "user", "status", "subtotal", "vat_amount", "total", "currency", "paid_at", "created_at")
    list_filter = ("status", "currency")
    search_fields = ("code", "user__phone", "reference_type", "reference_id")
    ordering = ("-id",)
    readonly_payment_fields = (
        "status",
        "paid_at",
        "cancelled_at",
        "payment_confirmed",
        "payment_confirmed_at",
        "payment_provider",
        "payment_reference",
        "payment_event_id",
        "payment_amount",
        "payment_currency",
    )
    inlines = [InvoiceLineItemInline]

    def get_readonly_fields(self, request, obj=None):
        readonly = list(super().get_readonly_fields(request, obj))
        if obj and obj.reference_type in TRUSTED_PAYMENT_REFERENCE_TYPES:
            readonly.extend(self.readonly_payment_fields)
        return tuple(dict.fromkeys(readonly))

    def save_model(self, request, obj, form, change):
        if change and obj.pk:
            original = Invoice.objects.get(pk=obj.pk)
            if original.reference_type in TRUSTED_PAYMENT_REFERENCE_TYPES:
                changed_fields = [
                    field_name
                    for field_name in self.readonly_payment_fields
                    if getattr(original, field_name) != getattr(obj, field_name)
                ]
                if changed_fields:
                    log_action(
                        actor=request.user,
                        action=AuditAction.INVOICE_STATUS_CHANGE_BLOCKED,
                        reference_type="invoice",
                        reference_id=original.code or str(original.pk),
                        request=request,
                        extra={
                            "reference_type": original.reference_type,
                            "reference_id": original.reference_id,
                            "blocked_fields": changed_fields,
                            "channel": "django_admin",
                        },
                    )
                    self.message_user(
                        request,
                        "لا يمكن تعديل حالة أو بيانات اعتماد الدفع لفواتير الاشتراك/التوثيق من Admin. استخدم مسار الدفع الموثوق فقط.",
                        level=messages.ERROR,
                    )
                    return
        super().save_model(request, obj, form, change)


@admin.register(PaymentAttempt)
class PaymentAttemptAdmin(admin.ModelAdmin):
    list_display = ("id", "invoice", "provider", "status", "amount", "currency", "created_at")
    list_filter = ("provider", "status", "currency")
    search_fields = ("provider_reference", "idempotency_key", "invoice__code")
    ordering = ("-created_at",)


@admin.register(InvoiceLineItem)
class InvoiceLineItemAdmin(admin.ModelAdmin):
    list_display = ("id", "invoice", "item_code", "title", "amount", "sort_order", "created_at")
    list_filter = ("invoice__status",)
    search_fields = ("invoice__code", "item_code", "title")
    ordering = ("invoice", "sort_order", "id")
    readonly_fields = ("created_at",)
    list_select_related = ("invoice",)


@admin.register(WebhookEvent)
class WebhookEventAdmin(admin.ModelAdmin):
    list_display = ("provider", "event_id", "received_at")
    list_filter = ("provider",)
    search_fields = ("event_id",)
    ordering = ("-received_at",)
