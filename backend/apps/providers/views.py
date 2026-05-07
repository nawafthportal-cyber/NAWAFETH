import logging

from django.utils.decorators import method_decorator
from django.views.decorators.cache import cache_page
from rest_framework import generics, permissions, status
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db.models import Avg, BooleanField, Count, Exists, F, Max, OuterRef, Prefetch, Q, Value
from django.db.models.functions import Coalesce
from django.db import transaction

logger = logging.getLogger(__name__)

from apps.accounts.models import User

from apps.accounts.models import UserRole
from apps.accounts.permissions import IsAtLeastClient, IsAtLeastPhoneOnly, IsAtLeastProvider
from apps.accounts.role_context import get_active_role
from .cache import get_cached_public_category_list_payload
from .eligibility import HasProviderProfile
from apps.reviews.models import ReviewModerationStatus
from apps.reviews.services import calculate_provider_rating

from .models import (
	Category,
	ContentShareChannel,
	ContentShareContentType,
	ProviderContentComment,
	ProviderContentCommentLike,
	ProviderCoverImage,
	ProviderFollow,
	ProviderLike,
	ProviderContentShare,
	ProviderCategory,
	ProviderPortfolioItem,
	ProviderPortfolioLike,
	ProviderPortfolioSave,
	ProviderPortfolioVisibilityBlock,
	ProviderProfile,
	ProviderService,
	ProviderSpotlightItem,
	ProviderSpotlightLike,
	ProviderSpotlightSave,
	ProviderSpotlightVisibilityBlock,
	ProviderVisibilityBlock,
	SaudiRegion,
	SubCategory,
	sync_provider_accepts_urgent_flag,
)
from .serializers import (
	BlockedPortfolioSerializer,
    BlockedProviderSerializer,
    BlockedSpotlightSerializer,
	CategorySerializer,
	MyProviderSubcategoriesSerializer,
	ProviderFollowerSerializer,
	ProviderCoverImageSerializer,
	ProviderCoverImageUploadSerializer,
	SaudiRegionSerializer,
	SubCategoryWithCategorySerializer,
	ProviderServicePublicDetailSerializer,
	ProviderServicePublicSerializer,
	ProviderServiceSerializer,
	ProviderPortfolioItemCreateSerializer,
	ProviderPortfolioItemSerializer,
	ProviderPortfolioItemUpdateSerializer,
	ProviderProfileSerializer,
	ProviderProfileMeSerializer,
	ProviderPublicSerializer,
	SpotlightCommentCreateSerializer,
	SpotlightCommentSerializer,
	ProviderSpotlightItemCreateSerializer,
	ProviderSpotlightItemSerializer,
	UserPublicSerializer,
)
from .location_formatter import provider_city_query_values
from .media_thumbnails import ensure_media_thumbnail
from apps.subscriptions.capabilities import banner_image_limit_for_user, spotlight_quota_for_user


def _dedup_follow_rows(rows: list[ProviderFollow]) -> list[ProviderFollow]:
	"""Return one follow row per user/provider pair, preferring provider-mode rows."""
	ordered_rows = sorted(
		rows,
		key=lambda row: (
			int(row.user_id or 0),
			int(row.provider_id or 0),
			0 if str(getattr(row, "role_context", "") or "").strip().lower() == "provider" else 1,
			-float(getattr(getattr(row, "created_at", None), "timestamp", lambda: 0)() or 0),
			-int(getattr(row, "id", 0) or 0),
		),
	)
	seen: set[tuple[int, int]] = set()
	deduped: list[ProviderFollow] = []
	for row in ordered_rows:
		key = (int(row.user_id or 0), int(row.provider_id or 0))
		if key in seen:
			continue
		seen.add(key)
		deduped.append(row)
	return deduped


def _dedup_follow_ids(qs):
	"""Return follow-row ids with cross-role duplicates collapsed."""
	return [
		row.id
		for row in _dedup_follow_rows(list(qs))
	]


def _handle_storage_error(exc):
	"""Convert storage/S3 exceptions into a user-friendly DRF Response."""
	msg = str(exc)
	if "403" in msg or "Forbidden" in msg:
		logger.error("Storage access denied (403). Check R2/S3 credentials: %s", msg)
		return Response(
			{"detail": "فشل رفع الملف: صلاحيات التخزين السحابي غير كافية. يرجى التواصل مع الدعم الفني."},
			status=status.HTTP_502_BAD_GATEWAY,
		)
	if "NoSuchBucket" in msg or "bucket" in msg.lower():
		logger.error("Storage bucket not found: %s", msg)
		return Response(
			{"detail": "فشل رفع الملف: مشكلة في إعداد التخزين السحابي."},
			status=status.HTTP_502_BAD_GATEWAY,
		)
	logger.error("Storage error during upload: %s", msg)
	return Response(
		{"detail": "فشل رفع الملف. يرجى المحاولة لاحقاً."},
		status=status.HTTP_502_BAD_GATEWAY,
	)


def _is_storage_error(exc):
	"""Check if an exception originates from the file storage backend."""
	try:
		from botocore.exceptions import ClientError, BotoCoreError
		if isinstance(exc, (ClientError, BotoCoreError)):
			return True
	except ImportError:
		pass
	from django.core.exceptions import ImproperlyConfigured, SuspiciousFileOperation
	if isinstance(exc, (ImproperlyConfigured, SuspiciousFileOperation, OSError)):
		return True
	# Catch generic exceptions that contain storage-related messages
	msg = str(exc).lower()
	if any(kw in msg for kw in ("s3", "r2", "boto", "storage", "bucket", "403", "forbidden")):
		return True
	return False


def _with_rating_annotations(qs):
	return qs.annotate(
		computed_rating_avg=Avg(
			"reviews__rating",
			filter=Q(reviews__moderation_status=ReviewModerationStatus.APPROVED),
		),
		computed_rating_count=Count(
			"reviews",
			filter=Q(reviews__moderation_status=ReviewModerationStatus.APPROVED),
			distinct=True,
		),
	)


def _active_role_or_default(request, fallback: str = "client"):
	return get_active_role(request, fallback=fallback) if request is not None else fallback


def _blocked_provider_ids_queryset(user, role_context: str):
	return ProviderVisibilityBlock.objects.filter(user=user, role_context=role_context).values("provider_id")


def _blocked_spotlight_ids_queryset(user, role_context: str):
	return ProviderSpotlightVisibilityBlock.objects.filter(user=user, role_context=role_context).values("spotlight_item_id")


def _blocked_portfolio_ids_queryset(user, role_context: str):
	return ProviderPortfolioVisibilityBlock.objects.filter(user=user, role_context=role_context).values("portfolio_item_id")


def _filter_provider_queryset_for_user(qs, request):
	user = getattr(request, "user", None)
	if user and user.is_authenticated:
		role = _active_role_or_default(request)
		qs = qs.exclude(id__in=_blocked_provider_ids_queryset(user, role))
	return qs


def _filter_portfolio_queryset_for_user(qs, request):
	user = getattr(request, "user", None)
	if user and user.is_authenticated:
		role = _active_role_or_default(request)
		qs = qs.exclude(provider_id__in=_blocked_provider_ids_queryset(user, role))
		qs = qs.exclude(id__in=_blocked_portfolio_ids_queryset(user, role))
	return qs


def _filter_spotlight_queryset_for_user(qs, request):
	user = getattr(request, "user", None)
	if user and user.is_authenticated:
		role = _active_role_or_default(request)
		qs = qs.exclude(provider_id__in=_blocked_provider_ids_queryset(user, role))
		qs = qs.exclude(id__in=_blocked_spotlight_ids_queryset(user, role))
	return qs


class MyProviderProfileView(generics.RetrieveUpdateAPIView):
	"""Get/update the current user's provider profile."""

	serializer_class = ProviderProfileMeSerializer
	permission_classes = [IsAtLeastClient]

	def get_object(self):
		provider_profile = (
			_with_rating_annotations(
				ProviderProfile.objects.select_related("user")
				.prefetch_related("providercategory_set__subcategory__category", "cover_gallery")
				.filter(user=self.request.user)
			)
			.first()
		)
		if not provider_profile:
			raise NotFound("provider_profile_not_found")
		return provider_profile

	def update(self, request, *args, **kwargs):
		try:
			return super().update(request, *args, **kwargs)
		except Exception as exc:
			if _is_storage_error(exc):
				return _handle_storage_error(exc)
			raise



def _annotate_content_comment_queryset(queryset, request):
	queryset = queryset.annotate(likes_count=Count("likes", distinct=True))
	user = getattr(request, "user", None)
	if user and getattr(user, "is_authenticated", False):
		role = get_active_role(request)
		liked_qs = ProviderContentCommentLike.objects.filter(
			user=user,
			comment_id=OuterRef("pk"),
			role_context=role,
		)
		return queryset.annotate(is_liked=Exists(liked_qs))
	return queryset.annotate(is_liked=Value(False, output_field=BooleanField()))


