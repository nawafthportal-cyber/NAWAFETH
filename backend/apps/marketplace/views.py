"""
Django template views for the marketplace app (HTML dashboard pages).

DRF API views (JSON endpoints for Flutter) live in api.py.
"""
from datetime import timedelta
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

from apps.providers.location_formatter import city_matches_scope, provider_city_query_values
from apps.providers.models import ProviderCategory, ProviderProfile
from apps.subscriptions.capabilities import (
	competitive_request_delay_for_user,
	competitive_requests_enabled_for_user,
	urgent_requests_enabled_for_user,
)
from apps.subscriptions.services import user_has_active_subscription

from .models import (
	DispatchStatus,
	PRE_EXECUTION_REQUEST_STATUSES,
	RequestStatus,
	RequestStatusLog,
	RequestType,
	ServiceRequest,
	ServiceRequestDispatch,
	request_status_group_value,
	service_request_status_label,
)

from apps.marketplace.services.actions import allowed_actions, execute_action
from apps.marketplace.services.dispatch import (
	clear_urgent_request_provider_notifications,
	provider_can_access_urgent_request,
	provider_dispatch_tier,
)


logger = logging.getLogger(__name__)



def _normalize_status_group(value: str) -> Optional[str]:
	v = (value or "").strip().lower()
	if not v:
		return None

	# English codes
	if v in {"new", "in_progress", "completed", "cancelled"}:
		return v
	if v in {status.value for status in PRE_EXECUTION_REQUEST_STATUSES}:
		return "new"

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
		"new": list(PRE_EXECUTION_REQUEST_STATUSES),
		"in_progress": [RequestStatus.IN_PROGRESS],
		"completed": [RequestStatus.COMPLETED],
		"cancelled": [RequestStatus.CANCELLED],
	}[group]


def _expire_urgent_requests() -> None:
	"""No-op: urgent requests no longer auto-expire."""
	pass


def _request_subcategory_ids(service_request: ServiceRequest) -> list[int]:
	try:
		return service_request.selected_subcategory_ids()
	except Exception:
		if getattr(service_request, "subcategory_id", None):
			return [service_request.subcategory_id]
		return []


def _provider_matches_request_scope(provider: ProviderProfile, service_request: ServiceRequest) -> bool:
	if not city_matches_scope(
		getattr(service_request, "city", "") or "",
		provider_city=getattr(provider, "city", "") or "",
		provider_region=getattr(provider, "region", "") or "",
	):
		return False
	return ProviderCategory.objects.filter(
		provider=provider,
		subcategory_id__in=_request_subcategory_ids(service_request),
	).exists()


def _provider_can_access_competitive_request(provider: ProviderProfile, service_request: ServiceRequest, *, now=None) -> bool:
	if not competitive_requests_enabled_for_user(provider.user):
		return False
	delay = competitive_request_delay_for_user(provider.user)
	if delay.total_seconds() <= 0:
		return True
	created_at = getattr(service_request, "created_at", None)
	if created_at is None:
		return False
	return created_at + delay <= (now or timezone.now())


def _can_provider_view_available_request(provider: ProviderProfile, service_request: ServiceRequest, *, now=None) -> bool:
	if service_request.provider_id is not None:
		return False
	if service_request.status != RequestStatus.NEW:
		return False
	if service_request.request_type == RequestType.NORMAL:
		return False
	if not user_has_active_subscription(provider.user):
		return False
	if not _provider_matches_request_scope(provider, service_request):
		return False
	if service_request.request_type == RequestType.URGENT:
		if not provider.accepts_urgent:
			return False
		if not urgent_requests_enabled_for_user(provider.user):
			return False
		return provider_can_access_urgent_request(provider, service_request, now=now)
	if service_request.request_type == RequestType.COMPETITIVE:
		return _provider_can_access_competitive_request(provider, service_request, now=now)
	return False


