from __future__ import annotations

from datetime import timedelta

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.content.services import sanitize_text
from apps.dashboard.access import has_action_permission, has_dashboard_access
from apps.dashboard.contracts import DashboardCode
from apps.moderation.integrations import sync_review_case
from apps.reviews.models import Review, ReviewModerationStatus
from apps.reviews.services import sync_review_to_unified

from ..view_utils import build_layout_context, dashboard_v2_login_required, parse_date_yyyy_mm_dd


def _has_reviews_access(user, *, write: bool = False) -> bool:
    return has_dashboard_access(user, DashboardCode.REVIEWS, write=write) or has_dashboard_access(
        user, DashboardCode.CONTENT, write=write
    )


def _review_priority(review: Review) -> tuple[str, str]:
    if review.rating <= 2:
        return "عالية", "high"
    if review.rating == 3:
        return "متوسطة", "normal"
    return "منخفضة", "low"


def _review_rating_criteria(review: Review) -> list[dict[str, int | str]]:
    criteria = []
    for field_name, label in (
        ("response_speed", "سرعة الاستجابة"),
        ("cost_value", "القيمة مقابل التكلفة"),
        ("quality", "جودة العمل"),
        ("credibility", "المصداقية"),
        ("on_time", "الالتزام بالموعد"),
    ):
        value = getattr(review, field_name, None)
        if value is None:
            continue
        criteria.append({"label": label, "value": value, "pct": int(value * 20)})
    return criteria


@dashboard_v2_login_required
def reviews_list_view(request):
    if not _has_reviews_access(request.user, write=False):
        return HttpResponse("غير مصرح", status=403)

    rating_q = (request.GET.get("rating") or "").strip()
    status_q = (request.GET.get("status") or "").strip()
    target_q = (request.GET.get("target") or "").strip()
    date_from_q = (request.GET.get("date_from") or "").strip()
    date_to_q = (request.GET.get("date_to") or "").strip()

    qs = Review.objects.select_related("provider__user", "client", "request__subcategory").order_by("-id")
    if rating_q.isdigit():
        qs = qs.filter(rating=int(rating_q))
    if status_q in {choice[0] for choice in ReviewModerationStatus.choices}:
        qs = qs.filter(moderation_status=status_q)
    if target_q:
        target_filter = Q(provider__display_name__icontains=target_q) | Q(client__phone__icontains=target_q)
        if target_q.isdigit():
            target_filter |= Q(request_id=int(target_q))
        qs = qs.filter(target_filter)
    date_from = parse_date_yyyy_mm_dd(date_from_q)
    date_to = parse_date_yyyy_mm_dd(date_to_q)
    if date_from:
        qs = qs.filter(created_at__gte=date_from)
    if date_to:
        qs = qs.filter(created_at__lt=date_to + timedelta(days=1))

    paginator = Paginator(qs, 20)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    can_write = _has_reviews_access(request.user, write=True)
    can_moderate = can_write and has_action_permission(request.user, "reviews.moderate")

    context = build_layout_context(
        request,
        title="المراجعات",
        subtitle="مراجعة تقييمات العملاء والردود الإدارية",
        active_code=DashboardCode.REVIEWS,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "rating_q": rating_q,
            "status_q": status_q,
            "target_q": target_q,
            "date_from_q": date_from_q,
            "date_to_q": date_to_q,
            "status_choices": ReviewModerationStatus.choices,
            "can_moderate": can_moderate,
            "table_headers": ["المراجعة", "المزود", "الحالة", "التقييم", "التاريخ", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/reviews/list.html", context)


@dashboard_v2_login_required
def reviews_detail_view(request, review_id: int):
    if not _has_reviews_access(request.user, write=False):
        return HttpResponse("غير مصرح", status=403)

    review = get_object_or_404(
        Review.objects.select_related(
            "provider__user",
            "client",
            "request__subcategory",
            "moderated_by",
            "management_reply_by",
        ),
        id=review_id,
    )
    priority_label, priority_code = _review_priority(review)
    can_write = _has_reviews_access(request.user, write=True)
    can_moderate = can_write and has_action_permission(request.user, "reviews.moderate")

    context = build_layout_context(
        request,
        title=f"مراجعة #{review.id}",
        subtitle="تفاصيل المراجعة، التقييمات التفصيلية، والرد الإداري",
        active_code=DashboardCode.REVIEWS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "المراجعات", "url": "dashboard_v2:reviews_list"},
        ],
    )
    context.update(
        {
            "review": review,
            "rating_criteria": _review_rating_criteria(review),
            "priority_label": priority_label,
            "priority_code": priority_code,
            "status_choices": ReviewModerationStatus.choices,
            "can_moderate": can_moderate,
        }
    )
    return render(request, "dashboard_v2/reviews/detail.html", context)


