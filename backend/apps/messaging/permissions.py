from rest_framework.permissions import BasePermission

from apps.accounts.role_context import get_active_role
from apps.marketplace.models import ServiceRequest

from .models import Thread


class IsRequestParticipant(BasePermission):
    """
    يسمح فقط لمالك الطلب أو المزوّد المعيّن على الطلب
    """

    def has_permission(self, request, view):
        request_id = view.kwargs.get("request_id")
        if not request_id:
            return True  # لبعض الـ views التي تستخدم thread_id لاحقًا

        sr = (
            ServiceRequest.objects.filter(id=request_id)
            .select_related("client", "provider__user")
            .first()
        )
        if not sr:
            return False

        active_mode = get_active_role(request, fallback="shared")

        if sr.client_id == request.user.id and active_mode in {"shared", "client"}:
            return True

        # provider__user هو صاحب حساب مقدم الخدمة
        if sr.provider and sr.provider.user_id == request.user.id and active_mode in {"shared", "provider"}:
            return True

        return False


class IsThreadParticipant(BasePermission):
    """Allows only participants of a thread (direct or request-based)."""

    def has_permission(self, request, view):
        thread_id = view.kwargs.get("thread_id")
        if not thread_id:
            return True

        thread = (
            Thread.objects.select_related("request", "request__client", "request__provider__user", "participant_1", "participant_2")
            .filter(id=thread_id)
            .first()
        )
        if not thread:
            return False

        active_mode = get_active_role(request, fallback="shared")

        if thread.is_direct:
            return bool(thread.is_participant(request.user) and thread.mode_matches_user(request.user, active_mode))

        if active_mode == "client":
            return bool(thread.request_id and thread.request and thread.request.client_id == request.user.id)

        if active_mode == "provider":
            return bool(
                thread.request_id
                and thread.request
                and thread.request.provider_id
                and thread.request.provider.user_id == request.user.id
            )

        return bool(thread.is_participant(request.user))