def _create_content_comment_report_ticket(*, request, comment, reported_kind: str, label: str, content_ref: str):
	from apps.moderation.integrations import sync_support_ticket_case
	from apps.support.models import SupportPriority, SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketType

	if request.user.id == comment.user_id:
		raise ValidationError("لا يمكنك الإبلاغ عن تعليقك الخاص.")

	reason = str(request.data.get("reason") or "").strip()
	details = str(request.data.get("details") or request.data.get("description") or request.data.get("text") or "").strip()
	reported_label = str(request.data.get("reported_label") or getattr(comment, "body", "") or "").strip()
	if not reason and details:
		reason = "أخرى"
	if not reason:
		raise ValidationError({"detail": "reason مطلوب"})

	prefix = f"بلاغ تعليق على {label} (Comment#{comment.id}) {content_ref}".strip()
	full = f"{prefix} - السبب: {reason}"
	if details:
		full += f" - التفاصيل: {details}"
	if reported_label:
		full += f" - نص التعليق: {reported_label[:120]}"
	full = full.strip()[:300]

	assigned_team = SupportTeam.objects.filter(code__iexact="content", is_active=True).first()
	ticket = SupportTicket.objects.create(
		requester=request.user,
		ticket_type=SupportTicketType.COMPLAINT,
		priority=SupportPriority.NORMAL,
		entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
		description=full,
		reported_kind=reported_kind,
		reported_object_id=str(comment.id),
		reported_user_id=comment.user_id,
		assigned_team=assigned_team,
	)
	try:
		sync_support_ticket_case(ticket=ticket, by_user=request.user, request=request, note=f"{reported_kind}_report")
	except Exception:
		pass
	return ticket


def _provider_cover_gallery_queryset(provider):
	return provider.cover_gallery.order_by("sort_order", "id")


def _ensure_cover_gallery_seeded(provider):
	if getattr(provider, "cover_image", None):
		provider.seed_cover_gallery_from_legacy_cover()


def _provider_cover_gallery_payload(provider, *, request):
	items = list(_provider_cover_gallery_queryset(provider))
	limit = max(0, int(banner_image_limit_for_user(getattr(request, "user", None)) or 0))
	count = len(items)
	serializer = ProviderCoverImageSerializer(items, many=True, context={"request": request})
	return {
		"limit": limit,
		"count": count,
		"remaining": max(limit - count, 0),
		"results": serializer.data,
	}


def _reindex_provider_cover_gallery(provider):
	for index, item in enumerate(_provider_cover_gallery_queryset(provider)):
		if int(getattr(item, "sort_order", 0) or 0) == index:
			continue
		item.sort_order = index
		item.save(update_fields=["sort_order"])


class MyProviderCoverGalleryView(APIView):
	permission_classes = [IsAtLeastProvider]

	def _provider(self, request):
		provider = getattr(request.user, "provider_profile", None)
		if not provider:
			raise NotFound("provider_profile_not_found")
		return provider

	def get(self, request):
		provider = self._provider(request)
		_ensure_cover_gallery_seeded(provider)
		return Response(_provider_cover_gallery_payload(provider, request=request), status=status.HTTP_200_OK)

	def post(self, request):
		provider = self._provider(request)
		limit = max(0, int(banner_image_limit_for_user(request.user) or 0))
		if limit <= 0:
			return Response(
				{
					"detail": "رفع خلفيات الملف غير متاح قبل تفعيل الاشتراك المناسب.",
					"error_code": "cover_gallery_unavailable",
					"cover_images_limit": limit,
				},
				status=status.HTTP_400_BAD_REQUEST,
			)

		serializer = ProviderCoverImageUploadSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		_ensure_cover_gallery_seeded(provider)
		current_count = _provider_cover_gallery_queryset(provider).count()
		if current_count >= limit:
			return Response(
				{
					"detail": f"بلغت الحد الأقصى لخلفيات الملف في باقتك الحالية ({limit}).",
					"error_code": "cover_gallery_limit_exceeded",
					"cover_images_limit": limit,
					"current_count": current_count,
				},
				status=status.HTTP_400_BAD_REQUEST,
			)

		next_sort = (
			_provider_cover_gallery_queryset(provider)
			.aggregate(max_sort=Max("sort_order"))
			.get("max_sort")
		)
		item = ProviderCoverImage.objects.create(
			provider=provider,
			image=serializer.validated_data["image"],
			sort_order=int(next_sort or -1) + 1,
		)
		if not getattr(provider, "cover_image", None):
			provider.cover_image = item.image
			provider.save(update_fields=["cover_image", "updated_at"])
		return Response(
			{
				"item": ProviderCoverImageSerializer(item, context={"request": request}).data,
				**_provider_cover_gallery_payload(provider, request=request),
			},
			status=status.HTTP_201_CREATED,
		)


class MyProviderCoverImageDetailView(APIView):
	permission_classes = [IsAtLeastProvider]

	def delete(self, request, pk: int):
		provider = getattr(request.user, "provider_profile", None)
		if not provider:
			raise NotFound("provider_profile_not_found")
		item = generics.get_object_or_404(ProviderCoverImage, provider=provider, pk=pk)
		item.delete()
		_reindex_provider_cover_gallery(provider)
		provider.sync_cover_image_from_gallery(save=True)
		return Response(_provider_cover_gallery_payload(provider, request=request), status=status.HTTP_200_OK)


class MyProviderSubcategoriesView(APIView):
	"""Get/update the authenticated provider's service subcategories.

	Used by the mobile app to power provider inbox filtering.
	"""

	permission_classes = [IsAtLeastProvider]

	def get(self, request):
		provider = getattr(request.user, "provider_profile", None)
		if not provider:
			raise NotFound("provider_profile_not_found")

		rows = list(
			ProviderCategory.objects.filter(provider=provider)
			.select_related("subcategory")
			.order_by("subcategory__category__name", "subcategory__name", "id")
		)
		ids = [row.subcategory_id for row in rows]
		single_row_legacy_mode = len(rows) == 1
		settings = [
			{
				"subcategory_id": row.subcategory_id,
				"accepts_urgent": bool(row.accepts_urgent and getattr(row.subcategory, "allows_urgent_requests", False)),
				"requires_geo_scope": bool(
					getattr(row.subcategory, "requires_geo_scope", True)
					if single_row_legacy_mode
					else getattr(row, "requires_geo_scope", True)
				),
			}
			for row in rows
		]
		return Response({"subcategory_ids": ids, "subcategory_settings": settings}, status=status.HTTP_200_OK)

	def put(self, request):
		provider = getattr(request.user, "provider_profile", None)
		if not provider:
			raise NotFound("provider_profile_not_found")

		serializer = MyProviderSubcategoriesSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		ids = serializer.validated_data.get("subcategory_ids", [])
		settings = serializer.validated_data.get("subcategory_settings", [])

		with transaction.atomic():
			ProviderCategory.objects.filter(provider=provider).delete()
			if settings:
				ProviderCategory.objects.bulk_create(
					[
						ProviderCategory(
							provider=provider,
							subcategory_id=item["subcategory_id"],
							accepts_urgent=bool(item.get("accepts_urgent", False)),
							requires_geo_scope=bool(item.get("requires_geo_scope", True)),
						)
						for item in settings
					]
				)
			sync_provider_accepts_urgent_flag(provider)

		# Return updated ids (normalized)
		return Response({"subcategory_ids": ids, "subcategory_settings": settings}, status=status.HTTP_200_OK)


class MyProviderServicesListCreateView(generics.ListCreateAPIView):
	"""Provider-owned services (list + create)."""

	serializer_class = ProviderServiceSerializer
	permission_classes = [IsAtLeastProvider]

	def get_queryset(self):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			return ProviderService.objects.none()
		return (
			ProviderService.objects.filter(provider=pp)
			.select_related("provider", "subcategory", "subcategory__category")
			.order_by("-updated_at", "-id")
		)

	def perform_create(self, serializer):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			raise NotFound("provider_profile_not_found")
		serializer.save(provider=pp)


class MyProviderServiceDetailView(generics.RetrieveUpdateDestroyAPIView):
	"""Provider-owned single service (retrieve/update/delete)."""

	serializer_class = ProviderServiceSerializer
	permission_classes = [IsAtLeastProvider]

	def get_queryset(self):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			return ProviderService.objects.none()
		return ProviderService.objects.filter(provider=pp).select_related(
			"provider", "subcategory", "subcategory__category"
		)


class ProviderServicesPublicListView(generics.ListAPIView):
	"""Public list of active services for a provider."""

	serializer_class = ProviderServicePublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		return (
			ProviderService.objects.filter(provider_id=provider_id, is_active=True)
			.select_related("subcategory", "subcategory__category")
			.order_by("-updated_at", "-id")
		)


class ProviderServicePublicDetailView(generics.RetrieveAPIView):
	"""Public detail for one active provider service."""

	serializer_class = ProviderServicePublicDetailSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		return (
			ProviderService.objects.filter(is_active=True)
			.select_related("provider", "subcategory", "subcategory__category")
		)