def _provider_available_request_ids(provider: ProviderProfile, *, now=None) -> list[int]:
	if not user_has_active_subscription(provider.user):
		return []

	now = now or timezone.now()
	provider_subcategories = list(
		ProviderCategory.objects.filter(provider=provider).values_list("subcategory_id", flat=True)
	)
	if not provider_subcategories:
		return []

	base_qs = (
		ServiceRequest.objects.filter(
			status=RequestStatus.NEW,
			provider__isnull=True,
		)
		.exclude(request_type=RequestType.NORMAL)
		.filter(
			Q(subcategory_id__in=provider_subcategories)
			| Q(subcategories__id__in=provider_subcategories)
		)
		.filter(
			Q(
				city__in=provider_city_query_values(
					getattr(provider, "city", "") or "",
					provider_region=getattr(provider, "region", "") or "",
				)
			)
			| Q(city="")
		)
		.distinct()
	)

	urgent_ids: list[int] = []
	if provider.accepts_urgent and urgent_requests_enabled_for_user(provider.user):
		provider_tier = provider_dispatch_tier(provider)
		if provider_tier:
			ready_request_ids = ServiceRequestDispatch.objects.filter(
				dispatch_tier=provider_tier,
				dispatch_status__in=[
					DispatchStatus.PENDING,
					DispatchStatus.READY,
					DispatchStatus.DISPATCHED,
				],
				available_at__lte=now,
			).values_list("request_id", flat=True)
			urgent_rows = list(
				base_qs.filter(request_type=RequestType.URGENT)
				.filter(Q(id__in=ready_request_ids) | Q(dispatch_windows__isnull=True))
			)
			urgent_ids = [
				request_row.id
				for request_row in urgent_rows
				if provider_can_access_urgent_request(provider, request_row, now=now)
			]

	competitive_ids: list[int] = []
	if competitive_requests_enabled_for_user(provider.user):
		competitive_qs = base_qs.filter(request_type=RequestType.COMPETITIVE)
		delay = competitive_request_delay_for_user(provider.user)
		if delay.total_seconds() > 0:
			competitive_qs = competitive_qs.filter(created_at__lte=now - delay)
		competitive_ids = list(competitive_qs.values_list("id", flat=True))

	return list(dict.fromkeys([*urgent_ids, *competitive_ids]))


def _accept_provider_request_from_legacy_html(*, provider: ProviderProfile, actor, service_request: ServiceRequest) -> str:
	if service_request.request_type == RequestType.COMPETITIVE:
		raise ValidationError("هذا الطلب تنافسي ويتم التعامل معه عبر العروض.")
	if service_request.status != RequestStatus.NEW:
		raise ValidationError("لا يمكن قبول الطلب في هذه الحالة")

	if service_request.provider_id == provider.id:
		old = service_request.status
		service_request.accept(provider)
		if service_request.request_type == RequestType.URGENT:
			clear_urgent_request_provider_notifications(service_request)
		RequestStatusLog.objects.create(
			request=service_request,
			actor=actor,
			from_status=old,
			to_status=service_request.status,
			note="قبول من المزود بانتظار إرسال تفاصيل التنفيذ",
		)
		return "تم تسجيل قبول الطلب بانتظار إرسال تفاصيل التنفيذ."

	if service_request.provider_id is not None:
		raise PermissionDenied("غير مصرح")
	if service_request.request_type != RequestType.URGENT:
		raise PermissionDenied("غير مصرح")
	if not provider.accepts_urgent:
		raise ValidationError("هذا المزود لا يقبل الطلبات العاجلة")
	if not urgent_requests_enabled_for_user(provider.user):
		raise ValidationError("الطلبات العاجلة تتطلب اشتراكًا فعالًا في إحدى الباقات.")
	if not _provider_matches_request_scope(provider, service_request):
		raise ValidationError("هذا الطلب لا يطابق نطاق تخصصك أو مدينتك")

	now = timezone.now()
	if not provider_can_access_urgent_request(provider, service_request, now=now):
		raise ValidationError("هذا الطلب لم يصبح متاحًا لباقتك بعد")

	service_request.accept(provider)
	clear_urgent_request_provider_notifications(service_request)
	RequestStatusLog.objects.create(
		request=service_request,
		actor=actor,
		from_status=RequestStatus.NEW,
		to_status=service_request.status,
		note="تم قبول الطلب العاجل من مزود الخدمة بانتظار إرسال تفاصيل التنفيذ",
	)
	return "تم قبول الطلب العاجل بانتظار إرسال تفاصيل التنفيذ."


def _status_label_ar(raw_status: str) -> str:
	class _StatusProxy:
		status = raw_status
		request_type = ""
		provider_id = None
		provider = None

	return service_request_status_label(_StatusProxy())


