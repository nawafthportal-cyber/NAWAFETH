from __future__ import annotations

from decimal import Decimal

import pytest
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.promo.models import PromoPriceUnit, PromoPricingRule, PromoServiceType
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.verification.models import VerificationRequest


def _dashboard(code: str, name_ar: str) -> Dashboard:
    dashboard, _ = Dashboard.objects.get_or_create(
        code=code,
        defaults={"name_ar": name_ar, "sort_order": 10},
    )
    return dashboard


def _login_dashboard_v2(client: Client, *, user: User, password: str = "Pass12345!") -> None:
    assert client.login(phone=user.phone, password=password)
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()


def _access_profile(user: User, *, level: str, dashboards: list[Dashboard]) -> UserAccessProfile:
    access_profile = UserAccessProfile.objects.create(user=user, level=level)
    access_profile.allowed_dashboards.set(dashboards)
    return access_profile


@pytest.mark.django_db
def test_phase3_promo_routes_and_pricing_permission():
    promo_dashboard = _dashboard("promo", "الترويج")
    user = User.objects.create_user(phone="0500300001", password="Pass12345!", is_staff=True)
    profile = _access_profile(user, level=AccessLevel.USER, dashboards=[promo_dashboard])

    rule = PromoPricingRule.objects.create(
        code="PH3_PROMO_RULE",
        service_type=PromoServiceType.HOME_BANNER,
        title="قاعدة اختبارية",
        unit=PromoPriceUnit.DAY,
        amount=Decimal("25.00"),
        is_active=True,
    )

    client = Client()
    _login_dashboard_v2(client, user=user)
    assert client.get(reverse("dashboard_v2:promo_requests_list")).status_code == 200
    assert client.get(reverse("dashboard_v2:promo_inquiries_list")).status_code == 200
    assert client.get(reverse("dashboard_v2:promo_pricing")).status_code == 200

    denied = client.post(
        reverse("dashboard_v2:promo_pricing_update_action"),
        data={"code": rule.code, "amount": "40.00", "is_active": "1"},
    )
    assert denied.status_code == 302
    rule.refresh_from_db()
    assert rule.amount == Decimal("25.00")

    permission, _ = AccessPermission.objects.get_or_create(
        code="promo.quote_activate",
        defaults={
            "name_ar": "تسعير وتفعيل الترويج",
            "dashboard_code": "promo",
            "sort_order": 30,
            "is_active": True,
        },
    )
    profile.granted_permissions.add(permission)

    allowed = client.post(
        reverse("dashboard_v2:promo_pricing_update_action"),
        data={"code": rule.code, "amount": "40.00", "is_active": "1"},
    )
    assert allowed.status_code == 302
    rule.refresh_from_db()
    assert rule.amount == Decimal("40.00")


@pytest.mark.django_db
def test_phase3_verification_object_access_and_finalize_guard():
    verify_dashboard = _dashboard("verify", "التوثيق")

    viewer = User.objects.create_user(phone="0500300011", password="Pass12345!", is_staff=True)
    assignee = User.objects.create_user(phone="0500300012", password="Pass12345!", is_staff=True)
    requester = User.objects.create_user(phone="0500300013", password="Pass12345!")
    qa_user = User.objects.create_user(phone="0500300014", password="Pass12345!", is_staff=True)

    _access_profile(viewer, level=AccessLevel.USER, dashboards=[verify_dashboard])
    _access_profile(assignee, level=AccessLevel.USER, dashboards=[verify_dashboard])
    _access_profile(qa_user, level=AccessLevel.QA, dashboards=[verify_dashboard])

    vr = VerificationRequest.objects.create(requester=requester, assigned_to=assignee)

    viewer_client = Client()
    _login_dashboard_v2(viewer_client, user=viewer)
    assert viewer_client.get(reverse("dashboard_v2:verification_requests_list")).status_code == 200
    assert viewer_client.get(reverse("dashboard_v2:verification_request_detail", args=[vr.id])).status_code == 403

    qa_client = Client()
    _login_dashboard_v2(qa_client, user=qa_user)
    finalize_resp = qa_client.post(reverse("dashboard_v2:verification_finalize_action", args=[vr.id]))
    assert finalize_resp.status_code in (302, 403)
    vr.refresh_from_db()
    assert vr.invoice_id is None


@pytest.mark.django_db
def test_phase3_subscriptions_scope_and_core_views():
    subs_dashboard = _dashboard("subs", "الاشتراكات")

    operator = User.objects.create_user(phone="0500300021", password="Pass12345!", is_staff=True)
    foreign_user = User.objects.create_user(phone="0500300022", password="Pass12345!")
    _access_profile(operator, level=AccessLevel.USER, dashboards=[subs_dashboard])

    plan = SubscriptionPlan.objects.create(
        code="PH3_BASIC",
        title="باقة اختبار",
        period=PlanPeriod.MONTH,
        price=Decimal("99.00"),
        is_active=True,
    )
    owned_sub = Subscription.objects.create(
        user=operator,
        plan=plan,
        status=SubscriptionStatus.PENDING_PAYMENT,
    )
    foreign_sub = Subscription.objects.create(
        user=foreign_user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
    )

    client = Client()
    _login_dashboard_v2(client, user=operator)
    list_response = client.get(reverse("dashboard_v2:subscriptions_list"))
    assert list_response.status_code == 200
    html = list_response.content.decode("utf-8")
    assert reverse("dashboard_v2:subscription_request_detail", args=[owned_sub.id]) in html
    assert reverse("dashboard_v2:subscription_request_detail", args=[foreign_sub.id]) not in html

    assert client.get(reverse("dashboard_v2:subscriptions_plans_list")).status_code == 200
    assert client.get(reverse("dashboard_v2:subscription_request_detail", args=[owned_sub.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:subscription_account_detail", args=[owned_sub.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:subscription_payment_detail", args=[owned_sub.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:subscription_request_detail", args=[foreign_sub.id])).status_code == 403