@dashboard_v2_login_required
@require_POST
def reviews_moderate_action(request, review_id: int):
    if not _has_reviews_access(request.user, write=True):
        return HttpResponse("غير مصرح", status=403)

    review = get_object_or_404(Review, id=review_id)
    if not has_action_permission(request.user, "reviews.moderate"):
        messages.error(request, "غير مصرح بتنفيذ إجراء الإشراف على المراجعات.")
        return redirect("dashboard_v2:reviews_detail", review_id=review.id)

    action_name = (request.POST.get("action") or "").strip().lower()
    status_mapping = {
        "approve": ReviewModerationStatus.APPROVED,
        "reject": ReviewModerationStatus.REJECTED,
        "hide": ReviewModerationStatus.HIDDEN,
    }
    new_status = status_mapping.get(action_name)
    if not new_status:
        messages.error(request, "إجراء غير صالح.")
        return redirect("dashboard_v2:reviews_detail", review_id=review.id)

    old_status = review.moderation_status
    review.moderation_status = new_status
    review.moderation_note = sanitize_text(request.POST.get("moderation_note", ""))
    review.moderated_at = timezone.now()
    review.moderated_by = request.user
    review.save(update_fields=["moderation_status", "moderation_note", "moderated_at", "moderated_by"])
    sync_review_to_unified(review=review, changed_by=request.user, force_status="closed")

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.REVIEW_MODERATED,
        reference_type="reviews.review",
        reference_id=str(review.id),
        extra={
            "before": old_status,
            "after": review.moderation_status,
            "moderation_note": review.moderation_note,
        },
    )
    try:
        sync_review_case(
            review=review,
            action_name=action_name,
            note=review.moderation_note,
            by_user=request.user,
            request=request,
        )
    except Exception:
        pass

    messages.success(request, "تم تحديث حالة المراجعة.")
    return redirect("dashboard_v2:reviews_detail", review_id=review.id)


@dashboard_v2_login_required
@require_POST
def reviews_respond_action(request, review_id: int):
    if not _has_reviews_access(request.user, write=True):
        return HttpResponse("غير مصرح", status=403)

    review = get_object_or_404(Review, id=review_id)
    if not has_action_permission(request.user, "reviews.moderate"):
        messages.error(request, "غير مصرح بإضافة رد إداري على المراجعات.")
        return redirect("dashboard_v2:reviews_detail", review_id=review.id)

    reply_text = sanitize_text(request.POST.get("management_reply", ""))
    if not reply_text:
        messages.error(request, "الرد لا يمكن أن يكون فارغًا.")
        return redirect("dashboard_v2:reviews_detail", review_id=review.id)

    review.management_reply = reply_text
    review.management_reply_at = timezone.now()
    review.management_reply_by = request.user
    review.save(update_fields=["management_reply", "management_reply_at", "management_reply_by"])
    sync_review_to_unified(review=review, changed_by=request.user)

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.REVIEW_RESPONSE_ADDED,
        reference_type="reviews.review",
        reference_id=str(review.id),
        extra={"management_reply": reply_text},
    )
    messages.success(request, "تم حفظ الرد الإداري.")
    return redirect("dashboard_v2:reviews_detail", review_id=review.id)

