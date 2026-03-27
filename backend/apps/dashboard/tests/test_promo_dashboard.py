import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.accounts.models import User, UserRole
from apps.billing.models import Invoice
from apps.billing.services import complete_mock_payment
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.promo.models import (
    PromoAdType,
    PromoFrequency,
    PromoOpsStatus,
    PromoPosition,
    PromoAsset,
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


def test_promo_save_request_persists_assignment_and_ops_status_and_reflects_in_table_rows():
    client = _dashboard_client()
    promo_request = _create_promo_request(plan_tier="riyadi")

    promo_dashboard, _ = Dashboard.objects.get_or_create(
        code="promo",
        defaults={"name_ar": "لوحة الترويج", "is_active": True, "sort_order": 30},
    )
    assignee = User.objects.create_user(
        phone="0554002099",
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    assignee_profile = UserAccessProfile.objects.create(user=assignee, level=AccessLevel.USER)
    assignee_profile.allowed_dashboards.add(promo_dashboard)

    response = client.post(
        reverse("dashboard:promo_dashboard"),
        {
            "action": "save_request",
            "promo_request_id": str(promo_request.id),
            "assigned_to": str(assignee.id),
            "ops_status": PromoOpsStatus.COMPLETED,
            "ops_note": "تم إنهاء التنفيذ بنجاح",
            "quote_note": "",
            "redirect_query": f"request={promo_request.id}",
        },
    )

    assert response.status_code == 302

    promo_request.refresh_from_db()
    assert promo_request.assigned_to_id == assignee.id
    assert promo_request.ops_status == PromoOpsStatus.COMPLETED

    listing = client.get(reverse("dashboard:promo_dashboard"), {"request": str(promo_request.id)})
    assert listing.status_code == 200

    rows = listing.context["promo_requests"]
    target = next(row for row in rows if row["id"] == promo_request.id)
    assert target["ops_status"] == promo_request.get_ops_status_display()
    assert target["assignee"] == (assignee.username or assignee.phone)


def test_paid_promo_request_moves_to_top_of_dashboard_requests_list():
    client = _dashboard_client()
    paid_request = _create_promo_request(plan_tier="pro")

    now = timezone.now()
    paid_request.status = PromoRequestStatus.PENDING_PAYMENT
    paid_request.ops_status = PromoOpsStatus.NEW
    paid_request.start_at = now
    paid_request.end_at = now + timezone.timedelta(days=3)
    paid_request.save(update_fields=["status", "ops_status", "start_at", "end_at", "updated_at"])

    newer_request = PromoRequest.objects.create(
        requester=paid_request.requester,
        title="طلب أحدث قبل الدفع",
        ad_type=PromoAdType.BUNDLE,
        start_at=now + timezone.timedelta(hours=1),
        end_at=now + timezone.timedelta(days=2),
        frequency=PromoFrequency.S60,
        position=PromoPosition.NORMAL,
        status=PromoRequestStatus.NEW,
        ops_status=PromoOpsStatus.NEW,
    )
    PromoRequestItem.objects.create(
        request=newer_request,
        service_type=PromoServiceType.FEATURED_SPECIALISTS,
        title="خدمة أحدث",
        start_at=newer_request.start_at,
        end_at=newer_request.end_at,
        frequency=PromoFrequency.S60,
        sort_order=1,
    )

    invoice = Invoice.objects.create(
        user=paid_request.requester,
        title="فاتورة طلب ترويج",
        subtotal="120.00",
        reference_type="promo_request",
        reference_id=paid_request.code or "",
    )
    paid_request.invoice = invoice
    paid_request.save(update_fields=["invoice", "updated_at"])

    complete_mock_payment(
        invoice=invoice,
        by_user=paid_request.requester,
        idempotency_key=f"dashboard-paid-order-{invoice.id}",
    )

    paid_request.refresh_from_db()
    assert paid_request.status == PromoRequestStatus.ACTIVE
    assert paid_request.invoice is not None
    assert paid_request.invoice.is_payment_effective() is True

    response = client.get(reverse("dashboard:promo_dashboard"))
    assert response.status_code == 200

    rows = response.context["promo_requests"]
    assert rows
    assert rows[0]["id"] == paid_request.id
    assert rows[0]["code"] == (paid_request.code or f"MD{paid_request.id:06d}")


def test_promo_request_form_limits_ops_status_choices_by_current_state():
    client = _dashboard_client()
    promo_request = _create_promo_request()
    promo_request.ops_status = PromoOpsStatus.NEW
    promo_request.save(update_fields=["ops_status", "updated_at"])

    response = client.get(reverse("dashboard:promo_dashboard"), {"request": str(promo_request.id)})
    assert response.status_code == 200

    form = response.context["request_form"]
    values = [value for value, _label in form.fields["ops_status"].choices]
    assert values == [PromoOpsStatus.NEW, PromoOpsStatus.IN_PROGRESS]


def test_promo_request_form_prefills_ops_note_from_saved_request_note():
    client = _dashboard_client()
    promo_request = _create_promo_request()
    promo_request.quote_note = "تعليق محفوظ سابقًا"
    promo_request.save(update_fields=["quote_note", "updated_at"])

    response = client.get(reverse("dashboard:promo_dashboard"), {"request": str(promo_request.id)})
    assert response.status_code == 200

    form = response.context["request_form"]
    assert (form["ops_note"].value() or "") == "تعليق محفوظ سابقًا"


def test_promo_request_close_button_url_removes_selected_request_param():
    client = _dashboard_client()
    promo_request = _create_promo_request()

    response = client.get(
        reverse("dashboard:promo_dashboard"),
        {
            "request": str(promo_request.id),
            "ops": PromoOpsStatus.IN_PROGRESS,
            "request_q": "qa",
        },
    )
    assert response.status_code == 200
    close_url = response.context["close_request_url"]
    assert "request=" not in close_url
    assert f"ops={PromoOpsStatus.IN_PROGRESS}" in close_url
    assert "request_q=qa" in close_url


def test_promo_save_request_blocks_skipping_ops_status_sequence():
    client = _dashboard_client()
    promo_request = _create_promo_request()
    promo_request.ops_status = PromoOpsStatus.NEW
    promo_request.save(update_fields=["ops_status", "updated_at"])

    response = client.post(
        reverse("dashboard:promo_dashboard"),
        {
            "action": "save_request",
            "promo_request_id": str(promo_request.id),
            "assigned_to": "",
            "ops_status": PromoOpsStatus.COMPLETED,
            "ops_note": "skip",
            "quote_note": "",
            "redirect_query": f"request={promo_request.id}",
        },
    )
    assert response.status_code == 302
    promo_request.refresh_from_db()
    assert promo_request.ops_status == PromoOpsStatus.NEW


def test_promo_dashboard_blocks_legacy_request_actions():
    client = _dashboard_client()
    promo_request = _create_promo_request()
    previous_ops_status = promo_request.ops_status

    response = client.post(
        reverse("dashboard:promo_dashboard"),
        {
            "action": "quote_request",
            "promo_request_id": str(promo_request.id),
            "assigned_to": "",
            "ops_status": PromoOpsStatus.COMPLETED,
            "ops_note": "legacy action should be blocked",
            "redirect_query": f"request={promo_request.id}",
        },
    )
    assert response.status_code == 302
    promo_request.refresh_from_db()
    assert promo_request.ops_status == previous_ops_status
    assert promo_request.invoice_id is None


def test_promo_inquiry_second_click_hides_details_and_keeps_selected_request():
    client = _dashboard_client()
    promo_request = _create_promo_request()

    requester = User.objects.create_user(
        phone="0554002030",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار لتجربة إظهار/إخفاء التفاصيل",
    )

    base_url = reverse("dashboard:promo_dashboard")
    open_response = client.get(
        base_url,
        {"inquiry": str(ticket.id), "request": str(promo_request.id)},
    )
    assert open_response.status_code == 200
    assert open_response.context["selected_inquiry"].id == ticket.id
    assert open_response.context["selected_request"].id == promo_request.id

    close_response = client.get(base_url, {"request": str(promo_request.id)})
    assert close_response.status_code == 200
    assert close_response.context["selected_inquiry"] is None
    assert close_response.context["selected_request"].id == promo_request.id


def test_promo_save_inquiry_redirect_updates_existing_inquiry_and_request_params():
    client = _dashboard_client()
    request_a = _create_promo_request()
    now = timezone.now()
    request_b = PromoRequest.objects.create(
        requester=request_a.requester,
        title="طلب ترويج بديل للربط",
        ad_type=PromoAdType.BUNDLE,
        start_at=now,
        end_at=now + timezone.timedelta(days=2),
        frequency=PromoFrequency.S60,
        position=PromoPosition.NORMAL,
        status=PromoRequestStatus.NEW,
        ops_status=PromoOpsStatus.NEW,
    )

    requester = User.objects.create_user(
        phone="0554002031",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار لاختبار تحديث باراميترات رابط الرجوع",
    )

    response = client.post(
        reverse("dashboard:promo_dashboard"),
        {
            "action": "save_inquiry",
            "ticket_id": str(ticket.id),
            "status": SupportTicketStatus.IN_PROGRESS,
            "description": ticket.description,
            "operator_comment": "تحديث البيانات وربط الطلب البديل",
            "linked_request_id": str(request_b.id),
            "redirect_query": f"inquiry=999999&request={request_a.id}&ops=in_progress",
        },
    )

    assert response.status_code == 302
    location = response["Location"]
    assert f"inquiry={ticket.id}" in location
    assert f"request={request_b.id}" in location
    assert f"request={request_a.id}" not in location
    assert "ops=in_progress" in location


def test_promo_inquiry_form_renders_insert_detail_link_icon_button():
    client = _dashboard_client()

    requester = User.objects.create_user(
        phone="0554002032",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار لإظهار زر إدراج الرابط",
    )

    response = client.get(reverse("dashboard:promo_dashboard"), {"inquiry": str(ticket.id)})
    assert response.status_code == 200

    html = response.content.decode("utf-8", errors="ignore")
    assert 'id="insertPromoDetailLinkBtn"' in html


def test_promo_module_home_banner_post_uses_selected_request_preview_asset():
    client = _dashboard_client()
    now = timezone.now()
    start_at = now + timezone.timedelta(days=2)
    end_at = start_at + timezone.timedelta(days=2)

    requester_a = User.objects.create_user(
        phone="0554002040",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    requester_b = User.objects.create_user(
        phone="0554002041",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )

    request_a = PromoRequest.objects.create(
        requester=requester_a,
        title="بنر A",
        ad_type=PromoAdType.BANNER_HOME,
        start_at=start_at,
        end_at=end_at,
        frequency=PromoFrequency.S60,
        position=PromoPosition.NORMAL,
        status=PromoRequestStatus.ACTIVE,
        ops_status=PromoOpsStatus.IN_PROGRESS,
    )
    request_b = PromoRequest.objects.create(
        requester=requester_b,
        title="بنر B",
        ad_type=PromoAdType.BANNER_HOME,
        start_at=start_at,
        end_at=end_at,
        frequency=PromoFrequency.S60,
        position=PromoPosition.NORMAL,
        status=PromoRequestStatus.ACTIVE,
        ops_status=PromoOpsStatus.IN_PROGRESS,
    )

    PromoAsset.objects.create(
        request=request_a,
        asset_type="image",
        title="asset-a",
        file=SimpleUploadedFile(
            "asset-a.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=requester_a,
    )
    asset_b = PromoAsset.objects.create(
        request=request_b,
        asset_type="image",
        title="asset-b",
        file=SimpleUploadedFile(
            "asset-b.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=requester_b,
    )

    response = client.post(
        reverse("dashboard:promo_module", kwargs={"module_key": "home_banner"}),
        data={
            "workflow_action": "preview_item",
            "request_id": str(request_b.id),
            "title": "معاينة بنر B",
            "start_at": start_at.strftime("%Y-%m-%dT%H:%M"),
            "end_at": end_at.strftime("%Y-%m-%dT%H:%M"),
            "attachment_specs": "",
            "operator_note": "",
        },
    )

    assert response.status_code == 200
    assert response.context["selected_request"].id == request_b.id
    assert response.context["selected_home_banner_asset"].id == asset_b.id


def test_home_banner_module_renders_live_preview_toolbar_and_preview_api_url():
    client = _dashboard_client()
    pr = _create_promo_request()
    PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.HOME_BANNER,
        title="بنر محفوظ",
        start_at=timezone.now(),
        end_at=timezone.now() + timezone.timedelta(days=3),
        sort_order=15,
    )
    PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="banner-live",
        file=SimpleUploadedFile(
            "banner-live.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=pr.requester,
    )

    response = client.get(reverse("dashboard:promo_module", kwargs={"module_key": "home_banner"}), {"request_id": str(pr.id)})

    assert response.status_code == 200
    html = response.content.decode("utf-8", errors="ignore")
    assert 'id="homeBannerModule"' in html
    assert 'id="homeBannerPreviewRequestBadge"' in html
    assert 'id="homeBannerPreviewSummary"' in html
    assert 'data-preview-api-url="' in html
    assert 'data-live-preview-focus="true"' in html
    assert 'name="workflow_action" value="preview_item"' not in html


def test_promo_module_request_preview_api_returns_selected_home_banner_asset():
    client = _dashboard_client()
    pr = _create_promo_request()
    asset = PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="banner-preview",
        file=SimpleUploadedFile(
            "banner-preview.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=pr.requester,
    )

    response = client.get(
        reverse("dashboard:promo_module_request_preview_api", kwargs={"module_key": "home_banner"}),
        {"request_id": str(pr.id)},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["request"]["id"] == str(pr.id)
    assert payload["request"]["requester_label"]
    assert payload["asset"]["type"] == "image"
    assert payload["asset"]["name"].endswith("banner-preview.png")
    assert payload["asset"]["url"].endswith(asset.file.name)


def test_promo_messages_module_renders_mobile_notification_and_chat_previews():
    client = _dashboard_client()
    pr = _create_promo_request()
    PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.PROMO_MESSAGES,
        title="رسالة محفوظة",
        send_at=timezone.now() + timezone.timedelta(days=1),
        message_body="رسالة ترويجية محفوظة",
        use_notification_channel=True,
        use_chat_channel=True,
        sort_order=20,
    )

    response = client.get(reverse("dashboard:promo_module", kwargs={"module_key": "promo_messages"}))

    assert response.status_code == 200
    html = response.content.decode("utf-8", errors="ignore")
    assert 'id="promoMessagePreviewPanel"' in html
    assert 'id="promoMessageNotificationList"' in html
    assert 'id="promoMessageChatThread"' in html
    assert 'id="promoMessageRequestBadge"' in html
    assert 'data-preview-api-url="' in html
    assert 'data-live-preview-focus="true"' in html
    assert 'name="workflow_action" value="preview_item"' not in html


def test_promo_module_request_preview_api_returns_selected_promo_message_asset():
    client = _dashboard_client()
    pr = _create_promo_request()
    item = PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.PROMO_MESSAGES,
        title="رسالة محفوظة",
        send_at=timezone.now() + timezone.timedelta(days=1),
        message_body="نص محفوظ",
        use_notification_channel=True,
        sort_order=18,
    )
    asset = PromoAsset.objects.create(
        request=pr,
        item=item,
        asset_type="image",
        title="message-asset",
        file=SimpleUploadedFile(
            "message-asset.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=pr.requester,
    )

    response = client.get(
        reverse("dashboard:promo_module_request_preview_api", kwargs={"module_key": "promo_messages"}),
        {"request_id": str(pr.id)},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["request"]["id"] == str(pr.id)
    assert payload["request"]["requester_label"]
    assert payload["asset"]["type"] == "image"
    assert payload["asset"]["name"].endswith("message-asset.png")
    assert payload["asset"]["url"].endswith(asset.file.name)


def test_sponsorship_module_renders_live_sponsor_preview_with_selected_asset():
    client = _dashboard_client()
    pr = _create_promo_request()
    item = PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.SPONSORSHIP,
        title="رعاية محفوظة",
        sponsor_name="الراعي الرسمي",
        sponsor_url="https://example.com/sponsor",
        sponsorship_months=3,
        start_at=timezone.now(),
        end_at=timezone.now() + timezone.timedelta(days=95),
        message_body="بطاقة الرعاية يجب أن تظهر مباشرة.",
        sort_order=30,
    )
    asset = PromoAsset.objects.create(
        request=pr,
        item=item,
        asset_type="image",
        title="sponsor-logo",
        file=SimpleUploadedFile(
            "sponsor-logo.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=pr.requester,
    )

    response = client.get(reverse("dashboard:promo_module", kwargs={"module_key": "sponsorship"}))

    assert response.status_code == 200
    assert response.context["selected_sponsorship_asset"].id == asset.id
    html = response.content.decode("utf-8", errors="ignore")
    assert 'id="sponsorshipPreviewPanel"' in html
    assert 'id="sponsorshipPreviewMedia"' in html
    assert 'id="sponsorshipPreviewTitle"' in html
    assert 'id="sponsorshipPreviewLink"' in html
    assert 'data-live-preview-focus="true"' in html
    assert 'name="workflow_action" value="preview_item"' not in html


def test_promo_messages_module_blocks_empty_message_without_attachment():
    client = _dashboard_client()
    pr = _create_promo_request()
    before_count = PromoRequestItem.objects.filter(request=pr, service_type=PromoServiceType.PROMO_MESSAGES).count()

    response = client.post(
        reverse("dashboard:promo_module", kwargs={"module_key": "promo_messages"}),
        data={
            "workflow_action": "approve_item",
            "request_id": str(pr.id),
            "message_body": "",
            "send_at": (timezone.now() + timezone.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M"),
            "use_notification_channel": "on",
        },
    )

    assert response.status_code == 200
    form = response.context["module_form"]
    assert "message_body" in form.errors
    after_count = PromoRequestItem.objects.filter(request=pr, service_type=PromoServiceType.PROMO_MESSAGES).count()
    assert after_count == before_count


def test_promo_messages_module_blocks_scheduling_in_the_past():
    client = _dashboard_client()
    pr = _create_promo_request()
    before_count = PromoRequestItem.objects.filter(request=pr, service_type=PromoServiceType.PROMO_MESSAGES).count()

    response = client.post(
        reverse("dashboard:promo_module", kwargs={"module_key": "promo_messages"}),
        data={
            "workflow_action": "approve_item",
            "request_id": str(pr.id),
            "message_body": "محتوى دعائي صالح",
            "send_at": (timezone.now() - timezone.timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M"),
            "use_notification_channel": "on",
        },
    )

    assert response.status_code == 200
    form = response.context["module_form"]
    assert "send_at" in form.errors
    after_count = PromoRequestItem.objects.filter(request=pr, service_type=PromoServiceType.PROMO_MESSAGES).count()
    assert after_count == before_count


def test_promo_messages_module_allows_single_gif_attachment_without_text():
    client = _dashboard_client()
    pr = _create_promo_request()
    before_count = PromoRequestItem.objects.filter(request=pr, service_type=PromoServiceType.PROMO_MESSAGES).count()
    gif_file = SimpleUploadedFile(
        "promo-message.gif",
        (
            b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!"
            b"\xf9\x04\x01\n\x00\x01\x00,\x00\x00\x00\x00\x01\x00\x01\x00"
            b"\x00\x02\x02D\x01\x00;"
        ),
        content_type="image/gif",
    )

    response = client.post(
        reverse("dashboard:promo_module", kwargs={"module_key": "promo_messages"}),
        data={
            "workflow_action": "approve_item",
            "request_id": str(pr.id),
            "message_body": "",
            "send_at": (timezone.now() + timezone.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M"),
            "use_chat_channel": "on",
            "media_file": gif_file,
        },
    )

    assert response.status_code == 302
    after_count = PromoRequestItem.objects.filter(request=pr, service_type=PromoServiceType.PROMO_MESSAGES).count()
    assert after_count == before_count + 1
    item = PromoRequestItem.objects.filter(request=pr, service_type=PromoServiceType.PROMO_MESSAGES).latest("id")
    asset = PromoAsset.objects.filter(item=item).latest("id")
    assert asset.asset_type == "image"
