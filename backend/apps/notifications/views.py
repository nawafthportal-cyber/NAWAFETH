from datetime import timedelta
import re

from django.conf import settings
from django.db.models import Case, IntegerField, Value, When
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.views import APIView
from rest_framework.response import Response

from .models import Notification, DeviceToken
from .pagination import NotificationPagination
from .serializers import (
    NotificationSerializer,
    DeviceTokenSerializer,
)
from .services import (
    NOTIFICATION_CATALOG,
    get_or_create_notification_preferences,
    _is_pref_locked,
    _notification_entitlement_context,
    notification_preference_availability,
    notification_tier_to_canonical,
    normalize_preference_mode,
)

from apps.accounts.permissions import IsAtLeastClient, IsAtLeastPhoneOnly
from apps.marketplace.models import ServiceRequest
from apps.messaging.models import Thread


_REQUEST_URL_RE = re.compile(r"/requests/(?P<id>\d+)(?:/|$)")
_THREAD_URL_RE = re.compile(r"/threads?/(?P<id>\d+)(?:/|$)")


_CLIENT_ONLY_KINDS = {
    "offer_created",
    "review_reply",
}
_PROVIDER_ONLY_KINDS = {
    "urgent_request",
    "offer_selected",
}


def _preferred_preferences_for_mode(*, prefs, mode: str):
    if mode not in {"client", "provider"}:
        priority = {"shared": 0, "provider": 1, "client": 2}
        selected = {}
        for pref in prefs:
            current = selected.get(pref.key)
            if current is None or priority.get(pref.audience_mode, 99) < priority.get(current.audience_mode, 99):
                selected[pref.key] = pref
        return list(selected.values())

    selected = {}
    for pref in prefs:
        if pref.audience_mode not in {mode, "shared"}:
            continue
        current = selected.get(pref.key)
        if current is None or (current.audience_mode == "shared" and pref.audience_mode == mode):
            selected[pref.key] = pref
    return list(selected.values())


def _serialize_preferences_for_response(*, user, prefs, mode: str):
    data = []
    entitlement_context = _notification_entitlement_context(user)
    for pref in _preferred_preferences_for_mode(prefs=prefs, mode=mode):
        cfg = NOTIFICATION_CATALOG.get(pref.key, {})
        availability = notification_preference_availability(
            user=user,
            pref_key=pref.key,
            audience_mode=pref.audience_mode,
            context=entitlement_context,
        )
        data.append(
            {
                "key": pref.key,
                "title": cfg.get("title", pref.key),
                "enabled": bool(pref.enabled),
                "tier": pref.tier,
                "canonical_tier": notification_tier_to_canonical(pref.tier),
                "audience_mode": pref.audience_mode,
                "locked": bool(availability["locked"]),
                "locked_reason": str(availability["reason"] or ""),
                "updated_at": pref.updated_at,
            }
        )
    return data


def _notification_matches_mode(*, notif: Notification, user, mode: str) -> bool:
    mode = (mode or "").strip().lower()
    if mode not in {"client", "provider"}:
        return True

    audience_mode = (getattr(notif, "audience_mode", "") or "").strip().lower()
    if audience_mode in {"client", "provider"}:
        return audience_mode == mode
    if audience_mode == "shared":
        # Continue to heuristic fallback for legacy/shared notifications that may
        # still carry request/thread URLs and can be isolated more accurately.
        pass

    kind = (notif.kind or "").strip().lower()
    if kind in _CLIENT_ONLY_KINDS:
        return mode == "client"
    if kind in _PROVIDER_ONLY_KINDS:
        return mode == "provider"

    # Shared/system notifications remain visible in both modes.
    if kind in {"report_status_change", "info", "urgent"}:
        return True

    url = (notif.url or "").strip()
    if not url:
        return True

    m_req = _REQUEST_URL_RE.search(url)
    if m_req:
        request_id = int(m_req.group("id"))
        sr = (
            ServiceRequest.objects.select_related("provider__user")
            .filter(id=request_id)
            .first()
        )
        if sr is None:
            return True
        if mode == "client":
            return sr.client_id == user.id
        return bool(sr.provider_id and sr.provider.user_id == user.id)

    m_thread = _THREAD_URL_RE.search(url)
    if m_thread:
        thread_id = int(m_thread.group("id"))
        thread = (
            Thread.objects.select_related("request", "request__provider__user")
            .filter(id=thread_id)
            .first()
        )
        if thread is None:
            return True
        if thread.is_direct:
            # Direct threads are shared between both account contexts.
            return user.id in {thread.participant_1_id, thread.participant_2_id}
        sr = thread.request
        if sr is None:
            return True
        if mode == "client":
            return sr.client_id == user.id
        return bool(sr.provider_id and sr.provider.user_id == user.id)

    return True


def _filter_notification_ids_by_mode(*, qs, user, mode: str):
    mode = (mode or "").strip().lower()
    if mode not in {"client", "provider"}:
        return None
    ids = []
    for notif in qs.only("id", "kind", "url", "audience_mode").iterator():
        # Include audience_mode when available (new schema).
        if _notification_matches_mode(notif=notif, user=user, mode=mode):
            ids.append(notif.id)
    return ids


class MyNotificationsView(generics.ListAPIView):
    permission_classes = [IsAtLeastPhoneOnly]
    serializer_class = NotificationSerializer
    pagination_class = NotificationPagination

    def get_queryset(self):
        qs = (
            Notification.objects.filter(user=self.request.user)
            .annotate(
                _sort_priority=Case(
                    When(is_pinned=True, then=Value(2)),
                    When(is_urgent=True, then=Value(1)),
                    default=Value(0),
                    output_field=IntegerField(),
                )
            )
            .order_by("-_sort_priority", "-id")
        )
        mode = (self.request.query_params.get("mode") or "").strip().lower()
        ids = _filter_notification_ids_by_mode(qs=qs, user=self.request.user, mode=mode)
        if ids is None:
            return qs
        return qs.filter(id__in=ids)


