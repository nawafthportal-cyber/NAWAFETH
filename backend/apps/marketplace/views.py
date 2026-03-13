"""
Django template views for the marketplace app (HTML dashboard pages).

DRF API views (JSON endpoints for Flutter) live in api.py.
"""
import logging
from typing import Optional

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator
from django.db.models import Q
from django.utils import timezone
from django.shortcuts import redirect, render, get_object_or_404
from django.views.decorators.csrf import csrf_protect
from django.views.decorators.http import require_POST
from django.core.exceptions import PermissionDenied, ValidationError

from apps.providers.models import ProviderCategory, ProviderProfile

from .models import (
	RequestStatus,
	RequestType,
	ServiceRequest,
)

from apps.marketplace.services.actions import allowed_actions, execute_action


logger = logging.getLogger(__name__)



def _normalize_status_group(value: str) -> Optional[str]:
	v = (value or "").strip().lower()
	if not v:
		return None

	# English codes
	if v in {"new", "in_progress", "completed", "cancelled"}:
		return v

	# Common variants
	if v in {"canceled", "cancel", "cancelled"}:
		return "cancelled"

	# Arabic labels (mobile/UI)
	ar_map = {
		"جديد": "new",
		"تحت التنفيذ": "in_progress",
		"مكتمل": "completed",
		"ملغي": "cancelled",
	}
	return ar_map.get(value.strip())


def _status_group_to_statuses(group: str) -> list[str]:
	# Map unified user-facing groups to internal statuses.
	return {
		"new": [RequestStatus.NEW],
		"in_progress": [RequestStatus.IN_PROGRESS],
		"completed": [RequestStatus.COMPLETED],
		"cancelled": [RequestStatus.CANCELLED],
	}[group]


def _expire_urgent_requests() -> None:
	"""No-op: urgent requests no longer auto-expire."""
	pass



# ────────────────────────────────────────────────
# Django template views (HTML dashboard)
# ────────────────────────────────────────────────

@login_required
def request_detail(request, request_id: int):
	obj = get_object_or_404(
		ServiceRequest.objects.select_related("client", "provider", "provider__user"),
		id=request_id,
	)

	provider_profile = ProviderProfile.objects.filter(user=request.user).first()

	# صلاحية عرض بسيطة: staff أو العميل أو المزوّد المعيّن
	if not getattr(request.user, "is_staff", False):
		is_client = obj.client_id == request.user.id
		is_provider = bool(obj.provider_id) and (obj.provider.user_id == request.user.id)
		if not (is_client or is_provider):
			raise PermissionDenied

	acts = allowed_actions(request.user, obj, has_provider_profile=(provider_profile is not None))

	context = {
		"obj": obj,
		"can_cancel": "cancel" in acts,
		"can_accept": "accept" in acts,
		"can_start": "start" in acts,
		"can_complete": "complete" in acts,
		"can_reopen": "reopen" in acts,
	}
	return render(request, "marketplace/request_detail.html", context)


@login_required
@require_POST
@csrf_protect
def request_action(request, request_id: int):
	sr = get_object_or_404(ServiceRequest, id=request_id)

	action = (request.POST.get("action") or "").strip()

	provider_profile = None
	try:
		provider_profile = ProviderProfile.objects.filter(user=request.user).first()

		result = execute_action(
			user=request.user,
			request_id=sr.id,
			action=action,
			provider_profile=provider_profile,
		)
		messages.success(request, result.message)

	except PermissionDenied:
		messages.error(request, "غير مصرح بتنفيذ هذا الإجراء")
	except ValidationError as e:
		msg = None
		if hasattr(e, "messages") and e.messages:
			msg = e.messages[0]
		elif hasattr(e, "message"):
			msg = e.message
		messages.warning(request, msg or "لا يمكن تنفيذ الإجراء")
	except Exception:
		logger.exception("marketplace request_action error")
		messages.error(request, "حدث خطأ غير متوقع")

	return redirect("marketplace:request_detail", request_id=sr.id)


@login_required
def provider_requests(request):
	"""
	Provider dashboard (marketplace side):
	- tab=available: SENT requests provider can accept
	- tab=assigned: requests assigned to this provider
	- tab=all: staff-only, all requests
	"""
	user = request.user
	provider = ProviderProfile.objects.select_related("user").filter(user=user).first()

	# إذا المستخدم ليس مزودًا
	if not provider and not getattr(user, "is_staff", False):
		return render(request, "marketplace/provider_not_found.html", status=403)

	tab = (request.GET.get("tab") or "available").strip().lower()
	q = (request.GET.get("q") or "").strip()
	city = (request.GET.get("city") or "").strip()
	status = (request.GET.get("status") or "").strip().lower()
	page = request.GET.get("page") or "1"

	qs = (
		ServiceRequest.objects.select_related("client", "provider", "provider__user", "subcategory")
		.prefetch_related("subcategories")
		.order_by("-id")
	)

	# staff: يرى كل شيء فقط عند tab=all
	if getattr(user, "is_staff", False) and tab == "all":
		pass
	else:
		if tab == "assigned":
			if provider:
				qs = qs.filter(provider=provider)
			else:
				# staff without provider profile: show assigned requests
				qs = qs.filter(provider__isnull=False)
		else:
			# available
			qs = qs.filter(status=RequestStatus.NEW, provider__isnull=True)

			# فلترة حسب subcategories المزود عبر ProviderCategory
			if provider:
				sub_ids = list(
					ProviderCategory.objects.filter(provider=provider).values_list(
						"subcategory_id",
						flat=True,
					)
				)
				if sub_ids:
					qs = qs.filter(Q(subcategory_id__in=sub_ids) | Q(subcategories__id__in=sub_ids)).distinct()

	# فلاتر آمنة
	if q:
		qs = qs.filter(Q(title__icontains=q) | Q(description__icontains=q))
	if city:
		qs = qs.filter(city__icontains=city)
	if status:
		valid = {c[0] for c in RequestStatus.choices}
		if status in valid:
			qs = qs.filter(status=status)

	paginator = Paginator(qs, 12)
	page_obj = paginator.get_page(page)

	context = {
		"tab": tab,
		"q": q,
		"city": city,
		"status": status,
		"page_obj": page_obj,
		"provider": provider,
	}
	return render(request, "marketplace/provider_requests.html", context)
