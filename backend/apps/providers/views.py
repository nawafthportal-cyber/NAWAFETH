import logging

from django.utils.decorators import method_decorator
from django.views.decorators.cache import cache_page
from rest_framework import generics, permissions, status
from rest_framework.exceptions import NotFound
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db.models import Count, Exists, F, Max, OuterRef, Prefetch, Q
from django.db.models.functions import Coalesce
from django.db import transaction

logger = logging.getLogger(__name__)

from apps.accounts.models import User

from apps.accounts.models import UserRole
from apps.accounts.permissions import IsAtLeastClient, IsAtLeastPhoneOnly, IsAtLeastProvider
from apps.accounts.role_context import get_active_role

from .models import (
	Category,
	ProviderFollow,
	ProviderLike,
	ProviderCategory,
	ProviderPortfolioItem,
	ProviderPortfolioLike,
	ProviderPortfolioSave,
	ProviderProfile,
	ProviderService,
	ProviderSpotlightItem,
	ProviderSpotlightLike,
	ProviderSpotlightSave,
	SaudiRegion,
	SubCategory,
	sync_provider_accepts_urgent_flag,
)
from .serializers import (
	CategorySerializer,
	MyProviderSubcategoriesSerializer,
	ProviderFollowerSerializer,
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
	ProviderSpotlightItemCreateSerializer,
	ProviderSpotlightItemSerializer,
	UserPublicSerializer,
)
from .media_thumbnails import ensure_video_thumbnail


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


