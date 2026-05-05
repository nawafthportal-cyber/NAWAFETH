from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models, transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.providers.models import ProviderProfile, SubCategory


class RequestType(models.TextChoices):
	NORMAL = "normal", "عادي"
	COMPETITIVE = "competitive", "تنافسي"
	URGENT = "urgent", "عاجل"


class RequestStatus(models.TextChoices):
	NEW = "new", "جديد"
	PROVIDER_ACCEPTED = "provider_accepted", "تم قبول الطلب"
	AWAITING_CLIENT_APPROVAL = "awaiting_client", "بانتظار اعتماد العميل"
	IN_PROGRESS = "in_progress", "تحت التنفيذ"
	COMPLETED = "completed", "مكتمل"
	CANCELLED = "cancelled", "ملغي"


# Backward compatibility for legacy status constants used in tests/older code.
RequestStatus.SENT = RequestStatus.NEW
RequestStatus.ACCEPTED = RequestStatus.PROVIDER_ACCEPTED


PRE_EXECUTION_REQUEST_STATUSES = (
	RequestStatus.NEW,
	RequestStatus.PROVIDER_ACCEPTED,
	RequestStatus.AWAITING_CLIENT_APPROVAL,
)


def request_status_group_value(raw_status: str) -> str:
	value = (raw_status or "").strip().lower()
	if value in {status.value for status in PRE_EXECUTION_REQUEST_STATUSES}:
		return "new"
	if value == RequestStatus.IN_PROGRESS:
		return "in_progress"
	if value == RequestStatus.COMPLETED:
		return "completed"
	if value in (RequestStatus.CANCELLED, "canceled"):
		return "cancelled"
	return "new"


def service_request_status_group(service_request) -> str:
	return request_status_group_value(getattr(service_request, "status", ""))


def service_request_status_label(service_request) -> str:
	status = (getattr(service_request, "status", "") or "").strip().lower()
	request_type = (getattr(service_request, "request_type", "") or "").strip().lower()
	has_provider = bool(getattr(service_request, "provider_id", None) or getattr(service_request, "provider", None))

	if status == RequestStatus.NEW:
		if request_type == RequestType.NORMAL and has_provider:
			return "بانتظار قبول المزود"
		if request_type == RequestType.COMPETITIVE and has_provider:
			return "بانتظار إرسال تفاصيل التنفيذ"
		return "جديد"
	if status == RequestStatus.PROVIDER_ACCEPTED:
		return "تم قبول الطلب"
	if status == RequestStatus.AWAITING_CLIENT_APPROVAL:
		return "بانتظار اعتماد العميل للتفاصيل"
	if status == RequestStatus.IN_PROGRESS:
		return "تحت التنفيذ"
	if status == RequestStatus.COMPLETED:
		return "مكتمل"
	if status in (RequestStatus.CANCELLED, "canceled"):
		return "ملغي"
	return "جديد"


def service_request_pre_execution_return_status(service_request) -> str:
	request_type = (getattr(service_request, "request_type", "") or "").strip().lower()
	has_provider = bool(getattr(service_request, "provider_id", None) or getattr(service_request, "provider", None))
	if request_type == RequestType.COMPETITIVE and has_provider:
		return RequestStatus.NEW
	if has_provider:
		return RequestStatus.PROVIDER_ACCEPTED
	return RequestStatus.NEW


def service_request_pending_input_stage(service_request, *, status_logs=None) -> str:
	status = (getattr(service_request, "status", "") or "").strip().lower()
	if status != RequestStatus.AWAITING_CLIENT_APPROVAL:
		return ""

	logs = status_logs
	if logs is None:
		prefetched = getattr(service_request, "_prefetched_objects_cache", {})
		cached_logs = prefetched.get("status_logs") if isinstance(prefetched, dict) else None
		if cached_logs is not None:
			logs = cached_logs
		else:
			try:
				logs = service_request.status_logs.only("to_status")
			except Exception:
				logs = []

	for log in logs or []:
		to_status = (getattr(log, "to_status", "") or "").strip().lower()
		if to_status == RequestStatus.IN_PROGRESS:
			return "progress_update"
	return "pre_execution"