class UnreadCountView(APIView):
    permission_classes = [IsAtLeastPhoneOnly]

    def get(self, request):
        qs = Notification.objects.filter(user=request.user, is_read=False).order_by("-id")
        mode = (request.query_params.get("mode") or "").strip().lower()
        ids = _filter_notification_ids_by_mode(qs=qs, user=request.user, mode=mode)
        count = qs.count() if ids is None else len(ids)
        return Response({"unread": count}, status=status.HTTP_200_OK)


class MarkReadView(APIView):
    permission_classes = [IsAtLeastPhoneOnly]

    def post(self, request, notif_id):
        updated = Notification.objects.filter(id=notif_id, user=request.user).update(
            is_read=True
        )
        if not updated:
            return Response({"detail": "غير موجود"}, status=status.HTTP_404_NOT_FOUND)
        return Response({"ok": True}, status=status.HTTP_200_OK)


class MarkAllReadView(APIView):
    permission_classes = [IsAtLeastPhoneOnly]

    def post(self, request):
        Notification.objects.filter(user=request.user, is_read=False).update(is_read=True)
        return Response({"ok": True}, status=status.HTTP_200_OK)


class NotificationActionView(APIView):
    permission_classes = [IsAtLeastPhoneOnly]

    def post(self, request, notif_id: int):
        action = (request.data.get("action") or "").strip().lower()
        notif = Notification.objects.filter(id=notif_id, user=request.user).first()
        if not notif:
            return Response({"detail": "غير موجود"}, status=status.HTTP_404_NOT_FOUND)

        if action == "pin":
            notif.is_pinned = not notif.is_pinned
            notif.save(update_fields=["is_pinned"])
            return Response({"ok": True, "is_pinned": notif.is_pinned}, status=status.HTTP_200_OK)

        if action == "follow_up":
            notif.is_follow_up = not notif.is_follow_up
            notif.save(update_fields=["is_follow_up"])
            return Response({"ok": True, "is_follow_up": notif.is_follow_up}, status=status.HTTP_200_OK)

        return Response({"detail": "إجراء غير مدعوم"}, status=status.HTTP_400_BAD_REQUEST)

    def delete(self, request, notif_id: int):
        deleted, _ = Notification.objects.filter(id=notif_id, user=request.user).delete()
        if not deleted:
            return Response({"detail": "غير موجود"}, status=status.HTTP_404_NOT_FOUND)
        return Response({"ok": True}, status=status.HTTP_200_OK)


class NotificationPreferencesView(APIView):
    permission_classes = [IsAtLeastPhoneOnly]

    def get(self, request):
        mode = normalize_preference_mode(request.query_params.get("mode"))
        prefs = get_or_create_notification_preferences(request.user, mode=mode, exposed_only=True)
        data = _serialize_preferences_for_response(user=request.user, prefs=prefs, mode=mode)
        return Response({"results": data}, status=status.HTTP_200_OK)

    def patch(self, request):
        mode = normalize_preference_mode(request.query_params.get("mode"))
        prefs = get_or_create_notification_preferences(request.user, mode=mode, exposed_only=True)
        by_key = {pref.key: pref for pref in _preferred_preferences_for_mode(prefs=prefs, mode=mode)}
        updates = request.data.get("updates") or []
        if not isinstance(updates, list):
            return Response({"detail": "صيغة updates غير صحيحة"}, status=status.HTTP_400_BAD_REQUEST)

        changed = 0
        for raw in updates:
            if not isinstance(raw, dict):
                continue
            key = (raw.get("key") or "").strip()
            if not key or key not in by_key:
                continue
            enabled = raw.get("enabled")
            if not isinstance(enabled, bool):
                continue
            obj = by_key[key]
            if _is_pref_locked(request.user, key, obj.audience_mode):
                continue
            if obj.enabled == enabled:
                continue
            obj.enabled = enabled
            obj.save(update_fields=["enabled", "updated_at"])
            changed += 1

        refreshed = get_or_create_notification_preferences(request.user, mode=mode, exposed_only=True)
        return Response(
            {
                "ok": True,
                "changed": changed,
                "results": _serialize_preferences_for_response(user=request.user, prefs=refreshed, mode=mode),
            },
            status=status.HTTP_200_OK,
        )


class RegisterDeviceTokenView(APIView):
	"""
	يسجّل توكن FCM للجوال. (للاستخدام لاحقًا)
	"""

	permission_classes = [IsAtLeastClient]

	def post(self, request):
		s = DeviceTokenSerializer(data=request.data)
		s.is_valid(raise_exception=True)
		token = s.validated_data["token"]
		platform = s.validated_data["platform"]

		DeviceToken.objects.update_or_create(
			token=token,
			defaults={
				"user": request.user,
				"platform": platform,
				"is_active": True,
				"last_seen_at": timezone.now(),
			},
		)
		return Response({"ok": True}, status=status.HTTP_200_OK)


class DeleteOldNotificationsView(APIView):
	permission_classes = [IsAtLeastClient]

	def post(self, request):
		days = getattr(settings, "NOTIFICATIONS_RETENTION_DAYS", 90)
		cutoff = timezone.now() - timedelta(days=days)

		deleted, _ = Notification.objects.filter(
			user=request.user,
			created_at__lt=cutoff,
		).delete()

		return Response(
			{"ok": True, "deleted": deleted, "retention_days": days},
			status=status.HTTP_200_OK,
		)
