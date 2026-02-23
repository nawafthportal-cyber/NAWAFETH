from django.conf import settings
from datetime import timedelta

from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from apps.marketplace.models import ServiceRequest, RequestStatus
from apps.providers.models import ProviderProfile


class Review(models.Model):
	request = models.OneToOneField(
		ServiceRequest,
		on_delete=models.CASCADE,
		related_name="review",
	)
	provider = models.ForeignKey(
		ProviderProfile,
		on_delete=models.CASCADE,
		related_name="reviews",
	)
	client = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.CASCADE,
		related_name="reviews_made",
	)

	rating = models.PositiveSmallIntegerField(
		validators=[MinValueValidator(1), MaxValueValidator(5)]
	)

	# تفصيل التقييم (اختياري حالياً لضمان التوافق)
	response_speed = models.PositiveSmallIntegerField(
		null=True,
		blank=True,
		validators=[MinValueValidator(1), MaxValueValidator(5)],
	)
	cost_value = models.PositiveSmallIntegerField(
		null=True,
		blank=True,
		validators=[MinValueValidator(1), MaxValueValidator(5)],
	)
	quality = models.PositiveSmallIntegerField(
		null=True,
		blank=True,
		validators=[MinValueValidator(1), MaxValueValidator(5)],
	)
	credibility = models.PositiveSmallIntegerField(
		null=True,
		blank=True,
		validators=[MinValueValidator(1), MaxValueValidator(5)],
	)
	on_time = models.PositiveSmallIntegerField(
		null=True,
		blank=True,
		validators=[MinValueValidator(1), MaxValueValidator(5)],
	)
	comment = models.CharField(max_length=500, blank=True)

	created_at = models.DateTimeField(default=timezone.now)

	class Meta:
		ordering = ("-id",)
		indexes = [
			models.Index(fields=["provider", "created_at"]),
		]

	def clean(self):
		# قواعد قوية (تُستخدم عند full_clean أو في serializer)
		if self.rating < 1 or self.rating > 5:
			raise ValidationError("rating_out_of_range")

		if self.request_id:
			status = self.request.status
			if status == RequestStatus.COMPLETED:
				pass
			elif status == RequestStatus.CANCELLED:
				pass
			elif status == RequestStatus.IN_PROGRESS:
				deadline = getattr(self.request, "expected_delivery_at", None)
				if not deadline or timezone.now() < (deadline + timedelta(hours=48)):
					raise ValidationError("request_not_reviewable_yet")
			else:
				raise ValidationError("request_not_reviewable")
			if self.client_id and self.request.client_id != self.client_id:
				raise ValidationError("client_mismatch")
			if self.provider_id and self.request.provider_id != self.provider_id:
				raise ValidationError("provider_mismatch")

	def __str__(self):
		return f"Review #{self.id} req={self.request_id} rating={self.rating}"