def service_request_pending_input_return_status(service_request, *, status_logs=None) -> str:
	if service_request_pending_input_stage(service_request, status_logs=status_logs) == "progress_update":
		return RequestStatus.IN_PROGRESS
	return service_request_pre_execution_return_status(service_request)


class DispatchMode(models.TextChoices):
	ALL = "all", "الكل"
	NEAREST = "nearest", "الأقرب"


class DispatchTier(models.TextChoices):
	BASIC = "basic", "أساسية"
	RIYADI = "riyadi", "ريادية"
	PRO = "pro", "احترافية"


class DispatchStatus(models.TextChoices):
	PENDING = "pending", "معلّق"
	READY = "ready", "جاهز للإرسال"
	DISPATCHED = "dispatched", "تم الإرسال"
	FAILED = "failed", "فشل الإرسال"


class ServiceRequest(models.Model):
	client = models.ForeignKey(
		User,
		on_delete=models.CASCADE,
		related_name="requests",
	)

	provider = models.ForeignKey(
		ProviderProfile,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="assigned_requests",
	)

	subcategory = models.ForeignKey(SubCategory, on_delete=models.PROTECT)
	subcategories = models.ManyToManyField(
		SubCategory,
		blank=True,
		related_name="service_requests_multi",
	)

	title = models.CharField(max_length=50)
	description = models.TextField(max_length=500)

	request_type = models.CharField(
		max_length=20,
		choices=RequestType.choices,
	)
	dispatch_mode = models.CharField(
		max_length=20,
		choices=DispatchMode.choices,
		default=DispatchMode.ALL,
	)

	status = models.CharField(
		max_length=20,
		choices=RequestStatus.choices,
		default=RequestStatus.NEW,
	)

	city = models.CharField(max_length=100)
	request_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
	request_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
	is_urgent = models.BooleanField(default=False)

	created_at = models.DateTimeField(auto_now_add=True)
	expires_at = models.DateTimeField(null=True, blank=True)
	quote_deadline = models.DateField(null=True, blank=True)
	expected_delivery_at = models.DateTimeField(null=True, blank=True)
	estimated_service_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
	received_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
	remaining_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
	delivered_at = models.DateTimeField(null=True, blank=True)
	actual_service_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
	canceled_at = models.DateTimeField(null=True, blank=True)
	cancel_reason = models.CharField(max_length=255, blank=True)
	provider_inputs_approved = models.BooleanField(null=True, blank=True)
	provider_inputs_decided_at = models.DateTimeField(null=True, blank=True)
	provider_inputs_decision_note = models.CharField(max_length=255, blank=True)

	def accept(self, provider: ProviderProfile) -> None:
		if self.status != RequestStatus.NEW:
			raise ValidationError("لا يمكن قبول الطلب الآن")

		update_qs = ServiceRequest.objects.filter(pk=self.pk, status=RequestStatus.NEW).filter(
			models.Q(provider__isnull=True) | models.Q(provider=provider)
		)
		updated = update_qs.update(
			provider=provider,
			status=RequestStatus.PROVIDER_ACCEPTED,
			provider_inputs_approved=None,
			provider_inputs_decided_at=None,
			provider_inputs_decision_note="",
		)
		if not updated:
			self.refresh_from_db()
			raise ValidationError("لا يمكن قبول الطلب الآن")

		self.provider = provider
		self.status = RequestStatus.PROVIDER_ACCEPTED
		self.provider_inputs_approved = None
		self.provider_inputs_decided_at = None
		self.provider_inputs_decision_note = ""

	def start(self) -> None:
		if self.status not in (*PRE_EXECUTION_REQUEST_STATUSES, RequestStatus.IN_PROGRESS):
			raise ValidationError("لا يمكن بدء التنفيذ في هذه الحالة")
		self.status = RequestStatus.IN_PROGRESS
		self.save(update_fields=["status"])

	def complete(self) -> None:
		if self.status != RequestStatus.IN_PROGRESS:
			raise ValidationError("لا يمكن الإكمال في هذه الحالة")
		self.status = RequestStatus.COMPLETED
		self.save(update_fields=["status"])

	def cancel(self, *, allowed_statuses: list[str] | None = None) -> None:
		"""Cancel a request. ``allowed_statuses`` lets the service layer
		restrict which statuses the caller may cancel from."""
		if allowed_statuses is None:
			allowed_statuses = [*PRE_EXECUTION_REQUEST_STATUSES, RequestStatus.IN_PROGRESS]
		if self.status not in allowed_statuses:
			raise ValidationError("لا يمكن إلغاء الطلب في هذه الحالة")
		clear_provider_state = self.status in PRE_EXECUTION_REQUEST_STATUSES
		self.status = RequestStatus.CANCELLED
		update_fields = ["status"]
		if clear_provider_state:
			self.provider = None
			self.expected_delivery_at = None
			self.estimated_service_amount = None
			self.received_amount = None
			self.remaining_amount = None
			self.provider_inputs_approved = None
			self.provider_inputs_decided_at = None
			self.provider_inputs_decision_note = ""
			update_fields.extend(
				[
					"provider",
					"expected_delivery_at",
					"estimated_service_amount",
					"received_amount",
					"remaining_amount",
					"provider_inputs_approved",
					"provider_inputs_decided_at",
					"provider_inputs_decision_note",
				]
			)
		self.save(update_fields=update_fields)

	def release_to_pool(self) -> None:
		if self.status not in PRE_EXECUTION_REQUEST_STATUSES:
			raise ValidationError("لا يمكن إعادة طرح الطلب في هذه الحالة")

		self.provider = None
		self.status = RequestStatus.NEW
		self.expected_delivery_at = None
		self.estimated_service_amount = None
		self.received_amount = None
		self.remaining_amount = None
		self.provider_inputs_approved = None
		self.provider_inputs_decided_at = None
		self.provider_inputs_decision_note = ""
		self.canceled_at = None
		self.cancel_reason = ""
		self.save(
			update_fields=[
				"provider",
				"status",
				"expected_delivery_at",
				"estimated_service_amount",
				"received_amount",
				"remaining_amount",
				"provider_inputs_approved",
				"provider_inputs_decided_at",
				"provider_inputs_decision_note",
				"canceled_at",
				"cancel_reason",
			]
		)

	def reopen(self) -> None:
		if self.status != RequestStatus.CANCELLED:
			raise ValidationError("لا يمكن إعادة فتح الطلب في هذه الحالة")
		self.status = RequestStatus.NEW
		self.provider = None
		self.canceled_at = None
		self.cancel_reason = ""
		self.save(update_fields=["status", "provider", "canceled_at", "cancel_reason"])

	def selected_subcategory_ids(self) -> list[int]:
		prefetched = getattr(self, "_prefetched_objects_cache", {})
		cached = prefetched.get("subcategories") if isinstance(prefetched, dict) else None
		if cached is not None:
			ids = [obj.id for obj in cached if getattr(obj, "id", None) is not None]
		else:
			ids = list(self.subcategories.values_list("id", flat=True))
		if not ids and self.subcategory_id:
			ids = [self.subcategory_id]
		return ids

	def __str__(self) -> str:
		return f"{self.title} ({self.get_status_display()})"


