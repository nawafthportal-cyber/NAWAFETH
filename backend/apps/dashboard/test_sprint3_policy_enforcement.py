import pytest
from django.test import Client, override_settings
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.backoffice.policies import PermissionCode
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType


pytestmark = pytest.mark.django_db


def _login_dashboard_user(phone: str, dashboards: list[str], permission_codes: list[str] | None = None):
    user = User.objects.create_user(phone=phone, password="Pass12345!", is_staff=True)
    profile = UserAccessProfile.objects.create(user=user, level=AccessLevel.USER)
    for index, code in enumerate(dashboards, start=1):
        dashboard, _ = Dashboard.objects.get_or_create(code=code, defaults={"name_ar": code, "sort_order": index})
        profile.allowed_dashboards.add(dashboard)
    for index, code in enumerate(permission_codes or [], start=1):
        permission, _ = AccessPermission.objects.get_or_create(
            code=code,
            defaults={"name_ar": code, "dashboard_code": dashboards[0], "sort_order": 80 + index},
        )
        profile.granted_permissions.add(permission)

    client = Client()
    assert client.login(phone=phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return user, client


def _subscription_request(user):
    plan = SubscriptionPlan.objects.create(
        code="SPRINT3-PRO",
        title="Sprint3 Pro",
        tier="pro",
        period=PlanPeriod.MONTH,
        price="99.00",
    )
    sub = Subscription.objects.create(user=user, plan=plan, status="pending_payment")
    UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        requester=user,
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
        status="new",
        priority="normal",
        summary="اشتراك",
    )
    return sub


@override_settings(FEATURE_RBAC_ENFORCE=False, RBAC_AUDIT_ONLY=True)
def test_subscription_request_assign_uses_dashboard_fallback_in_audit_only():
    requester = User.objects.create_user(phone="0503000011", password="Pass12345!")
    operator, client = _login_dashboard_user("0503000010", ["subs"])
    sub = _subscription_request(requester)

    response = client.post(
        reverse("dashboard:subscription_request_assign_action", args=[sub.id]),
        data={"assigned_to": operator.id, "note": "claim"},
    )

    assert response.status_code == 302
    ur = UnifiedRequest.objects.get(source_app="subscriptions", source_object_id=str(sub.id))
    assert ur.assigned_user_id == operator.id


@override_settings(FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_subscription_request_assign_denied_without_permission_when_enforced():
    requester = User.objects.create_user(phone="0503000013", password="Pass12345!")
    operator, client = _login_dashboard_user("0503000012", ["subs"])
    sub = _subscription_request(requester)

    response = client.post(
        reverse("dashboard:subscription_request_assign_action", args=[sub.id]),
        data={"assigned_to": operator.id, "note": "claim"},
    )

    assert response.status_code == 302
    ur = UnifiedRequest.objects.get(source_app="subscriptions", source_object_id=str(sub.id))
    assert ur.assigned_user_id is None


@override_settings(FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_extras_request_assign_allows_when_permission_granted():
    requester = User.objects.create_user(phone="0503000015", password="Pass12345!")
    operator, client = _login_dashboard_user("0503000014", ["extras"], [PermissionCode.EXTRAS_MANAGE])
    ur = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.EXTRAS,
        requester=requester,
        source_app="extras",
        source_model="ExtraPurchase",
        source_object_id="88",
        status="new",
        priority="normal",
        summary="إضافة",
    )

    response = client.post(
        reverse("dashboard:extras_request_assign_action", args=[ur.id]),
        data={"assigned_to": operator.id, "note": "claim"},
    )

    assert response.status_code == 302
    ur.refresh_from_db()
    assert ur.assigned_user_id == operator.id
