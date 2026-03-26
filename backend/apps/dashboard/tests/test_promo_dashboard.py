import pytest
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.accounts.models import User, UserRole
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.promo.models import (
    PromoAdType,
    PromoFrequency,
    PromoOpsStatus,
    PromoPosition,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoServiceType,
)
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.support.models import SupportPriority, SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketStatus, SupportTicketType


pytestmark = pytest.mark.django_db


def _dashboard_client() -> Client:
    user = User.objects.create_user(
        phone="0554000001",
        password="Pass12345!",
        is_staff=True,
        is_superuser=True,
        role_state=UserRole.STAFF,
    )
    client = Client()
    assert client.login(phone=user.phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return client


def _dashboard_client_for_user(user: User, *, password: str = "Pass12345!") -> Client:
    client = Client()
    assert client.login(phone=user.phone, password=password)
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return client


def _create_promo_request(*, plan_tier: str = "basic") -> PromoRequest:
    requester = User.objects.create_user(
        phone="0554001001",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    Subscription.objects.create(
        user=requester,
        plan=SubscriptionPlan.objects.create(
            code=f"{plan_tier}_promo",
            title=plan_tier,
            tier=plan_tier,
            period=PlanPeriod.MONTH,
            price="0.00",
            is_active=True,
        ),
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timezone.timedelta(days=30),
    )
    now = timezone.now()
    promo_request = PromoRequest.objects.create(
        requester=requester,
        title="طلب ترويج اختباري",
        ad_type=PromoAdType.BUNDLE,
        start_at=now,
        end_at=now + timezone.timedelta(days=2),
        frequency=PromoFrequency.S60,
        position=PromoPosition.NORMAL,
        status=PromoRequestStatus.ACTIVE,
        ops_status=PromoOpsStatus.IN_PROGRESS,
    )
    PromoRequestItem.objects.create(
        request=promo_request,
        service_type=PromoServiceType.FEATURED_SPECIALISTS,
        title="شريط أبرز المختصين",
        start_at=now,
        end_at=now + timezone.timedelta(days=2),
        frequency=PromoFrequency.S60,
        sort_order=10,
    )
    return promo_request


def test_promo_dashboard_nav_matches_requested_service_list_plus_pricing():
    client = _dashboard_client()

    response = client.get(reverse("dashboard:promo_dashboard"))

    assert response.status_code == 200
    labels = [item["label"] for item in response.context["nav_items"]]
    assert labels == [
        "بنر الصفحة الرئيسية",
        "شريط أبرز المختصين",
        "شريط البنرات والمشاريع",
        "شريط اللمحات",
        "الظهور في قوائم البحث",
        "الرسائل الدعائية",
        "الرعاية",
        "الأسعار",
    ]


def test_promo_requests_csv_export_includes_request_and_ops_status_columns():
    promo_request = _create_promo_request()
    client = _dashboard_client()

    response = client.get(
        reverse("dashboard:promo_dashboard"),
        {"scope": "requests", "export": "csv"},
    )

    assert response.status_code == 200
    assert response["Content-Disposition"] == 'attachment; filename="promo_requests.csv"'
    content = response.content.decode("utf-8")
    assert "الأولوية" in content
    assert "تاريخ وقت اعتماد الطلب" in content
    assert "حالة الطلب" in content
    assert promo_request.code in content
    assert promo_request.get_status_display() in content


def test_promo_dashboard_request_priority_follows_requester_plan_tier():
    _create_promo_request(plan_tier="riyadi")
    client = _dashboard_client()

    response = client.get(reverse("dashboard:promo_dashboard"))

    assert response.status_code == 200
    rows = response.context["promo_requests"]
    assert rows
    assert rows[0]["priority_number"] == 2
    assert rows[0]["approved_at"] != "-"


def test_promo_inquiry_appears_after_support_transfer_to_promo_team_assignee():
    admin_client = _dashboard_client()
    promo_dashboard, _ = Dashboard.objects.get_or_create(
        code="promo",
        defaults={"name_ar": "لوحة الترويج", "is_active": True, "sort_order": 30},
    )
    promo_team, _ = SupportTeam.objects.get_or_create(
        code="promo",
        defaults={"name_ar": "فريق إدارة الإعلانات والترويج", "is_active": True, "sort_order": 30},
    )
    promo_operator = User.objects.create_user(
        phone="0554002001",
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    promo_access = UserAccessProfile.objects.create(user=promo_operator, level=AccessLevel.USER)
    promo_access.allowed_dashboards.add(promo_dashboard)

    requester = User.objects.create_user(
        phone="0554002002",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار ترويج من لوحة الدعم",
    )

    response = admin_client.post(
        reverse("dashboard:support_ticket_detail", kwargs={"ticket_id": ticket.id}),
        {
            "ticket_id": str(ticket.id),
            "status": SupportTicketStatus.IN_PROGRESS,
            "assigned_team": str(promo_team.id),
            "assigned_to": str(promo_operator.id),
            "description": ticket.description,
            "assignee_comment": "تحويل إلى فريق الترويج",
            "action": "save_ticket",
        },
    )

    assert response.status_code == 302
    ticket.refresh_from_db()
    assert ticket.assigned_team_id == promo_team.id
    assert ticket.assigned_to_id == promo_operator.id

    promo_client = _dashboard_client_for_user(promo_operator)
    promo_response = promo_client.get(reverse("dashboard:promo_dashboard"))

    assert promo_response.status_code == 200
    inquiry_rows = promo_response.context["inquiries"]
    assert inquiry_rows
    assert inquiry_rows[0]["id"] == ticket.id
    assert inquiry_rows[0]["assignee"] == (promo_operator.username or promo_operator.phone)


def test_promo_inquiry_assignment_keeps_team_fixed_to_promo():
    client = _dashboard_client()
    _, _ = Dashboard.objects.get_or_create(
        code="promo",
        defaults={"name_ar": "لوحة الترويج", "is_active": True, "sort_order": 30},
    )
    promo_team, _ = SupportTeam.objects.get_or_create(
        code="promo",
        defaults={"name_ar": "فريق إدارة الإعلانات والترويج", "is_active": True, "sort_order": 30},
    )
    content_team, _ = SupportTeam.objects.get_or_create(
        code="content",
        defaults={"name_ar": "فريق إدارة المحتوى", "is_active": True, "sort_order": 40},
    )

    requester = User.objects.create_user(
        phone="0554002010",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار ترويجي لضبط الفريق الثابت",
        assigned_team=promo_team,
    )

    response = client.post(
        reverse("dashboard:promo_dashboard"),
        {
            "action": "save_inquiry",
            "ticket_id": str(ticket.id),
            "status": SupportTicketStatus.IN_PROGRESS,
            "assigned_team": str(content_team.id),
            "description": "تحديث من لوحة الترويج",
            "operator_comment": "اختبار تثبيت الفريق",
        },
    )

    assert response.status_code == 302
    ticket.refresh_from_db()
    assert ticket.assigned_team_id == promo_team.id


def test_promo_operator_can_reassign_inquiry_to_another_promo_operator():
    promo_dashboard, _ = Dashboard.objects.get_or_create(
        code="promo",
        defaults={"name_ar": "لوحة الترويج", "is_active": True, "sort_order": 30},
    )
    promo_team, _ = SupportTeam.objects.get_or_create(
        code="promo",
        defaults={"name_ar": "فريق إدارة الإعلانات والترويج", "is_active": True, "sort_order": 30},
    )

    operator_1 = User.objects.create_user(
        phone="0554002021",
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    operator_2 = User.objects.create_user(
        phone="0554002022",
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    profile_1 = UserAccessProfile.objects.create(user=operator_1, level=AccessLevel.USER)
    profile_1.allowed_dashboards.add(promo_dashboard)
    profile_2 = UserAccessProfile.objects.create(user=operator_2, level=AccessLevel.USER)
    profile_2.allowed_dashboards.add(promo_dashboard)

    requester = User.objects.create_user(
        phone="0554002023",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.IN_PROGRESS,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار لإعادة الإسناد",
        assigned_team=promo_team,
        assigned_to=operator_1,
    )

    operator_client = _dashboard_client_for_user(operator_1)
    response = operator_client.post(
        reverse("dashboard:promo_dashboard"),
        {
            "action": "save_inquiry",
            "ticket_id": str(ticket.id),
            "status": SupportTicketStatus.IN_PROGRESS,
            "assigned_to": str(operator_2.id),
            "description": "تحويل المكلف داخل فريق الترويج",
            "operator_comment": "تحويل لموظف آخر",
        },
    )

    assert response.status_code == 302
    ticket.refresh_from_db()
    assert ticket.assigned_team_id == promo_team.id
    assert ticket.assigned_to_id == operator_2.id