class OfferStatus(models.TextChoices):
	PENDING = "pending", "بانتظار"
	SELECTED = "selected", "مختار"
	REJECTED = "rejected", "مرفوض"


class Offer(models.Model):
	request = models.ForeignKey(
		ServiceRequest,
		on_delete=models.CASCADE,
		related_name="offers",
	)
	provider = models.ForeignKey(
		ProviderProfile,
		on_delete=models.CASCADE,
		related_name="offers",
	)

	price = models.DecimalField(max_digits=10, decimal_places=2)
	duration_days = models.PositiveIntegerField()
	note = models.TextField(max_length=500, blank=True)

	status = models.CharField(
		max_length=20,
		choices=OfferStatus.choices,
		default=OfferStatus.PENDING,
	)

	created_at = models.DateTimeField(auto_now_add=True)

	class Meta:
		unique_together = ("request", "provider")


class RequestStatusLog(models.Model):
	request = models.ForeignKey(
		"ServiceRequest",
		on_delete=models.CASCADE,
		related_name="status_logs",
	)
	actor = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
	)
	from_status = models.CharField(max_length=20)
	to_status = models.CharField(max_length=20)
	note = models.CharField(max_length=255, blank=True)
	created_at = models.DateTimeField(auto_now_add=True)

	class Meta:
		ordering = ("-id",)

	def __str__(self) -> str:
		return f"#{self.request_id}: {self.from_status} -> {self.to_status}"


