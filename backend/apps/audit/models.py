from __future__ import annotations

from django.conf import settings
from django.db import models


class AuditAction(models.TextChoices):
	INVOICE_CREATED = "invoice_created", "إنشاء فاتورة"
	INVOICE_PAID = "invoice_paid", "دفع فاتورة"
	SUBSCRIPTION_STARTED = "subscription_started", "بدء اشتراك"
	SUBSCRIPTION_ACTIVE = "subscription_active", "تفعيل اشتراك"
	SUBSCRIPTION_REQUEST_ASSIGNED = "subscription_request_assigned", "إسناد طلب اشتراك"
	SUBSCRIPTION_REQUEST_STATUS_CHANGED = "subscription_request_status_changed", "تغيير حالة طلب اشتراك"
	SUBSCRIPTION_REQUEST_NOTE_ADDED = "subscription_request_note_added", "إضافة ملاحظة طلب اشتراك"
	SUBSCRIPTION_ACCOUNT_NOTE_ADDED = "subscription_account_note_added", "إضافة ملاحظة حساب اشتراك"
	SUBSCRIPTION_ACCOUNT_RENEW_REQUESTED = "subscription_account_renew_requested", "طلب تجديد اشتراك"
	SUBSCRIPTION_ACCOUNT_UPGRADE_REQUESTED = "subscription_account_upgrade_requested", "طلب ترقية اشتراك"
	SUBSCRIPTION_ACCOUNT_CANCELLED = "subscription_account_cancelled", "إلغاء اشتراك"
	SUBSCRIPTION_PAYMENT_CHECKOUT_OPENED = "subscription_payment_checkout_opened", "فتح شاشة دفع اشتراك"
	SUBSCRIPTION_PAYMENT_COMPLETED = "subscription_payment_completed", "إتمام دفع اشتراك"

	VERIFY_REQUEST_CREATED = "verify_request_created", "طلب توثيق"
	VERIFY_REQUEST_APPROVED = "verify_request_approved", "اعتماد توثيق"
	VERIFY_REQUEST_REJECTED = "verify_request_rejected", "رفض توثيق"

	PROMO_REQUEST_CREATED = "promo_request_created", "طلب إعلان"
	PROMO_REQUEST_QUOTED = "promo_request_quoted", "تسعير إعلان"
	PROMO_REQUEST_ACTIVE = "promo_request_active", "تفعيل إعلان"

	EXTRA_PURCHASE_CREATED = "extra_purchase_created", "شراء إضافة"
	EXTRA_PURCHASE_ACTIVE = "extra_purchase_active", "تفعيل إضافة"

	ACCESS_PROFILE_UPDATED = "access_profile_updated", "تحديث صلاحيات تشغيل"
	ACCESS_PROFILE_CREATED = "access_profile_created", "إنشاء صلاحيات تشغيل"
	ACCESS_PROFILE_REVOKED = "access_profile_revoked", "سحب صلاحيات تشغيل"
	ACCESS_PROFILE_UNREVOKED = "access_profile_unrevoked", "إلغاء سحب صلاحيات تشغيل"
	CONTENT_BLOCK_UPDATED = "content_block_updated", "تحديث بلوك محتوى"
	CONTENT_DOCUMENT_UPLOADED = "content_document_uploaded", "رفع مستند قانوني"
	CONTENT_LINKS_UPDATED = "content_links_updated", "تحديث روابط المنصة"
	REVIEW_MODERATED = "review_moderated", "تعديل حالة مراجعة"
	REVIEW_RESPONSE_ADDED = "review_response_added", "إضافة رد إداري على مراجعة"

	LOGIN_OTP_SENT = "login_otp_sent", "إرسال OTP"
	LOGIN_OTP_VERIFIED = "login_otp_verified", "تأكيد OTP"


class AuditLog(models.Model):
	actor = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="audit_logs",
	)

	action = models.CharField(max_length=60, choices=AuditAction.choices)

	reference_type = models.CharField(max_length=60, blank=True)
	reference_id = models.CharField(max_length=60, blank=True)

	ip_address = models.GenericIPAddressField(null=True, blank=True)
	user_agent = models.CharField(max_length=255, blank=True)

	extra = models.JSONField(default=dict, blank=True)

	created_at = models.DateTimeField(auto_now_add=True)

	class Meta:
		ordering = ["-id"]
		indexes = [
			models.Index(fields=["action"]),
			models.Index(fields=["reference_type", "reference_id"]),
			models.Index(fields=["created_at"]),
		]

	def __str__(self):
		return f"{self.action} - {self.reference_type}:{self.reference_id}"

# Create your models here.
