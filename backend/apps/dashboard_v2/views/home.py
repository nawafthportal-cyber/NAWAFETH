from __future__ import annotations

from datetime import timedelta

from django.utils import timezone
from django.shortcuts import render

from apps.unified_requests.models import UnifiedRequest, UnifiedRequestStatus
from apps.dashboard.contracts import DashboardCode
from apps.dashboard.access import has_dashboard_access

from ..view_utils import apply_role_scope, build_layout_context, dashboard_v2_login_required, user_can_write


@dashboard_v2_login_required
def home_view(request):
    base_qs = UnifiedRequest.objects.select_related("requester", "assigned_user").all()
    scoped_qs = apply_role_scope(
        base_qs,
        user=request.user,
        assigned_field="assigned_user",
        owner_field="requester",
        include_unassigned_for_user=False,
    )

    cards = {
        UnifiedRequestStatus.NEW: scoped_qs.filter(status=UnifiedRequestStatus.NEW).count(),
        UnifiedRequestStatus.IN_PROGRESS: scoped_qs.filter(status=UnifiedRequestStatus.IN_PROGRESS).count(),
        UnifiedRequestStatus.RETURNED: scoped_qs.filter(status=UnifiedRequestStatus.RETURNED).count(),
        UnifiedRequestStatus.CLOSED: scoped_qs.filter(status=UnifiedRequestStatus.CLOSED).count(),
    }

    recent_requests = list(scoped_qs.order_by("-updated_at", "-id")[:10])
    two_days_ago = timezone.now() - timedelta(days=2)
    delayed_open_count = scoped_qs.filter(
        status__in=[
            UnifiedRequestStatus.NEW,
            UnifiedRequestStatus.IN_PROGRESS,
            UnifiedRequestStatus.RETURNED,
        ],
        updated_at__lt=two_days_ago,
    ).count()

    alerts: list[dict[str, str]] = []
    if delayed_open_count:
        alerts.append(
            {
                "level": "warning",
                "title": "تنبيه تشغيل",
                "text": f"يوجد {delayed_open_count} طلبات مفتوحة دون تحديث منذ أكثر من 48 ساعة.",
            }
        )
    if not recent_requests:
        alerts.append(
            {
                "level": "info",
                "title": "لا توجد عناصر حديثة",
                "text": "لم يتم العثور على طلبات ضمن نطاق وصولك الحالي.",
            }
        )

    quick_links = []
    if any(
        has_dashboard_access(request.user, code, write=False)
        for code in (
            DashboardCode.ANALYTICS,
            DashboardCode.SUPPORT,
            DashboardCode.CONTENT,
            DashboardCode.MODERATION,
            DashboardCode.REVIEWS,
            DashboardCode.PROMO,
            DashboardCode.VERIFY,
            DashboardCode.SUBS,
            DashboardCode.EXTRAS,
        )
    ):
        quick_links.append({"label": "الطلبات الموحدة", "url": "dashboard_v2:requests_list"})
    if has_dashboard_access(request.user, DashboardCode.SUPPORT, write=False):
        quick_links.append({"label": "تذاكر الدعم", "url": "dashboard_v2:support_list"})
    if has_dashboard_access(request.user, DashboardCode.CONTENT, write=False):
        quick_links.append({"label": "إدارة المحتوى", "url": "dashboard_v2:content_home"})
    if has_dashboard_access(request.user, DashboardCode.MODERATION, write=False):
        quick_links.append({"label": "مركز الإشراف", "url": "dashboard_v2:moderation_list"})
    if has_dashboard_access(request.user, DashboardCode.REVIEWS, write=False):
        quick_links.append({"label": "المراجعات", "url": "dashboard_v2:reviews_list"})
    if has_dashboard_access(request.user, DashboardCode.PROMO, write=False):
        quick_links.append({"label": "الترويج", "url": "dashboard_v2:promo_requests_list"})
    if has_dashboard_access(request.user, DashboardCode.VERIFY, write=False):
        quick_links.append({"label": "التوثيق", "url": "dashboard_v2:verification_requests_list"})
    if has_dashboard_access(request.user, DashboardCode.SUBS, write=False):
        quick_links.append({"label": "الاشتراكات", "url": "dashboard_v2:subscriptions_list"})
    if has_dashboard_access(request.user, "excellence", write=False):
        quick_links.append({"label": "التميز", "url": "dashboard_v2:excellence_home"})
    if has_dashboard_access(request.user, DashboardCode.ADMIN_CONTROL, write=False):
        quick_links.append({"label": "المستخدمون والصلاحيات", "url": "dashboard_v2:users_list"})

    context = build_layout_context(
        request,
        title="Dashboard V2",
        subtitle="نظرة تشغيلية سريعة على الحالة الحالية",
        active_code=DashboardCode.ANALYTICS,
    )
    context.update(
        {
            "cards": cards,
            "recent_requests": recent_requests,
            "alerts": alerts,
            "quick_links": quick_links,
            "can_write": user_can_write(request.user),
        }
    )
    return render(request, "dashboard_v2/home/index.html", context)