class ServiceRequestAttachment(models.Model):
	# Source/role of the attachment so the client UI can group/label them
	SOURCE_CLIENT = "client"
	SOURCE_PROVIDER_PROGRESS = "provider_progress"
	SOURCE_PROVIDER_COMPLETION = "provider_completion"
	SOURCE_CHOICES = (
		(SOURCE_CLIENT, "Client"),
		(SOURCE_PROVIDER_PROGRESS, "Provider progress update"),
		(SOURCE_PROVIDER_COMPLETION, "Provider completion"),
	)

	request = models.ForeignKey(
		ServiceRequest,
		on_delete=models.CASCADE,
		related_name="attachments",
	)
	# When the attachment was uploaded as part of a status/progress update,
	# we link it to the corresponding RequestStatusLog so the client can see
	# files inline with the workflow timeline entry.
	status_log = models.ForeignKey(
		"RequestStatusLog",
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="attachments",
	)
	source = models.CharField(
		max_length=24,
		choices=SOURCE_CHOICES,
		default=SOURCE_CLIENT,
		db_index=True,
	)
	file = models.FileField(upload_to="requests/attachments/%Y/%m/%d/")
	file_type = models.CharField(max_length=20)  # image, video, audio, document
	created_at = models.DateTimeField(auto_now_add=True)

	def __str__(self):
		return f"Attachment {self.id} for Request #{self.request_id}"


class ServiceRequestDispatch(models.Model):
	request = models.ForeignKey(
		ServiceRequest,
		on_delete=models.CASCADE,
		related_name="dispatch_windows",
	)
	dispatch_tier = models.CharField(max_length=20, choices=DispatchTier.choices)
	available_at = models.DateTimeField(db_index=True)
	dispatch_status = models.CharField(
		max_length=20,
		choices=DispatchStatus.choices,
		default=DispatchStatus.PENDING,
		db_index=True,
	)
	dispatched_at = models.DateTimeField(null=True, blank=True)
	dispatch_attempts = models.PositiveSmallIntegerField(default=0)
	last_error = models.CharField(max_length=255, blank=True)
	idempotency_key = models.CharField(max_length=120, unique=True)
	created_at = models.DateTimeField(auto_now_add=True)
	updated_at = models.DateTimeField(auto_now=True)

	class Meta:
		constraints = [
			models.UniqueConstraint(
				fields=["request", "dispatch_tier"],
				name="uniq_dispatch_window_request_tier",
			),
		]
		indexes = [
			models.Index(fields=["dispatch_tier", "dispatch_status", "available_at"]),
			models.Index(fields=["request", "dispatch_status"]),
		]

	def __str__(self) -> str:
		return f"dispatch#{self.id} req={self.request_id} tier={self.dispatch_tier} status={self.dispatch_status}"