class ReportProviderServiceView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		item = generics.get_object_or_404(
			ProviderService.objects.select_related("provider", "provider__user", "subcategory", "subcategory__category"),
			id=item_id,
			is_active=True,
		)
		if request.user.id == item.provider.user_id:
			return Response({"detail": "لا يمكنك الإبلاغ عن خدمتك الخاصة."}, status=status.HTTP_400_BAD_REQUEST)

		from apps.moderation.services import assign_case, create_case

		reason = str(request.data.get("reason") or "").strip()[:120] or "إبلاغ عن خدمة"
		details = str(request.data.get("details") or "").strip()[:500]
		case = create_case(
			reporter=request.user,
			payload={
				"reported_user": item.provider.user,
				"source_app": "providers",
				"source_model": "ProviderService",
				"source_object_id": str(item.id),
				"source_label": item.title or f"خدمة {item.provider.display_name}",
				"category": "service",
				"reason": reason,
				"details": details,
				"summary": f"بلاغ على خدمة {item.title or item.provider.display_name}"[:300],
				"severity": "normal",
				"snapshot": {
					"provider_id": item.provider_id,
					"provider_name": item.provider.display_name,
					"service_title": item.title,
					"service_description": item.description,
					"subcategory": getattr(getattr(item, "subcategory", None), "name", "") or "",
					"category_name": getattr(getattr(getattr(item, "subcategory", None), "category", None), "name", "") or "",
					"price_from": item.price_from,
					"price_to": item.price_to,
					"price_unit": item.price_unit,
				},
				"meta": {
					"surface": str(request.data.get("surface") or "mobile_web.service_detail"),
					"provider_id": item.provider_id,
					"service_id": item.id,
				},
			},
			request=request,
		)
		assign_case(
			case=case,
			assigned_team_code="content",
			assigned_team_name="المحتوى والمراجعات",
			note="بلاغ وارد من صفحة الخدمة",
			by_user=request.user,
			request=request,
		)
		return Response({"ok": True, "case_id": case.id, "case_code": case.code}, status=status.HTTP_201_CREATED)


class ReportProviderProfileView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		provider = generics.get_object_or_404(
			ProviderProfile.objects.select_related("user"),
			id=provider_id,
			user__is_active=True,
		)
		if request.user.id == provider.user_id:
			return Response({"detail": "لا يمكنك الإبلاغ عن ملفك الشخصي."}, status=status.HTTP_400_BAD_REQUEST)

		from apps.moderation.integrations import sync_support_ticket_case
		from apps.support.models import SupportPriority, SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketType

		reason = str(request.data.get("reason") or "").strip()[:120] or "إبلاغ عن مقدم خدمة"
		details = str(request.data.get("details") or "").strip()[:300]
		description = f"بلاغ على مقدم خدمة @{provider.display_name or provider.user.username or provider.user.phone} - السبب: {reason}"
		if details:
			description += f" - التفاصيل: {details}"
		description = description[:300]

		assigned_team = SupportTeam.objects.filter(code__iexact="support", is_active=True).first()
		ticket = SupportTicket.objects.create(
			requester=request.user,
			ticket_type=SupportTicketType.COMPLAINT,
			priority=SupportPriority.NORMAL,
			entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
			description=description,
			reported_kind="provider_profile",
			reported_object_id=str(provider.id),
			reported_user=provider.user,
			assigned_team=assigned_team,
		)
		try:
			sync_support_ticket_case(ticket=ticket, by_user=request.user, request=request, note="provider_profile_report")
		except Exception:
			pass
		return Response({"ok": True, "ticket_id": ticket.id, "ticket_code": ticket.code}, status=status.HTTP_201_CREATED)


class ProviderSubcategoriesPublicListView(generics.ListAPIView):
	"""Public list of a provider's selected service subcategories."""

	serializer_class = SubCategoryWithCategorySerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		return (
			SubCategory.objects.filter(
				is_active=True,
				providercategory__provider_id=provider_id,
			)
			.select_related("category")
			.distinct()
			.order_by("category_id", "name")
		)


class CategoryListView(generics.ListAPIView):
	queryset = Category.objects.filter(is_active=True).prefetch_related(
		Prefetch(
			"subcategories",
			queryset=SubCategory.objects.filter(is_active=True),
		)
	)
	serializer_class = CategorySerializer
	authentication_classes = []
	permission_classes = [permissions.AllowAny]

	def list(self, request, *args, **kwargs):
		def _build_payload():
			queryset = self.filter_queryset(self.get_queryset())
			serializer = self.get_serializer(queryset, many=True)
			return serializer.data

		return Response(get_cached_public_category_list_payload(_build_payload))


@method_decorator(cache_page(60 * 60 * 24), name="dispatch")  # 24 hours
class RegionCityCatalogView(generics.ListAPIView):
	queryset = SaudiRegion.objects.filter(is_active=True).prefetch_related("cities").order_by("sort_order", "id")
	serializer_class = SaudiRegionSerializer
	authentication_classes = []
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		return (
			SaudiRegion.objects.filter(is_active=True)
			.prefetch_related("cities")
			.order_by("sort_order", "id")
		)


class ProviderCreateView(generics.CreateAPIView):
	serializer_class = ProviderProfileSerializer
	# Provider registration is allowed only after full basic registration
	# (CLIENT or above), matching product permission matrix.
	permission_classes = [IsAtLeastClient]

	def perform_create(self, serializer):
		with transaction.atomic():
			profile = serializer.save(user=self.request.user)
			# Upgrade role to PROVIDER (level 4) after registering as provider
			user = self.request.user
			if not getattr(user, "is_staff", False) and getattr(user, "role_state", None) != UserRole.PROVIDER:
				user.role_state = UserRole.PROVIDER
				user.save(update_fields=["role_state"])
		return profile


class ProviderListView(generics.ListAPIView):
	"""Public provider list/search (visitor allowed)."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		from apps.marketplace.models import RequestStatus
		# Public list must include only real active provider accounts.
		qs = _with_rating_annotations(
			ProviderProfile.objects.select_related("user")
			.prefetch_related("providercategory_set__subcategory__category", "cover_gallery")
			.filter(
				user__is_active=True,
			)
			.annotate(
				# Keep parity with profile stats: count unique follower users,
				# not follow rows per role_context.
				followers_count=Count("followers__user", distinct=True),
				likes_count=Count("likes", distinct=True),
				completed_requests=Count(
					"assigned_requests",
					filter=Q(assigned_requests__status=RequestStatus.COMPLETED),
					distinct=True,
				),
			)
			.order_by("-id")
		)

		q = (self.request.query_params.get("q") or "").strip()
		city = (self.request.query_params.get("city") or "").strip()
		has_location = (self.request.query_params.get("has_location") or "").strip().lower()
		accepts_urgent = (self.request.query_params.get("accepts_urgent") or "").strip().lower()
		category_id = (self.request.query_params.get("category_id") or "").strip()
		subcategory_id = (self.request.query_params.get("subcategory_id") or "").strip()
		if q:
			qs = qs.filter(display_name__icontains=q)
		if city:
			city_values = provider_city_query_values(city)
			city_query = Q()
			for value in city_values:
				city_query |= Q(city__icontains=value)
			qs = qs.filter(city_query)
		if has_location in {"1", "true", "yes"}:
			qs = qs.exclude(lat__isnull=True).exclude(lng__isnull=True)
		urgent_only = accepts_urgent in {"1", "true", "yes"}

		# Optional service taxonomy filters via ProviderCategory
		if subcategory_id:
			try:
				sid = int(subcategory_id)
				filters = {"providercategory__subcategory_id": sid}
				if urgent_only:
					filters["providercategory__accepts_urgent"] = True
				qs = qs.filter(**filters)
			except ValueError:
				pass
		elif category_id:
			try:
				cid = int(category_id)
				sub_ids = list(
					SubCategory.objects.filter(category_id=cid, is_active=True).values_list("id", flat=True)
				)
				if sub_ids:
					filters = {"providercategory__subcategory_id__in": sub_ids}
					if urgent_only:
						filters["providercategory__accepts_urgent"] = True
					qs = qs.filter(**filters)
			except ValueError:
				pass
		elif urgent_only:
			qs = qs.filter(accepts_urgent=True)
		return _filter_provider_queryset_for_user(qs.distinct(), self.request)


class ProviderDetailView(generics.RetrieveAPIView):
	serializer_class = ProviderPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		from apps.marketplace.models import RequestStatus
		return _filter_provider_queryset_for_user(_with_rating_annotations(
			ProviderProfile.objects.select_related("user")
			.prefetch_related("providercategory_set__subcategory__category", "cover_gallery")
			.filter(
				user__is_active=True,
			)
			.annotate(
				# Keep parity with profile stats: count unique follower users,
				# not follow rows per role_context.
				followers_count=Count("followers__user", distinct=True),
				likes_count=Count("likes", distinct=True),
				completed_requests=Count(
					"assigned_requests",
					filter=Q(assigned_requests__status=RequestStatus.COMPLETED),
					distinct=True,
				),
			)
		), self.request)


class MyFollowingProvidersView(generics.ListAPIView):
	"""Providers the current user follows, de-duplicated across account modes."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		followed_provider_ids = ProviderFollow.objects.filter(
			user=self.request.user,
		).values("provider_id").distinct()
		return _filter_provider_queryset_for_user(_with_rating_annotations(
			ProviderProfile.objects.filter(id__in=followed_provider_ids)
			.prefetch_related("cover_gallery")
			.annotate(
				# Keep parity with provider stats: count unique users, not role rows.
				followers_count=Count("followers__user", distinct=True),
				likes_count=Count("likes__user", distinct=True),
				activity_at=Coalesce(
					Max("portfolio_items__created_at"),
					F("updated_at"),
					F("created_at"),
				),
			)
			.distinct()
			.order_by("-activity_at", "-id")
		), self.request)


