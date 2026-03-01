from rest_framework import generics, permissions, status
from rest_framework.exceptions import NotFound
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db.models import Count, F, Max, Q
from django.db.models.functions import Coalesce
from django.db import transaction

from apps.accounts.models import User

from apps.accounts.models import UserRole
from apps.accounts.permissions import IsAtLeastClient, IsAtLeastPhoneOnly, IsAtLeastProvider

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
	SubCategory,
)
from .serializers import (
	CategorySerializer,
	MyProviderSubcategoriesSerializer,
	SubCategoryWithCategorySerializer,
	ProviderServicePublicSerializer,
	ProviderServiceSerializer,
	ProviderPortfolioItemCreateSerializer,
	ProviderPortfolioItemSerializer,
	ProviderProfileSerializer,
	ProviderProfileMeSerializer,
	ProviderPublicSerializer,
	ProviderSpotlightItemCreateSerializer,
	ProviderSpotlightItemSerializer,
	UserPublicSerializer,
)
from .media_thumbnails import ensure_video_thumbnail


class MyProviderProfileView(generics.RetrieveUpdateAPIView):
	"""Get/update the current user's provider profile."""

	serializer_class = ProviderProfileMeSerializer
	permission_classes = [IsAtLeastClient]

	def get_object(self):
		provider_profile = getattr(self.request.user, "provider_profile", None)
		if not provider_profile:
			raise NotFound("provider_profile_not_found")
		return provider_profile


class MyProviderSubcategoriesView(APIView):
	"""Get/update the authenticated provider's service subcategories.

	Used by the mobile app to power provider inbox filtering.
	"""

	permission_classes = [IsAtLeastProvider]

	def get(self, request):
		provider = getattr(request.user, "provider_profile", None)
		if not provider:
			raise NotFound("provider_profile_not_found")

		ids = list(
			ProviderCategory.objects.filter(provider=provider)
			.values_list("subcategory_id", flat=True)
		)
		return Response({"subcategory_ids": ids}, status=status.HTTP_200_OK)

	def put(self, request):
		provider = getattr(request.user, "provider_profile", None)
		if not provider:
			raise NotFound("provider_profile_not_found")

		serializer = MyProviderSubcategoriesSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		ids = serializer.validated_data.get("subcategory_ids", [])

		with transaction.atomic():
			ProviderCategory.objects.filter(provider=provider).delete()
			if ids:
				ProviderCategory.objects.bulk_create(
					[ProviderCategory(provider=provider, subcategory_id=sid) for sid in ids]
				)

		# Return updated ids (normalized)
		return Response({"subcategory_ids": ids}, status=status.HTTP_200_OK)


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
			.select_related("subcategory", "subcategory__category")
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
			"subcategory", "subcategory__category"
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
	queryset = Category.objects.filter(is_active=True)
	serializer_class = CategorySerializer
	permission_classes = [permissions.AllowAny]


class ProviderCreateView(generics.CreateAPIView):
	serializer_class = ProviderProfileSerializer
	# Provider registration is allowed only after full basic registration
	# (CLIENT or above), matching product permission matrix.
	permission_classes = [IsAtLeastClient]

	def perform_create(self, serializer):
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
		if accepts_urgent in {"1", "true", "yes"}:
			qs = qs.filter(accepts_urgent=True)

		# Optional service taxonomy filters via ProviderCategory
		if subcategory_id:
			try:
				sid = int(subcategory_id)
				qs = qs.filter(providercategory__subcategory_id=sid)
			except ValueError:
				pass
		elif category_id:
			try:
				cid = int(category_id)
				sub_ids = list(
					SubCategory.objects.filter(category_id=cid, is_active=True).values_list("id", flat=True)
				)
				if sub_ids:
					qs = qs.filter(providercategory__subcategory_id__in=sub_ids)
			except ValueError:
				pass
		return qs.distinct()