def _request_type_label(service_request: ServiceRequest) -> str:
	try:
		label = service_request.get_request_type_display()
	except Exception:
		label = ""
	value = (label or getattr(service_request, "request_type", "") or "").strip()
	return value or "طلب"


def _request_workflow_note(service_request: ServiceRequest) -> str:
	status = (getattr(service_request, "status", "") or "").strip().lower()
	request_type = (getattr(service_request, "request_type", "") or "").strip().lower()
	has_provider = bool(getattr(service_request, "provider_id", None) or getattr(service_request, "provider", None))

	if status == RequestStatus.NEW:
		if request_type == RequestType.NORMAL and has_provider:
			return "الطلب محفوظ وموجّه للمزوّد المحدد بانتظار قبوله قبل إدخال تفاصيل التنفيذ."
		if request_type == RequestType.COMPETITIVE:
			return "الطلب مفتوح حالياً لاستقبال عروض الأسعار من المزوّدين المؤهلين حتى اختيار العرض المناسب."
		if request_type == RequestType.URGENT:
			return "الطلب متاح للمزوّدين المؤهلين وفق باقاتهم ونطاق التغطية، مع أولوية أعلى للظهور السريع."
		return "الطلب جديد ولم يبدأ التنفيذ بعد."
	if status == RequestStatus.PROVIDER_ACCEPTED:
		return "تم قبول الطلب من المزوّد، والخطوة التالية هي إرسال تفاصيل التنفيذ المالية والزمنية إلى العميل."
	if status == RequestStatus.AWAITING_CLIENT_APPROVAL:
		return "تمت مشاركة تفاصيل التنفيذ، والطلب الآن بانتظار اعتماد العميل أو طلب التعديل قبل البدء."
	if status == RequestStatus.IN_PROGRESS:
		return "تم اعتماد التفاصيل وبدأ التنفيذ. استمر في متابعة المرفقات والتحديثات حتى التسليم."
	if status == RequestStatus.COMPLETED:
		return "أُغلق الطلب كمكتمل ويمكن الرجوع إلى المرفقات وسجل الحالة والتقييمات عند الحاجة."
	if status == RequestStatus.CANCELLED:
		return "تم إلغاء الطلب، ويمكن مراجعة سبب الإلغاء وسجل التغييرات لمعرفة ما حدث."
	return "راجع سجل الحالة للتأكد من المرحلة الحالية لهذا الطلب."


def _decorate_dashboard_request(service_request: ServiceRequest, *, can_accept_legacy: bool = False) -> ServiceRequest:
	service_request.status_label = service_request_status_label(service_request)
	service_request.status_group = request_status_group_value(getattr(service_request, "status", ""))
	service_request.type_label = _request_type_label(service_request)
	service_request.workflow_note = _request_workflow_note(service_request)
	service_request.can_accept_legacy = can_accept_legacy
	service_request.city_label = (getattr(service_request, "city", "") or "").strip() or "كل المدن"
	return service_request


def _attachment_type_label(raw_type: str) -> str:
	value = (raw_type or "").strip().lower()
	labels = {
		"image": "صورة",
		"video": "فيديو",
		"audio": "صوت",
		"document": "مستند",
		"invoice": "فاتورة",
	}
	return labels.get(value, "ملف")


def _actor_display_name(actor) -> str:
	if not actor:
		return "النظام"
	full = f"{(getattr(actor, 'first_name', '') or '').strip()} {(getattr(actor, 'last_name', '') or '').strip()}".strip()
	if full:
		return full
	username = (getattr(actor, "username", "") or "").strip()
	if username:
		return username
	phone = (getattr(actor, "phone", "") or "").strip()
	return phone or "النظام"


def _attachment_vm(att) -> dict:
	file_name = "ملف"
	file_url = ""
	try:
		raw_name = (att.file.name or "").strip()
		if raw_name:
			file_name = raw_name.split("/")[-1] or file_name
	except Exception:
		raw_name = ""
	try:
		file_url = att.file.url
	except Exception:
		file_url = ""

	return {
		"id": getattr(att, "id", None),
		"name": file_name,
		"url": file_url,
		"type_label": _attachment_type_label(getattr(att, "file_type", "")),
		"created_at": getattr(att, "created_at", None),
	}