class ProviderPortfolioListView(generics.ListAPIView):
	"""Public portfolio items for a provider."""

	serializer_class = ProviderPortfolioItemSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		qs = (
			ProviderPortfolioItem.objects.filter(provider_id=provider_id)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(comments_count=Count("comments", filter=Q(comments__is_approved=True), distinct=True))
		)
		qs = _filter_portfolio_queryset_for_user(qs, self.request)
		user = self.request.user
		if user.is_authenticated:
			role = get_active_role(self.request)
			qs = qs.annotate(
				_is_liked=Exists(
					ProviderPortfolioLike.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderPortfolioSave.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
		return qs.order_by("-created_at", "-id")


class MyProviderPortfolioListCreateView(generics.ListCreateAPIView):
	"""Portfolio items for the authenticated provider (list + add)."""

	permission_classes = [IsAtLeastProvider]

	def get_queryset(self):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			return ProviderPortfolioItem.objects.none()
		return (
			ProviderPortfolioItem.objects.filter(provider=pp)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.order_by("-created_at", "-id")
		)

	def get_serializer_class(self):
		if self.request.method == "POST":
			return ProviderPortfolioItemCreateSerializer
		return ProviderPortfolioItemSerializer

	def perform_create(self, serializer):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			raise NotFound("provider_profile_not_found")
		item = serializer.save(provider=pp)
		ensure_media_thumbnail(item)

	def create(self, request, *args, **kwargs):
		try:
			return super().create(request, *args, **kwargs)
		except Exception as exc:
			if _is_storage_error(exc):
				return _handle_storage_error(exc)
			raise


class MyProviderPortfolioDetailView(generics.RetrieveUpdateDestroyAPIView):
	"""Provider-owned single portfolio item (retrieve/delete)."""

	permission_classes = [IsAtLeastProvider]

	def get_serializer_class(self):
		if self.request.method in {"PATCH", "PUT"}:
			return ProviderPortfolioItemUpdateSerializer
		return ProviderPortfolioItemSerializer

	def get_queryset(self):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			return ProviderPortfolioItem.objects.none()
		return (
			ProviderPortfolioItem.objects.filter(provider=pp)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.order_by("-created_at", "-id")
		)

	def perform_update(self, serializer):
		item = serializer.save()
		ensure_media_thumbnail(item, force=True)

	def update(self, request, *args, **kwargs):
		try:
			return super().update(request, *args, **kwargs)
		except Exception as exc:
			if _is_storage_error(exc):
				return _handle_storage_error(exc)
			raise


class ProviderSpotlightListView(generics.ListAPIView):
	"""Public spotlight items for a provider (separate from portfolio)."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		qs = (
			ProviderSpotlightItem.objects.filter(provider_id=provider_id)
			.select_related("provider", "provider__user")
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(comments_count=Count("comments", filter=Q(comments__is_approved=True), distinct=True))
		)
		qs = _filter_spotlight_queryset_for_user(qs, self.request)
		user = self.request.user
		if user.is_authenticated:
			role = get_active_role(self.request)
			qs = qs.annotate(
				_is_liked=Exists(
					ProviderSpotlightLike.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderSpotlightSave.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
		return qs.order_by("-created_at", "-id")


class ProviderSpotlightFeedView(generics.ListAPIView):
	"""Public home spotlight feed: active paid items plus items added today, else latest fallback."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		from django.utils import timezone
		from apps.promo.models import PromoAdType, PromoRequestItem, PromoRequestStatus, PromoServiceType
		randomize = (self.request.query_params.get("random") or "").strip().lower() in {"1", "true", "yes"}
		fallback_applied = False

		base_qs = _filter_spotlight_queryset_for_user((
			ProviderSpotlightItem.objects.select_related("provider", "provider__user")
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(comments_count=Count("comments", filter=Q(comments__is_approved=True), distinct=True))
		), self.request)
		qs = base_qs.filter(provider__user__is_active=True) if randomize else base_qs

		def annotate_user_state(queryset):
			user = self.request.user
			if not user.is_authenticated:
				return queryset
			role = get_active_role(self.request)
			return queryset.annotate(
				_is_liked=Exists(
					ProviderSpotlightLike.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderSpotlightSave.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)

		if not randomize:
			now = timezone.now()
			active_snapshot_promos = PromoRequestItem.objects.filter(
				request__status=PromoRequestStatus.ACTIVE,
				request__ad_type=PromoAdType.BUNDLE,
				service_type=PromoServiceType.SNAPSHOTS,
				start_at__lte=now,
				end_at__gte=now,
			).filter(
				Q(target_spotlight_item_id=OuterRef("pk"))
				| (
					Q(target_spotlight_item__isnull=True)
					& (
						Q(target_provider_id=OuterRef("provider_id"))
						| Q(
							target_provider__isnull=True,
							request__requester__provider_profile__id=OuterRef("provider_id"),
						)
					)
				)
			)
			qs = qs.annotate(_promo_snapshot=Exists(active_snapshot_promos))
			today = timezone.localdate(now)
			qs = qs.filter(Q(_promo_snapshot=True) | Q(created_at__date=today))

		qs = annotate_user_state(qs)

		exclude_ids_raw = (self.request.query_params.get("exclude_ids") or "").strip()
		if exclude_ids_raw:
			exclude_ids = [int(value) for value in exclude_ids_raw.split(",") if value.strip().isdigit()]
			if exclude_ids:
				qs = qs.exclude(id__in=exclude_ids)

		if randomize:
			qs = qs.order_by("?")
		else:
			qs = qs.order_by("-_promo_snapshot", "-created_at", "-id")
			if not qs.exists():
				fallback_applied = True
				qs = annotate_user_state(
					base_qs
					.filter(provider__user__is_active=True)
					.order_by("-created_at", "-id")
				)

		limit_raw = (self.request.query_params.get("limit") or "").strip()
		if limit_raw.isdigit():
			limit = max(1, min(int(limit_raw), 100))
			if fallback_applied:
				limit = 1
			return qs[:limit]
		if fallback_applied:
			return qs[:1]
		return qs


class PublicSpotlightDetailView(generics.RetrieveAPIView):
	"""Public detail endpoint for a single spotlight item used by share links."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [permissions.AllowAny]
	lookup_url_kwarg = "item_id"

	def get_queryset(self):
		qs = _filter_spotlight_queryset_for_user((
			ProviderSpotlightItem.objects.select_related("provider", "provider__user")
			.filter(provider__user__is_active=True)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(comments_count=Count("comments", filter=Q(comments__is_approved=True), distinct=True))
		), self.request)
		user = self.request.user
		if user.is_authenticated:
			role = get_active_role(self.request)
			qs = qs.annotate(
				_is_liked=Exists(
					ProviderSpotlightLike.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderSpotlightSave.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
		return qs.order_by("-created_at", "-id")


class PublicPortfolioDetailView(generics.RetrieveAPIView):
	"""Public detail endpoint for a single portfolio item used by share links."""

	serializer_class = ProviderPortfolioItemSerializer
	permission_classes = [permissions.AllowAny]
	lookup_url_kwarg = "item_id"

	def get_queryset(self):
		qs = _filter_portfolio_queryset_for_user((
			ProviderPortfolioItem.objects.select_related("provider", "provider__user")
			.filter(provider__user__is_active=True)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(comments_count=Count("comments", filter=Q(comments__is_approved=True), distinct=True))
		), self.request)
		user = self.request.user
		if user.is_authenticated:
			role = get_active_role(self.request)
			qs = qs.annotate(
				_is_liked=Exists(
					ProviderPortfolioLike.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderPortfolioSave.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
		return qs.order_by("-created_at", "-id")


class ProviderPortfolioFeedView(generics.ListAPIView):
	"""Public home portfolio feed: sponsored items + latest works from newest providers."""

	serializer_class = ProviderPortfolioItemSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		from django.utils import timezone
		from apps.promo.models import PromoAdType, PromoRequestItem, PromoRequestStatus, PromoServiceType

		qs = _filter_portfolio_queryset_for_user((
			ProviderPortfolioItem.objects.select_related("provider", "provider__user")
			.filter(provider__user__is_active=True)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(comments_count=Count("comments", filter=Q(comments__is_approved=True), distinct=True))
		), self.request)

		now = timezone.now()
		active_portfolio_promos = PromoRequestItem.objects.filter(
			request__status=PromoRequestStatus.ACTIVE,
			request__ad_type=PromoAdType.BUNDLE,
			service_type=PromoServiceType.PORTFOLIO_SHOWCASE,
			start_at__lte=now,
			end_at__gte=now,
		).filter(
			Q(target_portfolio_item_id=OuterRef("pk"))
			| (
				Q(target_portfolio_item__isnull=True)
				& (
					Q(target_provider_id=OuterRef("provider_id"))
					| Q(
						target_provider__isnull=True,
						request__requester__provider_profile__id=OuterRef("provider_id"),
					)
				)
			)
		)
		qs = qs.annotate(_promo_portfolio=Exists(active_portfolio_promos))

		# Include latest works from newest providers to keep the strip fresh even
		# when sponsored inventory is low.
		newest_provider_ids = ProviderProfile.objects.filter(user__is_active=True).order_by("-id").values("id")[:60]
		qs = qs.filter(Q(_promo_portfolio=True) | Q(provider_id__in=newest_provider_ids))

		user = self.request.user
		if user.is_authenticated:
			role = get_active_role(self.request)
			qs = qs.annotate(
				_is_liked=Exists(
					ProviderPortfolioLike.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderPortfolioSave.objects.filter(
						user=user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)

		qs = qs.order_by("-_promo_portfolio", "-provider_id", "-created_at", "-id")

		limit_raw = (self.request.query_params.get("limit") or "").strip()
		if limit_raw.isdigit():
			limit = max(1, min(int(limit_raw), 100))
			return qs[:limit]
		return qs


class MyProviderSpotlightListCreateView(generics.ListCreateAPIView):
	"""Spotlight items for the authenticated provider (list + add)."""

	permission_classes = [HasProviderProfile]

	def get_queryset(self):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			return ProviderSpotlightItem.objects.none()
		return (
			ProviderSpotlightItem.objects.filter(provider=pp)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.order_by("-created_at", "-id")
		)

	def get_serializer_class(self):
		if self.request.method == "POST":
			return ProviderSpotlightItemCreateSerializer
		return ProviderSpotlightItemSerializer

	def _spotlight_quota_error_payload(self):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			raise NotFound("provider_profile_not_found")
		from apps.subscriptions.services import get_effective_active_subscription

		active_subscription = get_effective_active_subscription(self.request.user)
		plan = getattr(active_subscription, "plan", None)
		plan_name = str(getattr(plan, "title", "") or "باقتك الحالية").strip() or "باقتك الحالية"
		spotlight_quota = max(0, int(spotlight_quota_for_user(self.request.user) or 0))
		current_spotlights = ProviderSpotlightItem.objects.filter(provider=pp).count()
		if spotlight_quota <= 0:
			return {
				"detail": f"رفع اللمحات غير متاح ضمن {plan_name}. فعّل أو رقِّ الباقة للاستمرار.",
				"error_code": "spotlight_quota_unavailable",
				"plan_name": plan_name,
				"spotlight_quota": spotlight_quota,
				"current_count": current_spotlights,
			}
		if current_spotlights >= spotlight_quota:
			return {
				"detail": f"وصلت إلى الحد الأقصى لعدد اللمحات في {plan_name}. احذف لمحة حاليّة أو رقِّ الباقة لإضافة المزيد.",
				"error_code": "spotlight_quota_exceeded",
				"plan_name": plan_name,
				"spotlight_quota": spotlight_quota,
				"current_count": current_spotlights,
			}
		return None

	def perform_create(self, serializer):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			raise NotFound("provider_profile_not_found")
		item = serializer.save(provider=pp)
		ensure_media_thumbnail(item)

	def create(self, request, *args, **kwargs):
		try:
			serializer = self.get_serializer(data=request.data)
			serializer.is_valid(raise_exception=True)
			quota_error = self._spotlight_quota_error_payload()
			if quota_error is not None:
				return Response(quota_error, status=status.HTTP_400_BAD_REQUEST)
			self.perform_create(serializer)
			headers = self.get_success_headers(serializer.data)
			return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)
		except Exception as exc:
			if _is_storage_error(exc):
				return _handle_storage_error(exc)
			raise


class MyProviderSpotlightDetailView(generics.RetrieveDestroyAPIView):
	"""Provider-owned single spotlight item (retrieve/delete)."""

	permission_classes = [HasProviderProfile]
	serializer_class = ProviderSpotlightItemSerializer

	def get_queryset(self):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			return ProviderSpotlightItem.objects.none()
		return (
			ProviderSpotlightItem.objects.filter(provider=pp)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.order_by("-created_at", "-id")
		)


class MyLikedPortfolioItemsView(generics.ListAPIView):
	"""Portfolio media the current user liked (scoped to active role)."""

	serializer_class = ProviderPortfolioItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		role = get_active_role(self.request)
		return (
			ProviderPortfolioItem.objects.filter(
				likes__user=self.request.user,
				likes__role_context=role,
			)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(
				_is_liked=Exists(
					ProviderPortfolioLike.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderPortfolioSave.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class MySavedPortfolioItemsView(generics.ListAPIView):
	"""Portfolio media the current user saved (scoped to active role)."""

	serializer_class = ProviderPortfolioItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		role = get_active_role(self.request)
		return (
			ProviderPortfolioItem.objects.filter(
				saves__user=self.request.user,
				saves__role_context=role,
			)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(
				_is_liked=Exists(
					ProviderPortfolioLike.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderPortfolioSave.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class MyLikedSpotlightItemsView(generics.ListAPIView):
	"""Spotlight media the current user liked (scoped to active role)."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		role = get_active_role(self.request)
		return (
			ProviderSpotlightItem.objects.filter(
				likes__user=self.request.user,
				likes__role_context=role,
			)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(
				_is_liked=Exists(
					ProviderSpotlightLike.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderSpotlightSave.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class MySavedSpotlightItemsView(generics.ListAPIView):
	"""Spotlight media the current user saved (scoped to active role)."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		role = get_active_role(self.request)
		return (
			ProviderSpotlightItem.objects.filter(
				saves__user=self.request.user,
				saves__role_context=role,
			)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.annotate(
				_is_liked=Exists(
					ProviderSpotlightLike.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
				_is_saved=Exists(
					ProviderSpotlightSave.objects.filter(
						user=self.request.user,
						item=OuterRef("pk"),
						role_context=role,
					)
				),
			)
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class LikePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		item = generics.get_object_or_404(ProviderPortfolioItem, id=item_id)
		ProviderPortfolioLike.objects.get_or_create(user=request.user, item=item, role_context=role)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnlikePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		ProviderPortfolioLike.objects.filter(user=request.user, item_id=item_id, role_context=role).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class SavePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		item = generics.get_object_or_404(ProviderPortfolioItem, id=item_id)
		ProviderPortfolioSave.objects.get_or_create(user=request.user, item=item, role_context=role)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnsavePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		ProviderPortfolioSave.objects.filter(user=request.user, item_id=item_id, role_context=role).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class LikeSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		item = generics.get_object_or_404(ProviderSpotlightItem, id=item_id)
		ProviderSpotlightLike.objects.get_or_create(user=request.user, item=item, role_context=role)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnlikeSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		ProviderSpotlightLike.objects.filter(user=request.user, item_id=item_id, role_context=role).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class SaveSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		item = generics.get_object_or_404(ProviderSpotlightItem, id=item_id)
		ProviderSpotlightSave.objects.get_or_create(user=request.user, item=item, role_context=role)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnsaveSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		ProviderSpotlightSave.objects.filter(user=request.user, item_id=item_id, role_context=role).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class MyLikedProvidersView(generics.ListAPIView):
	"""Providers the current user liked (scoped to active role)."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		role = get_active_role(self.request)
		liked_by_me = ProviderLike.objects.filter(
			provider=OuterRef("pk"),
			user=self.request.user,
			role_context=role,
		)
		return _with_rating_annotations(
			ProviderProfile.objects.prefetch_related("cover_gallery").annotate(_is_liked=Exists(liked_by_me))
			.filter(_is_liked=True)
			.annotate(
				followers_count=Count("followers__user", distinct=True),
				likes_count=Count("likes__user", distinct=True),
			)
			.distinct()
			.order_by("-id")
		)


class MyProviderFollowersView(generics.ListAPIView):
	"""Users who follow the current user's provider profile across all modes."""
	serializer_class = ProviderFollowerSerializer
	permission_classes = [IsAtLeastProvider]

	def get_queryset(self):
		provider_profile = getattr(self.request.user, "provider_profile", None)
		if not provider_profile:
			return ProviderFollow.objects.none()
		qs = ProviderFollow.objects.filter(
			provider=provider_profile,
		).select_related("user", "user__provider_profile")
		return qs.filter(id__in=_dedup_follow_ids(qs)).order_by("-created_at", "-id")


class MyProviderLikersView(generics.ListAPIView):
	"""Users who liked the current user's provider profile (if exists)."""
	serializer_class = UserPublicSerializer
	permission_classes = [IsAtLeastProvider]

	def get_queryset(self):
		provider_profile = getattr(self.request.user, "provider_profile", None)
		if not provider_profile:
			return User.objects.none()

		return (
			User.objects.filter(provider_likes__provider=provider_profile)
			.distinct()
			.order_by("-id")
		)


class ProviderFollowersView(generics.ListAPIView):
	"""Public: Users who follow a specific provider.

	By default the list is scoped to the viewer's active role mode
	(client vs provider) so it stays consistent with the same-mode counts
	used inside the app. Public profile UIs that show the *total* followers
	count across both modes can opt-in to the cross-mode list by passing
	``?scope=all``; in that case rows are de-duplicated per user, preferring
	the ``provider`` role context so the bond to a provider profile is kept.
	"""
	serializer_class = ProviderFollowerSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		scope = (self.request.query_params.get("scope") or "").strip().lower()
		qs = (
			ProviderFollow.objects.filter(provider_id=provider_id)
			.select_related("user", "user__provider_profile")
		)
		if scope == "all":
			return qs.filter(id__in=_dedup_follow_ids(qs)).order_by("-created_at", "-id")
		role = get_active_role(self.request, fallback="client")
		return qs.filter(role_context=role).order_by("-created_at", "-id")


class ProviderFollowingView(generics.ListAPIView):
	"""Public: Providers that a specific provider follows.

	By default the list is scoped to the viewer's active role mode. Pass
	``?scope=all`` to return every provider followed by this user across
	both modes (de-duplicated per provider), matching the public total.
	"""
	serializer_class = ProviderPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		scope = (self.request.query_params.get("scope") or "").strip().lower()
		try:
			provider = ProviderProfile.objects.get(id=provider_id)
		except ProviderProfile.DoesNotExist:
			return ProviderProfile.objects.none()

		user = provider.user
		if scope == "all":
			followed_provider_ids = ProviderFollow.objects.filter(
				user=user,
			).values("provider_id").distinct()
			return _with_rating_annotations(
				ProviderProfile.objects.filter(id__in=followed_provider_ids)
				.prefetch_related("cover_gallery")
				.annotate(
					followers_count=Count("followers__user", distinct=True),
					likes_count=Count("likes__user", distinct=True),
				)
				.distinct()
				.order_by("-id")
			)
		else:
			role = get_active_role(self.request, fallback="provider")
			follow_filter = ProviderFollow.objects.filter(
				provider=OuterRef("pk"),
				user=user,
				role_context=role,
			)
		return _with_rating_annotations(
			ProviderProfile.objects.prefetch_related("cover_gallery").annotate(_is_followed=Exists(follow_filter))
			.filter(_is_followed=True)
			.annotate(
				followers_count=Count("followers__user", distinct=True),
				likes_count=Count("likes__user", distinct=True),
			)
			.distinct()
			.order_by("-id")
		)


class ProviderPublicStatsView(APIView):
	"""Public lightweight stats for a provider profile."""
	permission_classes = [permissions.AllowAny]

	def get(self, request, provider_id: int):
		from django.core.cache import cache as _cache
		from apps.marketplace.client_relationships import provider_service_request_client_ids
		role = _active_role_or_default(request)
		if request.user.is_authenticated and ProviderVisibilityBlock.objects.filter(user=request.user, provider_id=provider_id, role_context=role).exists():
			raise NotFound("provider_not_found")

		cache_key = f"provider:{provider_id}:public_stats:shared:v2"
		cached = _cache.get(cache_key)
		if cached is not None:
			return Response(cached, status=status.HTTP_200_OK)

		provider = (
			ProviderProfile.objects.select_related("user")
			.filter(id=provider_id, user__is_active=True)
			.first()
		)
		if not provider:
			raise NotFound("provider_not_found")

		# Import locally to avoid hard coupling at import time.
		from apps.marketplace.models import ServiceRequest, RequestStatus

		completed_requests = ServiceRequest.objects.filter(
			provider_id=provider_id,
			status=RequestStatus.COMPLETED,
		).count()
		total_clients = len(provider_service_request_client_ids(provider))
		followers_count = (
			ProviderFollow.objects.filter(provider_id=provider_id)
			.values("user_id")
			.distinct()
			.count()
		)
		following_count = (
			ProviderFollow.objects.filter(
				user=provider.user,
			)
			.values("provider_id")
			.distinct()
			.count()
		)
		profile_likes_count = (
			ProviderLike.objects.filter(provider_id=provider_id)
			.values("user_id")
			.distinct()
			.count()
		)
		portfolio_likes_count = ProviderPortfolioLike.objects.filter(
			item__provider_id=provider_id,
		).count()
		portfolio_saves_count = ProviderPortfolioSave.objects.filter(
			item__provider_id=provider_id,
		).count()
		spotlight_likes_count = ProviderSpotlightLike.objects.filter(
			item__provider_id=provider_id,
		).count()
		spotlight_saves_count = ProviderSpotlightSave.objects.filter(
			item__provider_id=provider_id,
		).count()
		media_likes_count = portfolio_likes_count + spotlight_likes_count
		media_saves_count = portfolio_saves_count + spotlight_saves_count
		rating = calculate_provider_rating(provider_id)

		payload = {
			"provider_id": provider_id,
			"total_clients": total_clients,
			"completed_requests": completed_requests,
			"followers_count": followers_count,
			"following_count": following_count,
			# Backward-compatible: keep profile likes on legacy key.
			"likes_count": profile_likes_count,
			"profile_likes_count": profile_likes_count,
			"portfolio_likes_count": portfolio_likes_count,
			"spotlight_likes_count": spotlight_likes_count,
			"media_likes_count": media_likes_count,
			"portfolio_saves_count": portfolio_saves_count,
			"spotlight_saves_count": spotlight_saves_count,
			"media_saves_count": media_saves_count,
			"rating_avg": rating["rating_avg"],
			"rating_count": rating["rating_count"],
		}
		_cache.set(cache_key, payload, 300)  # 5 minutes
		return Response(payload, status=status.HTTP_200_OK)


class ReportSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		item = generics.get_object_or_404(
			ProviderSpotlightItem.objects.select_related("provider", "provider__user"),
			id=item_id,
			provider__user__is_active=True,
		)
		if request.user.id == item.provider.user_id:
			return Response({"detail": "لا يمكنك الإبلاغ عن لمحتك الخاصة."}, status=status.HTTP_400_BAD_REQUEST)

		from apps.moderation.services import assign_case, create_case

		reason = str(request.data.get("reason") or "").strip()[:120] or "إبلاغ عن لمحة"
		details = str(request.data.get("details") or "").strip()[:500]
		case = create_case(
			reporter=request.user,
			payload={
				"reported_user": item.provider.user,
				"source_app": "providers",
				"source_model": "ProviderSpotlightItem",
				"source_object_id": str(item.id),
				"source_label": f"لمحة {item.provider.display_name}",
				"category": "spotlight",
				"reason": reason,
				"details": details,
				"summary": f"بلاغ على لمحة {item.provider.display_name}",
				"severity": "normal",
				"snapshot": {
					"provider_id": item.provider_id,
					"provider_name": item.provider.display_name,
					"caption": item.caption,
					"file_type": item.file_type,
					"file_url": getattr(getattr(item, "file", None), "url", "") or "",
					"thumbnail_url": getattr(item.thumbnail, "url", "") if getattr(item, "thumbnail", None) else "",
				},
				"meta": {
					"surface": str(request.data.get("surface") or "mobile_web.spotlight_viewer"),
					"provider_id": item.provider_id,
					"spotlight_id": item.id,
				},
			},
			request=request,
		)
		assign_case(
			case=case,
			assigned_team_code="content",
			assigned_team_name="المحتوى والمراجعات",
			note="بلاغ وارد من عارض اللمحات",
			by_user=request.user,
			request=request,
		)
		return Response({"ok": True, "case_id": case.id, "case_code": case.code}, status=status.HTTP_201_CREATED)


class ReportPortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		item = generics.get_object_or_404(
			ProviderPortfolioItem.objects.select_related("provider", "provider__user"),
			id=item_id,
			provider__user__is_active=True,
		)
		if request.user.id == item.provider.user_id:
			return Response({"detail": "لا يمكنك الإبلاغ عن محتواك الخاص."}, status=status.HTTP_400_BAD_REQUEST)

		from apps.moderation.services import assign_case, create_case

		reason = str(request.data.get("reason") or "").strip()[:120] or "إبلاغ عن محتوى خدمات ومشاريع"
		details = str(request.data.get("details") or "").strip()[:500]
		case = create_case(
			reporter=request.user,
			payload={
				"reported_user": item.provider.user,
				"source_app": "providers",
				"source_model": "ProviderPortfolioItem",
				"source_object_id": str(item.id),
				"source_label": f"محتوى خدمات ومشاريع {item.provider.display_name}",
				"category": "portfolio",
				"reason": reason,
				"details": details,
				"summary": f"بلاغ على محتوى خدمات ومشاريع {item.provider.display_name}",
				"severity": "normal",
				"snapshot": {
					"provider_id": item.provider_id,
					"provider_name": item.provider.display_name,
					"caption": item.caption,
					"file_type": item.file_type,
					"file_url": getattr(getattr(item, "file", None), "url", "") or "",
					"thumbnail_url": getattr(item.thumbnail, "url", "") if getattr(item, "thumbnail", None) else "",
				},
				"meta": {
					"surface": str(request.data.get("surface") or "mobile_web.portfolio_viewer"),
					"provider_id": item.provider_id,
					"portfolio_item_id": item.id,
				},
			},
			request=request,
		)
		assign_case(
			case=case,
			assigned_team_code="content",
			assigned_team_name="المحتوى والمراجعات",
			note="بلاغ وارد من عارض خدمات ومشاريع",
			by_user=request.user,
			request=request,
		)
		return Response({"ok": True, "case_id": case.id, "case_code": case.code}, status=status.HTTP_201_CREATED)


def _get_spotlight_comment_or_404(request, item_id: int, comment_id: int):
	item = generics.get_object_or_404(
		_filter_spotlight_queryset_for_user(
			ProviderSpotlightItem.objects.select_related("provider", "provider__user").filter(provider__user__is_active=True),
			request,
		),
		id=item_id,
	)
	comment = generics.get_object_or_404(
		ProviderContentComment.objects.filter(spotlight_item=item, is_approved=True).select_related("user", "provider"),
		id=comment_id,
	)
	return item, comment


def _get_portfolio_comment_or_404(request, item_id: int, comment_id: int):
	item = generics.get_object_or_404(
		_filter_portfolio_queryset_for_user(
			ProviderPortfolioItem.objects.select_related("provider", "provider__user").filter(provider__user__is_active=True),
			request,
		),
		id=item_id,
	)
	comment = generics.get_object_or_404(
		ProviderContentComment.objects.filter(portfolio_item=item, is_approved=True).select_related("user", "provider"),
		id=comment_id,
	)
	return item, comment


class LikeSpotlightCommentView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int, comment_id: int):
		_, comment = _get_spotlight_comment_or_404(request, item_id, comment_id)
		role = get_active_role(request)
		ProviderContentCommentLike.objects.get_or_create(user=request.user, comment=comment, role_context=role)
		return Response({"ok": True, "likes_count": comment.likes.count()}, status=status.HTTP_200_OK)


class UnlikeSpotlightCommentView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int, comment_id: int):
		_, comment = _get_spotlight_comment_or_404(request, item_id, comment_id)
		role = get_active_role(request)
		ProviderContentCommentLike.objects.filter(user=request.user, comment=comment, role_context=role).delete()
		return Response({"ok": True, "likes_count": comment.likes.count()}, status=status.HTTP_200_OK)


class ReportSpotlightCommentView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int, comment_id: int):
		item, comment = _get_spotlight_comment_or_404(request, item_id, comment_id)
		ticket = _create_content_comment_report_ticket(
			request=request,
			comment=comment,
			reported_kind="spotlight_comment",
			label="لمحة",
			content_ref=f"Spotlight#{item.id}",
		)
		return Response({"ok": True, "ticket_id": ticket.id, "ticket_code": ticket.code}, status=status.HTTP_201_CREATED)


class LikePortfolioCommentView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int, comment_id: int):
		_, comment = _get_portfolio_comment_or_404(request, item_id, comment_id)
		role = get_active_role(request)
		ProviderContentCommentLike.objects.get_or_create(user=request.user, comment=comment, role_context=role)
		return Response({"ok": True, "likes_count": comment.likes.count()}, status=status.HTTP_200_OK)


class UnlikePortfolioCommentView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int, comment_id: int):
		_, comment = _get_portfolio_comment_or_404(request, item_id, comment_id)
		role = get_active_role(request)
		ProviderContentCommentLike.objects.filter(user=request.user, comment=comment, role_context=role).delete()
		return Response({"ok": True, "likes_count": comment.likes.count()}, status=status.HTTP_200_OK)


class ReportPortfolioCommentView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int, comment_id: int):
		item, comment = _get_portfolio_comment_or_404(request, item_id, comment_id)
		ticket = _create_content_comment_report_ticket(
			request=request,
			comment=comment,
			reported_kind="portfolio_comment",
			label="خدمات ومشاريع",
			content_ref=f"Portfolio#{item.id}",
		)
		return Response({"ok": True, "ticket_id": ticket.id, "ticket_code": ticket.code}, status=status.HTTP_201_CREATED)