class MyProviderProfileView(generics.RetrieveUpdateAPIView):
	"""Get/update the current user's provider profile."""

	serializer_class = ProviderProfileMeSerializer
	permission_classes = [IsAtLeastClient]

	def get_object(self):
		provider_profile = (
			ProviderProfile.objects.select_related("user")
			.prefetch_related("providercategory_set__subcategory__category")
			.filter(user=self.request.user)
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
		settings = [
			{"subcategory_id": row.subcategory_id, "accepts_urgent": bool(row.accepts_urgent)}
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


@method_decorator(cache_page(60 * 60), name="dispatch")  # 1 hour
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
		qs = (
			ProviderProfile.objects.select_related("user")
			.prefetch_related("providercategory_set__subcategory__category")
			.filter(
				user__is_active=True,
			)
			.annotate(
				followers_count=Count("followers", distinct=True),
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
			qs = qs.filter(city__icontains=city)
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
		return qs.distinct()


class ProviderDetailView(generics.RetrieveAPIView):
	serializer_class = ProviderPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		from apps.marketplace.models import RequestStatus
		return (
			ProviderProfile.objects.select_related("user")
			.prefetch_related("providercategory_set__subcategory__category")
			.filter(
				user__is_active=True,
			)
			.annotate(
				followers_count=Count("followers", distinct=True),
				likes_count=Count("likes", distinct=True),
				completed_requests=Count(
					"assigned_requests",
					filter=Q(assigned_requests__status=RequestStatus.COMPLETED),
					distinct=True,
				),
			)
		)


class MyFollowingProvidersView(generics.ListAPIView):
	"""Providers the current user follows (scoped to active role)."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		role = get_active_role(self.request)
		followed_by_me = ProviderFollow.objects.filter(
			provider=OuterRef("pk"),
			user=self.request.user,
			role_context=role,
		)
		return (
			ProviderProfile.objects.annotate(_is_followed=Exists(followed_by_me))
			.filter(_is_followed=True)
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
		)


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
		)
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
		ensure_video_thumbnail(item)

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
		)
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
	"""Public home spotlight feed: active paid items plus items added today."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		from django.utils import timezone
		from apps.promo.models import PromoAdType, PromoRequestItem, PromoRequestStatus, PromoServiceType

		qs = (
			ProviderSpotlightItem.objects.select_related("provider", "provider__user")
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
		)

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

		# Annotate is_liked / is_saved for authenticated users
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

		qs = qs.order_by("-_promo_snapshot", "-created_at", "-id")

		limit_raw = (self.request.query_params.get("limit") or "").strip()
		if limit_raw.isdigit():
			limit = max(1, min(int(limit_raw), 100))
			return qs[:limit]
		return qs


class MyProviderSpotlightListCreateView(generics.ListCreateAPIView):
	"""Spotlight items for the authenticated provider (list + add)."""

	permission_classes = [IsAtLeastProvider]

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

	def perform_create(self, serializer):
		pp = getattr(self.request.user, "provider_profile", None)
		if not pp:
			raise NotFound("provider_profile_not_found")
		item = serializer.save(provider=pp)
		ensure_video_thumbnail(item)

	def create(self, request, *args, **kwargs):
		try:
			return super().create(request, *args, **kwargs)
		except Exception as exc:
			if _is_storage_error(exc):
				return _handle_storage_error(exc)
			raise


class MyProviderSpotlightDetailView(generics.RetrieveDestroyAPIView):
	"""Provider-owned single spotlight item (retrieve/delete)."""

	permission_classes = [IsAtLeastProvider]
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
				Q(saves__user=self.request.user, saves__role_context=role)
				| Q(likes__user=self.request.user, likes__role_context=role)
			)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
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
				Q(saves__user=self.request.user, saves__role_context=role)
				| Q(likes__user=self.request.user, likes__role_context=role)
			)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
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
		return (
			ProviderProfile.objects.annotate(_is_liked=Exists(liked_by_me))
			.filter(_is_liked=True)
			.annotate(
				followers_count=Count("followers__user", distinct=True),
				likes_count=Count("likes__user", distinct=True),
			)
			.distinct()
			.order_by("-id")
		)


class MyProviderFollowersView(generics.ListAPIView):
	"""Users who follow the current user's provider profile (if exists)."""
	serializer_class = ProviderFollowerSerializer
	permission_classes = [IsAtLeastProvider]

	def get_queryset(self):
		provider_profile = getattr(self.request.user, "provider_profile", None)
		if not provider_profile:
			return ProviderFollow.objects.none()

		return (
			ProviderFollow.objects.filter(provider=provider_profile)
			.select_related("user", "user__provider_profile")
			.order_by("-created_at", "-id")
		)


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
	"""Public: Users who follow a specific provider."""
	serializer_class = UserPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		user_ids = (
			ProviderFollow.objects.filter(provider_id=provider_id)
			.values_list("user_id", flat=True)
			.distinct()
		)
		return (
			User.objects.filter(id__in=user_ids)
			.order_by("-id")
		)


class ProviderFollowingView(generics.ListAPIView):
	"""Public: Providers that a specific provider follows (scoped by role)."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		role = get_active_role(self.request, fallback="provider")
		try:
			provider = ProviderProfile.objects.get(id=provider_id)
			user = provider.user
			followed_by_provider_user = ProviderFollow.objects.filter(
				provider=OuterRef("pk"),
				user=user,
				role_context=role,
			)
			return (
				ProviderProfile.objects.annotate(_is_followed=Exists(followed_by_provider_user))
				.filter(_is_followed=True)
				.annotate(
					followers_count=Count("followers__user", distinct=True),
					likes_count=Count("likes__user", distinct=True),
				)
				.distinct()
				.order_by("-id")
			)
		except ProviderProfile.DoesNotExist:
			return ProviderProfile.objects.none()


class ProviderPublicStatsView(APIView):
	"""Public lightweight stats for a provider profile."""
	permission_classes = [permissions.AllowAny]

	def get(self, request, provider_id: int):
		role = get_active_role(request, fallback="client")

		from django.core.cache import cache as _cache

		cache_key = f"provider:{provider_id}:public_stats:{role}"
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
		followers_count = (
			ProviderFollow.objects.filter(provider_id=provider_id)
			.values("user_id")
			.distinct()
			.count()
		)
		following_count = (
			ProviderFollow.objects.filter(
				user=provider.user,
				role_context=role,
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

		payload = {
			"provider_id": provider_id,
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
			"rating_avg": getattr(provider, "rating_avg", 0) or 0,
			"rating_count": getattr(provider, "rating_count", 0) or 0,
		}
		_cache.set(cache_key, payload, 300)  # 5 minutes
		return Response(payload, status=status.HTTP_200_OK)


def _invalidate_provider_counters(provider_id: int) -> None:
	"""Delete cached follower/like counts so they are recalculated on next read."""
	from django.core.cache import cache as _cache
	_cache.delete_many([
		f"provider:{provider_id}:followers",
		f"provider:{provider_id}:likes",
		f"provider:{provider_id}:public_stats:client",
		f"provider:{provider_id}:public_stats:provider",
		f"provider:{provider_id}:public_stats:shared",
	])


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