class ProviderDetailView(generics.RetrieveAPIView):
	serializer_class = ProviderPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		from apps.marketplace.models import RequestStatus
		return (
			ProviderProfile.objects.select_related("user")
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
	"""Providers the current user follows."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		return (
			ProviderProfile.objects.filter(followers__user=self.request.user)
			.annotate(
				followers_count=Count("followers"),
				likes_count=Count("likes"),
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
		return (
			ProviderPortfolioItem.objects.filter(provider_id=provider_id)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.order_by("-created_at", "-id")
		)


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


class MyProviderPortfolioDetailView(generics.RetrieveDestroyAPIView):
	"""Provider-owned single portfolio item (retrieve/delete)."""

	permission_classes = [IsAtLeastProvider]
	serializer_class = ProviderPortfolioItemSerializer

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
		return (
			ProviderSpotlightItem.objects.filter(provider_id=provider_id)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.order_by("-created_at", "-id")
		)


class ProviderSpotlightFeedView(generics.ListAPIView):
	"""Public spotlight feed for the home page (latest across providers)."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		qs = (
			ProviderSpotlightItem.objects.select_related("provider", "provider__user")
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.order_by("-created_at", "-id")
		)

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
	"""Portfolio media the current user liked (Favorites: images/videos)."""

	serializer_class = ProviderPortfolioItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		return (
			ProviderPortfolioItem.objects.filter(likes__user=self.request.user)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class MySavedPortfolioItemsView(generics.ListAPIView):
	"""Portfolio media the current user saved (bookmarked)."""

	serializer_class = ProviderPortfolioItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		return (
			ProviderPortfolioItem.objects.filter(saves__user=self.request.user)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class MyLikedSpotlightItemsView(generics.ListAPIView):
	"""Spotlight media the current user liked."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		return (
			ProviderSpotlightItem.objects.filter(likes__user=self.request.user)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class MySavedSpotlightItemsView(generics.ListAPIView):
	"""Spotlight media the current user saved (bookmarked)."""

	serializer_class = ProviderSpotlightItemSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		return (
			ProviderSpotlightItem.objects.filter(saves__user=self.request.user)
			.annotate(likes_count=Count("likes", distinct=True))
			.annotate(saves_count=Count("saves", distinct=True))
			.select_related("provider", "provider__user")
			.distinct()
			.order_by("-created_at", "-id")
		)


class LikePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		item = generics.get_object_or_404(ProviderPortfolioItem, id=item_id)
		ProviderPortfolioLike.objects.get_or_create(user=request.user, item=item)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnlikePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		ProviderPortfolioLike.objects.filter(user=request.user, item_id=item_id).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class SavePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		item = generics.get_object_or_404(ProviderPortfolioItem, id=item_id)
		ProviderPortfolioSave.objects.get_or_create(user=request.user, item=item)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnsavePortfolioItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		ProviderPortfolioSave.objects.filter(user=request.user, item_id=item_id).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class LikeSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		item = generics.get_object_or_404(ProviderSpotlightItem, id=item_id)
		ProviderSpotlightLike.objects.get_or_create(user=request.user, item=item)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnlikeSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		ProviderSpotlightLike.objects.filter(user=request.user, item_id=item_id).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class SaveSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		item = generics.get_object_or_404(ProviderSpotlightItem, id=item_id)
		ProviderSpotlightSave.objects.get_or_create(user=request.user, item=item)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnsaveSpotlightItemView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, item_id: int):
		ProviderSpotlightSave.objects.filter(user=request.user, item_id=item_id).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class MyLikedProvidersView(generics.ListAPIView):
	"""Providers the current user liked (used as Favorites in the app)."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [IsAtLeastPhoneOnly]

	def get_queryset(self):
		return (
			ProviderProfile.objects.filter(likes__user=self.request.user)
			.annotate(followers_count=Count("followers"), likes_count=Count("likes"))
			.distinct()
			.order_by("-id")
		)


class MyProviderFollowersView(generics.ListAPIView):
	"""Users who follow the current user's provider profile (if exists)."""
	serializer_class = UserPublicSerializer
	permission_classes = [IsAtLeastProvider]

	def get_queryset(self):
		provider_profile = getattr(self.request.user, "provider_profile", None)
		if not provider_profile:
			return User.objects.none()

		user_ids = (
			ProviderFollow.objects.filter(provider=provider_profile)
			.values_list("user_id", flat=True)
			.distinct()
		)
		return (
			User.objects.filter(id__in=user_ids)
			.select_related("provider_profile")
			.order_by("-id")
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
	"""Public: Providers that a specific provider follows (if any)."""
	serializer_class = ProviderPublicSerializer
	permission_classes = [permissions.AllowAny]

	def get_queryset(self):
		provider_id = self.kwargs.get("provider_id")
		try:
			provider = ProviderProfile.objects.get(id=provider_id)
			user = provider.user
			return (
				ProviderProfile.objects.filter(followers__user=user)
				.annotate(
					followers_count=Count("followers"),
					likes_count=Count("likes"),
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
			ProviderFollow.objects.filter(user=provider.user)
			.values("provider_id")
			.distinct()
			.count()
		)
		likes_count = (
			ProviderLike.objects.filter(provider_id=provider_id)
			.values("user_id")
			.distinct()
			.count()
		)

		return Response(
			{
				"provider_id": provider_id,
				"completed_requests": completed_requests,
				"followers_count": followers_count,
				"following_count": following_count,
				"likes_count": likes_count,
				"rating_avg": getattr(provider, "rating_avg", 0) or 0,
				"rating_count": getattr(provider, "rating_count", 0) or 0,
			},
			status=status.HTTP_200_OK,
		)


class FollowProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		provider = generics.get_object_or_404(ProviderProfile, id=provider_id)
		ProviderFollow.objects.get_or_create(user=request.user, provider=provider)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnfollowProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		ProviderFollow.objects.filter(user=request.user, provider_id=provider_id).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)


class LikeProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		provider = generics.get_object_or_404(ProviderProfile, id=provider_id)
		ProviderLike.objects.get_or_create(user=request.user, provider=provider)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class UnlikeProviderView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, provider_id: int):
		ProviderLike.objects.filter(user=request.user, provider_id=provider_id).delete()
		return Response({"ok": True}, status=status.HTTP_200_OK)
