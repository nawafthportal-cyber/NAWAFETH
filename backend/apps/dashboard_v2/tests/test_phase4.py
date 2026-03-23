from __future__ import annotations

from decimal import Decimal

import pytest
from django.test import Client, override_settings
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.billing.models import Invoice, InvoiceStatus
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ExtraType, ServiceCatalog
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestStatus, UnifiedRequestType


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
def test_phase4_extras_requests_scope_and_routes():
    extras_dashboard = _dashboard("extras", "الخدمات الإضافية")

    operator = User.objects.create_user(phone="0500400001", password="Pass12345!", is_staff=True)
    other_staff = User.objects.create_user(phone="0500400002", password="Pass12345!", is_staff=True)
    requester = User.objects.create_user(phone="0500400003", password="Pass12345!")
    foreign_requester = User.objects.create_user(phone="0500400004", password="Pass12345!")

    _access_profile(operator, level=AccessLevel.USER, dashboards=[extras_dashboard])
    _access_profile(other_staff, level=AccessLevel.USER, dashboards=[extras_dashboard])

    visible = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.EXTRAS,
        requester=requester,
        status=UnifiedRequestStatus.NEW,
        summary="extras-visible",
        assigned_user=operator,
        assigned_team_code="extras",
        assigned_team_name="الخدمات الإضافية",
    )
    hidden = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.EXTRAS,
        requester=foreign_requester,
        status=UnifiedRequestStatus.NEW,
        summary="extras-hidden",
        assigned_user=other_staff,
        assigned_team_code="extras",
        assigned_team_name="الخدمات الإضافية",
    )

    client = Client()
    _login_dashboard_v2(client, user=operator)

    response = client.get(reverse("dashboard_v2:extras_requests_list"))
    assert response.status_code == 200
    html = response.content.decode("utf-8")
    assert "extras-visible" in html
    assert "extras-hidden" not in html

    assert client.get(reverse("dashboard_v2:extras_request_detail", args=[visible.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:extras_request_detail", args=[hidden.id])).status_code == 403

    assert client.get(reverse("dashboard_v2:extras_clients_list")).status_code == 200
    assert client.get(reverse("dashboard_v2:extras_catalog_list")).status_code == 200
    assert client.get(reverse("dashboard_v2:extras_finance_list")).status_code == 200


@pytest.mark.django_db
@override_settings(FEATURE_RBAC_ENFORCE=True)
def test_phase4_extras_catalog_toggle_enforces_permission():
    extras_dashboard = _dashboard("extras", "الخدمات الإضافية")
    user = User.objects.create_user(phone="0500400011", password="Pass12345!", is_staff=True)
    profile = _access_profile(user, level=AccessLevel.USER, dashboards=[extras_dashboard])

    item = ServiceCatalog.objects.create(
        sku="PH4_EXTRA_SKU",
        title="خدمة إضافية",
        price=Decimal("49.00"),
        currency="SAR",
        is_active=True,
    )

    client = Client()
    _login_dashboard_v2(client, user=user)

    denied = client.post(reverse("dashboard_v2:extras_catalog_toggle_action", args=[item.id]))
    assert denied.status_code == 302
    item.refresh_from_db()
    assert item.is_active is True

    permission, _ = AccessPermission.objects.get_or_create(
        code="extras.manage",
        defaults={
            "name_ar": "إدارة الخدمات الإضافية",
            "dashboard_code": "extras",
            "sort_order": 40,
            "is_active": True,
        },
    )
    profile.granted_permissions.add(permission)

    allowed = client.post(reverse("dashboard_v2:extras_catalog_toggle_action", args=[item.id]))
    assert allowed.status_code == 302
    item.refresh_from_db()
    assert item.is_active is False


@pytest.mark.django_db
def test_phase4_client_portal_visibility_and_object_access():
    client_dashboard = _dashboard("client_extras", "بوابة العميل")

    portal_user = User.objects.create_user(phone="0500400021", password="Pass12345!")
    foreign_user = User.objects.create_user(phone="0500400022", password="Pass12345!")
    _access_profile(portal_user, level=AccessLevel.CLIENT, dashboards=[client_dashboard])
    _access_profile(foreign_user, level=AccessLevel.CLIENT, dashboards=[client_dashboard])

    own_invoice = Invoice.objects.create(
        user=portal_user,
        title="Own Invoice",
        currency="SAR",
        subtotal=Decimal("100.00"),
        vat_percent=Decimal("15.00"),
        status=InvoiceStatus.PENDING,
        reference_type="extra_purchase",
        reference_id="1",
    )
    foreign_invoice = Invoice.objects.create(
        user=foreign_user,
        title="Foreign Invoice",
        currency="SAR",
        subtotal=Decimal("90.00"),
        vat_percent=Decimal("15.00"),
        status=InvoiceStatus.PENDING,
        reference_type="extra_purchase",
        reference_id="2",
    )

    own_purchase = ExtraPurchase.objects.create(
        user=portal_user,
        sku="OWN-SERVICE",
        title="My Service",
        extra_type=ExtraType.TIME_BASED,
        subtotal=Decimal("100.00"),
        currency="SAR",
        status=ExtraPurchaseStatus.PENDING_PAYMENT,
        invoice=own_invoice,
    )
    foreign_purchase = ExtraPurchase.objects.create(
        user=foreign_user,
        sku="FOREIGN-SERVICE",
        title="Foreign Service",
        extra_type=ExtraType.TIME_BASED,
        subtotal=Decimal("90.00"),
        currency="SAR",
        status=ExtraPurchaseStatus.PENDING_PAYMENT,
        invoice=foreign_invoice,
    )

    own_request = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.EXTRAS,
        requester=portal_user,
        status=UnifiedRequestStatus.NEW,
        summary="portal-own-request",
    )
    foreign_request = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.EXTRAS,
        requester=foreign_user,
        status=UnifiedRequestStatus.NEW,
        summary="portal-foreign-request",
    )

    client = Client()
    _login_dashboard_v2(client, user=portal_user)

    assert client.get(reverse("dashboard_v2:client_portal_home")).status_code == 200
    requests_response = client.get(reverse("dashboard_v2:client_portal_requests_list"))
    assert requests_response.status_code == 200
    requests_html = requests_response.content.decode("utf-8")
    assert "portal-own-request" in requests_html
    assert "portal-foreign-request" not in requests_html

    services_response = client.get(reverse("dashboard_v2:client_portal_services_list"))
    assert services_response.status_code == 200
    services_html = services_response.content.decode("utf-8")
    assert "OWN-SERVICE" in services_html
    assert "FOREIGN-SERVICE" not in services_html

    assert client.get(reverse("dashboard_v2:client_portal_request_detail", args=[own_request.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:client_portal_request_detail", args=[foreign_request.id])).status_code == 403
    assert client.get(reverse("dashboard_v2:client_portal_service_detail", args=[own_purchase.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:client_portal_service_detail", args=[foreign_purchase.id])).status_code == 404
    assert client.get(reverse("dashboard_v2:client_portal_payment_detail", args=[own_invoice.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:client_portal_payment_detail", args=[foreign_invoice.id])).status_code == 403


@pytest.mark.django_db
@override_settings(FEATURE_ANALYTICS_KPI_SURFACES=True)
def test_phase4_analytics_routes_and_dashboard_access():
    analytics_dashboard = _dashboard("analytics", "التحليلات")
    support_dashboard = _dashboard("support", "الدعم")

    analytics_user = User.objects.create_user(phone="0500400031", password="Pass12345!", is_staff=True)
    support_user = User.objects.create_user(phone="0500400032", password="Pass12345!", is_staff=True)

    _access_profile(analytics_user, level=AccessLevel.USER, dashboards=[analytics_dashboard])
    _access_profile(support_user, level=AccessLevel.USER, dashboards=[support_dashboard])

    analytics_client = Client()
    _login_dashboard_v2(analytics_client, user=analytics_user)
    assert analytics_client.get(reverse("dashboard_v2:analytics_overview")).status_code == 200
    assert analytics_client.get(reverse("dashboard_v2:analytics_reports_index"), {"section": "provider"}).status_code == 200
    assert analytics_client.get(reverse("dashboard_v2:analytics_exports")).status_code == 200

    support_client = Client()
    _login_dashboard_v2(support_client, user=support_user)
    assert support_client.get(reverse("dashboard_v2:analytics_overview")).status_code in (302, 403)