class SpotlightCommentsView(APIView):
	permission_classes = [permissions.AllowAny]

	def _item_queryset(self, request):
		return _filter_spotlight_queryset_for_user(
			ProviderSpotlightItem.objects.select_related("provider", "provider__user").filter(provider__user__is_active=True),
			request,
		)

	def _get_item(self, request, item_id: int):
		return generics.get_object_or_404(self._item_queryset(request), id=item_id)

	def get(self, request, item_id: int):
		item = self._get_item(request, item_id)
		limit_raw = str(request.query_params.get("limit") or "").strip()
		limit = max(1, min(int(limit_raw), 100)) if limit_raw.isdigit() else 25
		replies_prefetch = Prefetch(
			"replies",
			queryset=_annotate_content_comment_queryset(
				ProviderContentComment.objects.filter(is_approved=True),
				request,
			)
			.select_related("user", "user__provider_profile")
			.order_by("created_at", "id"),
			to_attr="prefetched_replies",
		)
		comments_qs = _annotate_content_comment_queryset((
			ProviderContentComment.objects.filter(spotlight_item=item, is_approved=True, parent__isnull=True)
			.select_related("user", "user__provider_profile")
			.prefetch_related(replies_prefetch)
			.order_by("-created_at", "-id")
		), request)
		rows = list(comments_qs[:limit])
		serializer = SpotlightCommentSerializer(rows, many=True, context={"request": request})
		return Response(
			{
				"count": ProviderContentComment.objects.filter(spotlight_item=item, is_approved=True).count(),
				"results": serializer.data,
			},
			status=status.HTTP_200_OK,
		)

	def post(self, request, item_id: int):
		if not request.user.is_authenticated:
			return Response({"detail": "Authentication credentials were not provided."}, status=status.HTTP_401_UNAUTHORIZED)
		if not IsAtLeastPhoneOnly().has_permission(request, self):
			return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)
		role = get_active_role(request)
		item = self._get_item(request, item_id)
		serializer = SpotlightCommentCreateSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		parent = serializer.validated_data.get("parent")
		if parent and int(getattr(parent, "spotlight_item_id", 0) or 0) != int(item.id):
			return Response({"parent": ["التعليق الأصلي لا يتبع هذه اللمحة"]}, status=status.HTTP_400_BAD_REQUEST)
		comment = ProviderContentComment.objects.create(
			provider=item.provider,
			user=request.user,
			spotlight_item=item,
			parent=parent,
			role_context=role,
			body=serializer.validated_data["body"],
			is_approved=True,
		)
		return Response(
			SpotlightCommentSerializer(comment, context={"request": request}).data,
			status=status.HTTP_201_CREATED,
		)


