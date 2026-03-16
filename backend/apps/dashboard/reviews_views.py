from __future__ import annotations

from datetime import datetime, timedelta

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Q
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.content.services import sanitize_text
from apps.reviews.models import Review, ReviewModerationStatus
from apps.reviews.services import sync_review_to_unified

from .auth import dashboard_staff_required as staff_member_required
from .views import _dashboard_allowed, dashboard_access_required


@staff_member_required
@dashboard_access_required("content", write=False)
def reviews_dashboard_list(request):
    rating = (request.GET.get("rating") or "").strip()
    moderation_status = (request.GET.get("status") or "").strip()
    target = (request.GET.get("target") or "").strip()
    date_from = (request.GET.get("date_from") or "").strip()
    date_to = (request.GET.get("date_to") or "").strip()

    qs = Review.objects.select_related("provider__user", "client", "request__subcategory")

    if rating.isdigit():
        qs = qs.filter(rating=int(rating))
    if moderation_status in {c[0] for c in ReviewModerationStatus.choices}:
        qs = qs.filter(moderation_status=moderation_status)
    if target:
        target_q = Q(provider__display_name__icontains=target) | Q(client__phone__icontains=target)
        if target.isdigit():
            target_q = target_q | Q(request_id=int(target))
        qs = qs.filter(target_q)

    if date_from:
        try:
            from_dt = datetime.strptime(date_from, "%Y-%m-%d")
            qs = qs.filter(created_at__gte=timezone.make_aware(from_dt, timezone.get_current_timezone()))
        except Exception:
            pass
    if date_to:
        try:
            to_dt = datetime.strptime(date_to, "%Y-%m-%d") + timedelta(days=1)
            qs = qs.filter(created_at__lt=timezone.make_aware(to_dt, timezone.get_current_timezone()))
        except Exception:
            pass

    qs = qs.order_by("-id")

    paginator = Paginator(qs, 20)
    page_obj = paginator.get_page(request.GET.get("page") or 1)

    return render(
        request,
        "dashboard/reviews_list.html",
        {
            "page_obj": page_obj,
            "rating": rating,
            "status": moderation_status,
            "target": target,
            "date_from": date_from,
            "date_to": date_to,
            "status_choices": ReviewModerationStatus.choices,
            "can_write": _dashboard_allowed(request.user, "content", write=True),
        },
    )


@staff_member_required
@dashboard_access_required("content", write=False)
def reviews_dashboard_detail(request, review_id: int):
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
    # Compute detailed ratings list for template
    rating_criteria = []
    criteria_map = [
        ("response_speed", "سرعة الاستجابة"),
        ("cost_value", "القيمة مقابل التكلفة"),
        ("quality", "جودة العمل"),
        ("credibility", "المصداقية"),
        ("on_time", "الالتزام بالموعد"),
    ]
    for field_name, label in criteria_map:
        val = getattr(review, field_name, None)
        if val is not None:
            rating_criteria.append({"label": label, "value": val, "pct": val * 20})

    # Compute priority indicator based on rating
    if review.rating <= 2:
        priority_label = "عالية"
        priority_color = "rose"
    elif review.rating == 3:
        priority_label = "متوسطة"
        priority_color = "amber"
    else:
        priority_label = "منخفضة"
        priority_color = "emerald"

    service_request = review.request
    return render(
        request,
        "dashboard/reviews_detail.html",
        {
            "review": review,
            "service_request": service_request,
            "rating_criteria": rating_criteria,
            "priority_label": priority_label,
            "priority_color": priority_color,
            "status_choices": ReviewModerationStatus.choices,
            "can_write": _dashboard_allowed(request.user, "content", write=True),
        },
    )


@require_POST
@staff_member_required
@dashboard_access_required("content", write=True)
def reviews_dashboard_moderate_action(request, review_id: int):
    review = get_object_or_404(Review, id=review_id)

    action_name = (request.POST.get("action") or "").strip()
    mapping = {
        "approve": ReviewModerationStatus.APPROVED,
        "reject": ReviewModerationStatus.REJECTED,
        "hide": ReviewModerationStatus.HIDDEN,
    }
    new_status = mapping.get(action_name)
    if not new_status:
        messages.error(request, "إجراء غير معروف")
        return redirect("dashboard:reviews_dashboard_detail", review_id=review.id)

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
    messages.success(request, "تم تحديث حالة المراجعة")
    return redirect("dashboard:reviews_dashboard_detail", review_id=review.id)


@require_POST
@staff_member_required
@dashboard_access_required("content", write=True)
def reviews_dashboard_respond_action(request, review_id: int):
    review = get_object_or_404(Review, id=review_id)
    text = sanitize_text(request.POST.get("management_reply", ""))
    if not text:
        messages.error(request, "الرد لا يمكن أن يكون فارغاً")
        return redirect("dashboard:reviews_dashboard_detail", review_id=review.id)

    review.management_reply = text
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
        extra={"management_reply": text},
    )
    messages.success(request, "تم حفظ الرد الإداري")
    return redirect("dashboard:reviews_dashboard_detail", review_id=review.id)