def _split_attachments_for_detail(sr: ServiceRequest, attachments: list) -> tuple[list, list]:
	if not attachments:
		return [], []

	completion_log_at = None
	for log in sr.status_logs.all():
		if (getattr(log, "to_status", "") or "").strip().lower() == RequestStatus.COMPLETED:
			completion_log_at = getattr(log, "created_at", None)
			break

	delivered_at = getattr(sr, "delivered_at", None)
	if completion_log_at and delivered_at:
		cutoff = completion_log_at if completion_log_at <= delivered_at else delivered_at
	else:
		cutoff = completion_log_at or delivered_at

	completion_window = timedelta(minutes=2)
	creation_grace = timedelta(minutes=5)
	request_created_at = getattr(sr, "created_at", None)
	completion_state = (getattr(sr, "status", "") or "").strip().lower() == RequestStatus.COMPLETED

	regular, completion = [], []
	for att in attachments:
		created_at = getattr(att, "created_at", None)
		is_completion_attachment = False

		if completion_state and cutoff and created_at:
			is_completion_attachment = created_at >= (cutoff - completion_window)
		elif completion_state and request_created_at and created_at:
			is_completion_attachment = created_at > (request_created_at + creation_grace)

		if is_completion_attachment:
			completion.append(att)
		else:
			regular.append(att)

	if not completion and completion_state and request_created_at:
		inferred = [
			att
			for att in regular
			if getattr(att, "created_at", None) and getattr(att, "created_at") > (request_created_at + creation_grace)
		]
		if inferred:
			inferred_ids = {getattr(att, "id", None) for att in inferred}
			completion = inferred
			regular = [att for att in regular if getattr(att, "id", None) not in inferred_ids]

	regular.sort(key=lambda att: getattr(att, "created_at", None) or timezone.now(), reverse=True)
	completion.sort(key=lambda att: getattr(att, "created_at", None) or timezone.now(), reverse=True)
	return regular, completion



# ────────────────────────────────────────────────
# Django template views (HTML dashboard)
# ────────────────────────────────────────────────