class PortfolioCommentsView(APIView):
	permission_classes = [permissions.AllowAny]

	def _item_queryset(self, request):
		return _filter_portfolio_queryset_for_user(
			ProviderPortfolioItem.objects.select_related("provider", "provider__user").filter(provider__user__is_active=True),
			request,
		)

	def _get_item(self, request, item_id: int):
		return generics.get_object_or_404(self._item_queryset(request), id=item_id)

	def get(self, request, item_id: int):
		item = self._get_item(request, item_id)
		limit_raw = str(request.query_params.get("limit") or "").strip()
		limit = max(1, min(int(limit_raw), 100)) if limit_raw.isdigit() else 25
		replies_prefetch = Prefetch(
			"replies",
			queryset=_annotate_content_comment_queryset(
				ProviderContentComment.objects.filter(is_approved=True),
				request,
			)
			.select_related("user", "user__provider_profile")
			.order_by("created_at", "id"),
			to_attr="prefetched_replies",
		)
		comments_qs = _annotate_content_comment_queryset((
			ProviderContentComment.objects.filter(portfolio_item=item, is_approved=True, parent__isnull=True)
			.select_related("user", "user__provider_profile")
			.prefetch_related(replies_prefetch)
			.order_by("-created_at", "-id")
		), request)
		rows = list(comments_qs[:limit])
		serializer = SpotlightCommentSerializer(rows, many=True, context={"request": request})
		return Response(
			{
				"count": ProviderContentComment.objects.filter(portfolio_item=item, is_approved=True).count(),
				"results": serializer.data,
			},
			status=status.HTTP_200_OK,
		)

	def post(self, request, item_id: int):
		if not request.user.is_authenticated:
			return Response({"detail": "Authentication credentials were not provided."}, status=status.HTTP_401_UNAUTHORIZED)
		if not IsAtLeastPhoneOnly().has_permission(request, self):
			return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)
		role = get_active_role(request)
		item = self._get_item(request, item_id)
		serializer = SpotlightCommentCreateSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		parent = serializer.validated_data.get("parent")
		if parent and int(getattr(parent, "portfolio_item_id", 0) or 0) != int(item.id):
			return Response({"parent": ["التعليق الأصلي لا يتبع هذا المحتوى"]}, status=status.HTTP_400_BAD_REQUEST)
		comment = ProviderContentComment.objects.create(
			provider=item.provider,
			user=request.user,
			portfolio_item=item,
			parent=parent,
			role_context=role,
			body=serializer.validated_data["body"],
			is_approved=True,
		)
		return Response(
			SpotlightCommentSerializer(comment, context={"request": request}).data,
			status=status.HTTP_201_CREATED,
		)


