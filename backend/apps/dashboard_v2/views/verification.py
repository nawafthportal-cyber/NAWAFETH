from __future__ import annotations

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Count, Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from apps.backoffice.policies import VerificationFinalizePolicy
from apps.dashboard.access import can_access_object, has_action_permission, has_dashboard_access
from apps.dashboard.contracts import DashboardCode
from apps.verification.models import VerificationDocument, VerificationRequirement, VerificationRequest, VerificationStatus
from apps.verification.services import (
    activate_after_payment,
    decide_requirement,
    finalize_request_and_create_invoice,
)

from ..view_utils import apply_role_scope, build_layout_context, dashboard_v2_access_required


def _can_access_verification_object(user, vr: VerificationRequest) -> bool:
    return can_access_object(
        user,
        vr,
        assigned_field="assigned_to",
        allow_unassigned_for_user_level=True,
    )


@dashboard_v2_access_required(DashboardCode.VERIFY, write=False)
def verification_requests_list_view(request):
    qs = (
        VerificationRequest.objects.select_related("requester", "invoice", "assigned_to")
        .prefetch_related("requirements")
        .order_by("-id")
    )

    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    qs = apply_role_scope(
        qs,
        user=request.user,
        assigned_field="assigned_to",
        owner_field=None,
        include_unassigned_for_user=False,
    )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    summary = qs.aggregate(
        total=Count("id"),
        new=Count("id", filter=Q(status=VerificationStatus.NEW)),
        in_review=Count("id", filter=Q(status=VerificationStatus.IN_REVIEW)),
        active=Count("id", filter=Q(status=VerificationStatus.ACTIVE)),
    )

    context = build_layout_context(
        request,
        title="التوثيق",
        subtitle="متابعة طلبات التوثيق والمستندات والاعتماد",
        active_code=DashboardCode.VERIFY,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "status_choices": VerificationStatus.choices,
            "summary": {
                "total": summary.get("total") or 0,
                "new": summary.get("new") or 0,
                "in_review": summary.get("in_review") or 0,
                "active": summary.get("active") or 0,
            },
            "can_write": has_dashboard_access(request.user, DashboardCode.VERIFY, write=True),
            "table_headers": ["الطلب", "المستخدم", "بنود التوثيق", "الحالة", "المكلّف", "الفاتورة", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/verification/requests_list.html", context)


@dashboard_v2_access_required(DashboardCode.VERIFY, write=False)
def verification_request_detail_view(request, verification_id: int):
    vr = get_object_or_404(
        VerificationRequest.objects.select_related("requester", "invoice", "assigned_to"),
        id=verification_id,
    )
    if not _can_access_verification_object(request.user, vr):
        return HttpResponse("غير مصرح", status=403)

    docs = list(VerificationDocument.objects.filter(request=vr).select_related("decided_by").order_by("-id"))
    reqs = list(
        VerificationRequirement.objects.filter(request=vr)
        .select_related("decided_by")
        .prefetch_related("attachments")
        .order_by("sort_order", "id")
    )
    inv_lines = list(vr.invoice.lines.all().order_by("sort_order", "id")) if vr.invoice_id and hasattr(vr.invoice, "lines") else []

    can_write = has_dashboard_access(request.user, DashboardCode.VERIFY, write=True)
    can_finalize = can_write and has_action_permission(request.user, "verification.finalize")

    context = build_layout_context(
        request,
        title=f"طلب توثيق {vr.code or vr.id}",
        subtitle="تفاصيل الطلب، المتطلبات، والمستندات",
        active_code=DashboardCode.VERIFY,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "التوثيق", "url": "dashboard_v2:verification_requests_list"},
        ],
    )
    context.update(
        {
            "vr": vr,
            "docs": docs,
            "reqs": reqs,
            "inv_lines": inv_lines,
            "can_finalize": can_finalize,
        }
    )
    return render(request, "dashboard_v2/verification/request_detail.html", context)


@dashboard_v2_access_required(DashboardCode.VERIFY, write=True)
@require_POST
def verification_requirement_decision_action(request, req_id: int):
    req = get_object_or_404(VerificationRequirement.objects.select_related("request"), id=req_id)
    vr = req.request
    if not _can_access_verification_object(request.user, vr):
        return HttpResponse("غير مصرح", status=403)
    if not has_action_permission(request.user, "verification.finalize"):
        messages.error(request, "ليس لديك صلاحية تنفيذ قرار بنود التوثيق.")
        return redirect("dashboard_v2:verification_request_detail", verification_id=vr.id)

    raw = (request.POST.get("is_approved") or "").strip().lower()
    if raw not in {"true", "false", "1", "0", "yes", "no"}:
        messages.warning(request, "اختر قرار البند.")
        return redirect("dashboard_v2:verification_request_detail", verification_id=vr.id)
    is_approved = raw in {"true", "1", "yes"}
    note = (request.POST.get("decision_note") or "").strip()
    try:
        decide_requirement(req=req, is_approved=is_approved, note=note, by_user=request.user)
        messages.success(request, "تم حفظ قرار البند.")
    except Exception:
        messages.error(request, "تعذر حفظ قرار البند.")
    return redirect("dashboard_v2:verification_request_detail", verification_id=vr.id)


@dashboard_v2_access_required(DashboardCode.VERIFY, write=True)
@require_POST
def verification_finalize_action(request, verification_id: int):
    vr = get_object_or_404(VerificationRequest, id=verification_id)
    if not _can_access_verification_object(request.user, vr):
        return HttpResponse("غير مصرح", status=403)

    policy = VerificationFinalizePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="verification.request",
        reference_id=str(vr.id),
        extra={"surface": "dashboard_v2.verification_finalize_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإنهاء هذا الطلب.")
        return redirect("dashboard_v2:verification_request_detail", verification_id=vr.id)

    try:
        vr = finalize_request_and_create_invoice(vr=vr, by_user=request.user)
        messages.success(request, f"تمت معالجة الطلب: {vr.get_status_display()}")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر إنهاء طلب التوثيق.")
    return redirect("dashboard_v2:verification_request_detail", verification_id=vr.id)


@dashboard_v2_access_required(DashboardCode.VERIFY, write=True)
@require_POST
def verification_activate_action(request, verification_id: int):
    vr = get_object_or_404(VerificationRequest, id=verification_id)
    if not _can_access_verification_object(request.user, vr):
        return HttpResponse("غير مصرح", status=403)

    policy = VerificationFinalizePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="verification.request",
        reference_id=str(vr.id),
        extra={"surface": "dashboard_v2.verification_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل طلب التوثيق.")
        return redirect("dashboard_v2:verification_request_detail", verification_id=vr.id)

    try:
        activate_after_payment(vr=vr)
        messages.success(request, "تم تفعيل التوثيق بنجاح.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تفعيل طلب التوثيق.")
    return redirect("dashboard_v2:verification_request_detail", verification_id=vr.id)