@login_required
def request_detail(request, request_id: int):
	obj = get_object_or_404(
		ServiceRequest.objects.select_related("client", "provider", "provider__user")
		.prefetch_related("attachments", "status_logs", "status_logs__actor"),
		id=request_id,
	)

	provider_profile = ProviderProfile.objects.filter(user=request.user).first()
	now = timezone.now()

	# صلاحية عرض بسيطة: staff أو العميل أو المزوّد المعيّن
	if not getattr(request.user, "is_staff", False):
		is_client = obj.client_id == request.user.id
		is_provider = bool(obj.provider_id) and (obj.provider.user_id == request.user.id)
		can_view_as_available_provider = bool(
			provider_profile
			and _can_provider_view_available_request(provider_profile, obj, now=now)
		)
		if not (is_client or is_provider or can_view_as_available_provider):
			raise PermissionDenied

	acts = allowed_actions(request.user, obj, has_provider_profile=(provider_profile is not None))

	attachments = list(obj.attachments.all())
	request_attachments, completion_attachments = _split_attachments_for_detail(obj, attachments)

	status_rows = []
	for log in obj.status_logs.all():
		from_status = (getattr(log, "from_status", "") or "").strip().lower()
		to_status = (getattr(log, "to_status", "") or "").strip().lower()
		same_status = from_status == to_status
		status_rows.append(
			{
				"from_label": _status_label_ar(getattr(log, "from_status", "")),
				"to_label": _status_label_ar(getattr(log, "to_status", "")),
				"same_status": same_status,
				"note": (getattr(log, "note", "") or "").strip(),
				"created_at": getattr(log, "created_at", None),
				"actor_name": _actor_display_name(getattr(log, "actor", None)),
			}
		)

	context = {
		"obj": obj,
		"can_send": "send" in acts,
		"can_cancel": "cancel" in acts,
		"can_accept": "accept" in acts,
		"can_start": "start" in acts,
		"can_complete": "complete" in acts,
		"can_reopen": "reopen" in acts,
		"status_label": service_request_status_label(obj),
		"status_group": request_status_group_value(obj.status),
		"request_type_label": _request_type_label(obj),
		"workflow_note": _request_workflow_note(obj),
		"attachment_total": len(request_attachments) + len(completion_attachments),
		"request_attachments": [_attachment_vm(att) for att in request_attachments],
		"completion_attachments": [_attachment_vm(att) for att in completion_attachments],
		"status_log_rows": status_rows,
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

		if provider_profile is not None and not getattr(request.user, "is_staff", False):
			if action != "accept":
				raise ValidationError("هذه الصفحة لا تدعم إلا تسجيل قبول الطلب. بقية الإجراءات تتم عبر المسار الحديث للطلبات.")
			message = _accept_provider_request_from_legacy_html(
				provider=provider_profile,
				actor=request.user,
				service_request=sr,
			)
			messages.success(request, message)
			return redirect("marketplace:request_detail", request_id=sr.id)

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
	request_type = (request.GET.get("request_type") or "").strip().lower()
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
				eligible_ids = _provider_available_request_ids(provider)
				qs = qs.filter(id__in=eligible_ids)

	# فلاتر آمنة
	if q:
		qs = qs.filter(Q(title__icontains=q) | Q(description__icontains=q))
	if city:
		city_values = provider_city_query_values(city)
		city_query = Q()
		for value in city_values:
			city_query |= Q(city__icontains=value)
		qs = qs.filter(city_query)
	if request_type in {choice[0] for choice in RequestType.choices}:
		qs = qs.filter(request_type=request_type)
	if status:
		status_group = _normalize_status_group(status)
		if status_group:
			qs = qs.filter(status__in=_status_group_to_statuses(status_group))
		else:
			valid = {c[0] for c in RequestStatus.choices}
			if status in valid:
				qs = qs.filter(status=status)

	paginator = Paginator(qs, 12)
	page_obj = paginator.get_page(page)
	page_obj.object_list = [
		_decorate_dashboard_request(
			obj,
			can_accept_legacy=bool(tab == "available" and provider and obj.request_type == RequestType.URGENT),
		)
		for obj in page_obj.object_list
	]

	if provider:
		available_base = ServiceRequest.objects.filter(id__in=_provider_available_request_ids(provider))
		assigned_base = ServiceRequest.objects.filter(provider=provider)
	else:
		available_base = ServiceRequest.objects.filter(status=RequestStatus.NEW, provider__isnull=True).exclude(request_type=RequestType.NORMAL)
		assigned_base = ServiceRequest.objects.filter(provider__isnull=False)

	summary = {
		"available_total": available_base.count(),
		"assigned_total": assigned_base.count(),
		"competitive_available": available_base.filter(request_type=RequestType.COMPETITIVE).count(),
		"urgent_available": available_base.filter(request_type=RequestType.URGENT).count(),
		"awaiting_acceptance": assigned_base.filter(status=RequestStatus.NEW, request_type=RequestType.NORMAL).count(),
		"awaiting_client": assigned_base.filter(status=RequestStatus.AWAITING_CLIENT_APPROVAL).count(),
		"in_progress_total": assigned_base.filter(status=RequestStatus.IN_PROGRESS).count(),
	}

	tab_titles = {
		"available": "الطلبات المتاحة الآن",
		"assigned": "الطلبات المسندة إليك",
		"all": "عرض تشغيلي شامل",
	}
	tab_descriptions = {
		"available": "يتضمن هذا العرض الطلبات التي يحق لك الاطلاع عليها حالياً بحسب الباقة، النطاق، ونوع الطلب.",
		"assigned": "هنا تجد جميع الطلبات التي أُسنِدت إليك وتحتاج متابعة، اعتماد عميل، أو استكمال تنفيذ.",
		"all": "عرض موحّد للمراجعة التشغيلية يشمل جميع الطلبات المتاحة والمسندة والمكتملة عند الحاجة.",
	}

	context = {
		"tab": tab,
		"q": q,
		"city": city,
		"status": status,
		"request_type": request_type,
		"page_obj": page_obj,
		"provider": provider,
		"summary": summary,
		"current_tab_title": tab_titles.get(tab, tab_titles["available"]),
		"current_tab_description": tab_descriptions.get(tab, tab_descriptions["available"]),
	}
	return render(request, "marketplace/provider_requests.html", context)