class SpotlightCommentDetailView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def delete(self, request, item_id: int, comment_id: int):
		item = generics.get_object_or_404(
			_filter_spotlight_queryset_for_user(
				ProviderSpotlightItem.objects.select_related("provider", "provider__user").filter(provider__user__is_active=True),
				request,
			),
			id=item_id,
		)
		comment = generics.get_object_or_404(
			ProviderContentComment.objects.filter(spotlight_item=item).select_related("user"),
			id=comment_id,
		)
		if request.user.id != comment.user_id:
			return Response({"detail": "يمكنك حذف تعليقك فقط"}, status=status.HTTP_403_FORBIDDEN)
		deleted_id = comment.id
		comment.delete()
		return Response({"ok": True, "deleted": True, "comment_id": deleted_id}, status=status.HTTP_200_OK)


class PortfolioCommentDetailView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def delete(self, request, item_id: int, comment_id: int):
		item = generics.get_object_or_404(
			_filter_portfolio_queryset_for_user(
				ProviderPortfolioItem.objects.select_related("provider", "provider__user").filter(provider__user__is_active=True),
				request,
			),
			id=item_id,
		)
		comment = generics.get_object_or_404(
			ProviderContentComment.objects.filter(portfolio_item=item).select_related("user"),
			id=comment_id,
		)
		if request.user.id != comment.user_id:
			return Response({"detail": "يمكنك حذف تعليقك فقط"}, status=status.HTTP_403_FORBIDDEN)
		deleted_id = comment.id
		comment.delete()
		return Response({"ok": True, "deleted": True, "comment_id": deleted_id}, status=status.HTTP_200_OK)


class MyVisibilityBlocksView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def get(self, request):
		role = get_active_role(request)
		provider_blocks = ProviderVisibilityBlock.objects.filter(user=request.user, role_context=role).select_related("provider", "provider__user").order_by("-created_at")
		spotlight_blocks = ProviderSpotlightVisibilityBlock.objects.filter(user=request.user, role_context=role).select_related(
			"spotlight_item",
			"spotlight_item__provider",
			"spotlight_item__provider__user",
		).order_by("-created_at")
		portfolio_blocks = ProviderPortfolioVisibilityBlock.objects.filter(user=request.user, role_context=role).select_related(
			"portfolio_item",
			"portfolio_item__provider",
			"portfolio_item__provider__user",
		).order_by("-created_at")
		return Response(
			{
				"blocked_providers": BlockedProviderSerializer(provider_blocks, many=True, context={"request": request}).data,
				"blocked_spotlights": BlockedSpotlightSerializer(spotlight_blocks, many=True, context={"request": request}).data,
				"blocked_portfolio": BlockedPortfolioSerializer(portfolio_blocks, many=True, context={"request": request}).data,
			},
			status=status.HTTP_200_OK,
		)


class BlockSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		item = generics.get_object_or_404(
			ProviderSpotlightItem.objects.select_related("provider", "provider__user"),
			id=item_id,
			provider__user__is_active=True,
		)
		block, created = ProviderSpotlightVisibilityBlock.objects.get_or_create(
			user=request.user,
			spotlight_item=item,
			role_context=role,
		)
		return Response({"ok": True, "blocked": True, "created": created, "spotlight_id": block.spotlight_item_id}, status=status.HTTP_200_OK)

	def delete(self, request, item_id: int):
		role = get_active_role(request)
		deleted_count, _ = ProviderSpotlightVisibilityBlock.objects.filter(
			user=request.user,
			spotlight_item_id=item_id,
			role_context=role,
		).delete()
		return Response({"ok": True, "blocked": False, "deleted": bool(deleted_count), "spotlight_id": item_id}, status=status.HTTP_200_OK)


class BlockPortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		role = get_active_role(request)
		item = generics.get_object_or_404(
			ProviderPortfolioItem.objects.select_related("provider", "provider__user"),
			id=item_id,
			provider__user__is_active=True,
		)
		block, created = ProviderPortfolioVisibilityBlock.objects.get_or_create(
			user=request.user,
			portfolio_item=item,
			role_context=role,
		)
		return Response({"ok": True, "blocked": True, "created": created, "portfolio_item_id": block.portfolio_item_id}, status=status.HTTP_200_OK)

	def delete(self, request, item_id: int):
		role = get_active_role(request)
		deleted_count, _ = ProviderPortfolioVisibilityBlock.objects.filter(
			user=request.user,
			portfolio_item_id=item_id,
			role_context=role,
		).delete()
		return Response({"ok": True, "blocked": False, "deleted": bool(deleted_count), "portfolio_item_id": item_id}, status=status.HTTP_200_OK)


class BlockProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		role = get_active_role(request)
		provider = generics.get_object_or_404(
			ProviderProfile.objects.select_related("user"),
			id=provider_id,
			user__is_active=True,
		)
		if request.user.id == provider.user_id:
			return Response({"detail": "لا يمكنك حظر حسابك الخاص."}, status=status.HTTP_400_BAD_REQUEST)
		block, created = ProviderVisibilityBlock.objects.get_or_create(
			user=request.user,
			provider=provider,
			role_context=role,
		)
		return Response({"ok": True, "blocked": True, "created": created, "provider_id": block.provider_id}, status=status.HTTP_200_OK)

	def delete(self, request, provider_id: int):
		role = get_active_role(request)
		deleted_count, _ = ProviderVisibilityBlock.objects.filter(
			user=request.user,
			provider_id=provider_id,
			role_context=role,
		).delete()
		return Response({"ok": True, "blocked": False, "deleted": bool(deleted_count), "provider_id": provider_id}, status=status.HTTP_200_OK)


def _invalidate_provider_counters(provider_id: int) -> None:
	"""Delete cached follower/like counts so they are recalculated on next read."""
	from django.core.cache import cache as _cache
	_cache.delete_many([
		f"provider:{provider_id}:followers",
		f"provider:{provider_id}:likes",
		f"provider:{provider_id}:public_stats:client",
		f"provider:{provider_id}:public_stats:provider",
		f"provider:{provider_id}:public_stats:shared",
		f"provider:{provider_id}:public_stats:shared:v2",
	])


def _share_tracking_session_id(request) -> str:
	session = getattr(request, "session", None)
	if session is None:
		return ""
	if not session.session_key:
		session.save()
	return str(session.session_key or "")


class RecordProviderContentShareView(APIView):
	permission_classes = [permissions.AllowAny]

	def post(self, request, provider_id: int):
		provider = generics.get_object_or_404(ProviderProfile, id=provider_id)
		content_type = str(request.data.get("content_type") or ContentShareContentType.PROFILE).strip().lower()
		if content_type not in {value for value, _ in ContentShareContentType.choices}:
			return Response(
				{"detail": "نوع المحتوى غير صالح لتسجيل المشاركة."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		channel = str(request.data.get("channel") or ContentShareChannel.OTHER).strip().lower()
		if channel not in {value for value, _ in ContentShareChannel.choices}:
			return Response(
				{"detail": "قناة المشاركة غير صالحة."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		content_id = None
		if content_type != ContentShareContentType.PROFILE:
			raw_content_id = request.data.get("content_id")
			try:
				content_id = int(raw_content_id)
			except (TypeError, ValueError):
				return Response(
					{"detail": "يجب إرسال معرف المحتوى عند تسجيل هذه المشاركة."},
					status=status.HTTP_400_BAD_REQUEST,
				)
			if content_id <= 0:
				return Response(
					{"detail": "معرف المحتوى غير صالح."},
					status=status.HTTP_400_BAD_REQUEST,
				)
			content_model = ProviderPortfolioItem if content_type == ContentShareContentType.PORTFOLIO else ProviderSpotlightItem
			if not content_model.objects.filter(id=content_id, provider=provider).exists():
				return Response(
					{"detail": "المحتوى المطلوب لا ينتمي إلى هذا المزود."},
					status=status.HTTP_400_BAD_REQUEST,
				)

		session_id = str(request.data.get("session_id") or "").strip() or _share_tracking_session_id(request)
		share = ProviderContentShare.objects.create(
			provider=provider,
			user=request.user if getattr(request.user, "is_authenticated", False) else None,
			content_type=content_type,
			content_id=content_id,
			channel=channel,
			session_id=session_id[:64],
		)
		return Response({"ok": True, "share_id": share.id}, status=status.HTTP_200_OK)


class FollowProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		role = get_active_role(request)
		provider = generics.get_object_or_404(ProviderProfile, id=provider_id)
		ProviderFollow.objects.get_or_create(user=request.user, provider=provider, role_context=role)
		_invalidate_provider_counters(provider_id)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnfollowProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		role = get_active_role(request)
		ProviderFollow.objects.filter(user=request.user, provider_id=provider_id, role_context=role).delete()
		_invalidate_provider_counters(provider_id)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class LikeProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		role = get_active_role(request)
		provider = generics.get_object_or_404(ProviderProfile, id=provider_id)
		ProviderLike.objects.get_or_create(user=request.user, provider=provider, role_context=role)
		_invalidate_provider_counters(provider_id)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnlikeProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		role = get_active_role(request)
		ProviderLike.objects.filter(user=request.user, provider_id=provider_id, role_context=role).delete()
		_invalidate_provider_counters(provider_id)
		return Response({"ok": True}, status=status.HTTP_200_OK)
