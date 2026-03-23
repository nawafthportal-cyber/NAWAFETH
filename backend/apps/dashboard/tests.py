import pytest
from datetime import timedelta
from django.core.files.uploadedfile import SimpleUploadedFile
from django.http import HttpResponse
from django.test import Client, override_settings
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.audit.models import AuditAction, AuditLog
from apps.billing.models import Invoice
from apps.content.models import SiteLinks
from apps.core.models import PlatformConfig
from apps.dashboard.views import _compute_actions, _dashboard_allowed
from apps.dashboard.templatetags.dashboard_access import can_access
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.marketplace.models import RequestStatus, ServiceRequest
from apps.providers.models import Category, ProviderProfile, SubCategory
from apps.promo.models import HomeBanner, PromoAdType, PromoRequest, PromoRequestStatus, PromoServiceType
from apps.subscriptions.models import PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus
from apps.support.models import SupportTicket, SupportTicketType, SupportTicketStatus, SupportPriority, SupportTeam
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestStatus


@pytest.mark.django_db
def test_compute_actions_provider_unassigned_can_accept_when_sent(django_assert_num_queries):
	cat = Category.objects.create(name="تصميم", is_active=True)
	sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)

	client_user = User.objects.create_user(phone="0500000201")
	provider_user = User.objects.create_user(phone="0500000202")

	ProviderProfile.objects.create(
		user=provider_user,
		provider_type="individual",
		display_name="مزود",
		bio="bio",
		city="الرياض",
		years_experience=0,
	)

	sr = ServiceRequest.objects.create(
		client=client_user,
		subcategory=sub,
		title="طلب",
		description="وصف",
		request_type="competitive",
		status=RequestStatus.NEW,
		city="الرياض",
	)

	# For status=NEW, ProviderProfile.exists() is checked once.
	with django_assert_num_queries(1):
		actions = _compute_actions(provider_user, sr)

	assert actions["can_accept"] is True


@pytest.mark.django_db
def test_compute_actions_staff_does_not_query_providerprofile_when_sent(django_assert_num_queries):
	cat = Category.objects.create(name="تصميم", is_active=True)
	sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)

	client_user = User.objects.create_user(phone="0500000203")
	staff_user = User.objects.create_user(phone="0500000204", is_staff=True)

	sr = ServiceRequest.objects.create(
		client=client_user,
		subcategory=sub,
		title="طلب",
		description="وصف",
		request_type="competitive",
		status=RequestStatus.NEW,
		city="الرياض",
	)

	# No ProviderProfile lookup for staff
	with django_assert_num_queries(0):
		actions = _compute_actions(staff_user, sr)

	assert actions["can_accept"] is True
	assert actions["can_cancel"] is True


@pytest.mark.django_db
def test_dashboard_allowed_write_uses_content_dashboard_code():
	staff_user = User.objects.create_user(
		phone="0500000205",
		password="Pass12345!",
		is_staff=True,
	)
	content_dashboard, _ = Dashboard.objects.get_or_create(
		code="content",
		defaults={"name_ar": "إدارة المحتوى", "sort_order": 20},
	)
	ap = UserAccessProfile.objects.create(
		user=staff_user,
		level=AccessLevel.USER,
	)
	ap.allowed_dashboards.set([content_dashboard])

	assert _dashboard_allowed(staff_user, "content", write=True) is True


@pytest.mark.django_db
def test_dashboard_allowed_qa_denies_write_even_with_content_access():
	staff_user = User.objects.create_user(
		phone="0500000206",
		password="Pass12345!",
		is_staff=True,
	)
	content_dashboard, _ = Dashboard.objects.get_or_create(
		code="content",
		defaults={"name_ar": "إدارة المحتوى", "sort_order": 20},
	)
	ap = UserAccessProfile.objects.create(
		user=staff_user,
		level=AccessLevel.QA,
	)
	ap.allowed_dashboards.set([content_dashboard])

	assert _dashboard_allowed(staff_user, "content", write=False) is True
	assert _dashboard_allowed(staff_user, "content", write=True) is False


@pytest.mark.django_db
def test_dashboard_allowed_staff_without_access_profile_is_denied():
	staff_user = User.objects.create_user(
		phone="0500000207",
		password="Pass12345!",
		is_staff=True,
	)
	assert _dashboard_allowed(staff_user, "content", write=False) is False
	assert can_access(staff_user, "content", write=False) is False


@pytest.mark.django_db
def test_dashboard_allowed_admin_alias_maps_to_admin_control():
	staff_user = User.objects.create_user(
		phone="05000002070",
		password="Pass12345!",
		is_staff=True,
	)
	admin_dashboard, _ = Dashboard.objects.get_or_create(
		code="admin_control",
		defaults={"name_ar": "الإدارة", "sort_order": 1},
	)
	ap = UserAccessProfile.objects.create(
		user=staff_user,
		level=AccessLevel.USER,
	)
	ap.allowed_dashboards.set([admin_dashboard])

	assert _dashboard_allowed(staff_user, "admin", write=False) is True
	assert _dashboard_allowed(staff_user, "access", write=False) is True


@pytest.mark.django_db
def test_access_profile_update_action_updates_level_dashboards_and_expiry():
	admin_user = User.objects.create_user(
		phone="0500000208",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard, _ = Dashboard.objects.get_or_create(code="admin_control", defaults={"name_ar": "صلاحيات التشغيل", "sort_order": 10})
	content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
	support_dashboard, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 30})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)

	target_user = User.objects.create_user(phone="0500000209", password="Pass12345!", is_staff=True)
	target_ap = UserAccessProfile.objects.create(user=target_user, level=AccessLevel.USER)
	target_ap.allowed_dashboards.set([content_dashboard])

	c = Client()
	assert c.login(phone="0500000208", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()
	url = reverse("dashboard:access_profile_update_action", args=[target_ap.id])
	res = c.post(
		url,
		data={
			"level": AccessLevel.QA,
			"expires_at": "2030-01-01T10:30",
			"dashboard_ids": [str(support_dashboard.id)],
		},
	)
	assert res.status_code == 302

	target_ap.refresh_from_db()
	assert target_ap.level == AccessLevel.QA
	assert target_ap.expires_at is not None
	assert list(target_ap.allowed_dashboards.values_list("code", flat=True)) == ["support"]

	log = AuditLog.objects.filter(
		action=AuditAction.ACCESS_PROFILE_UPDATED,
		reference_type="backoffice.user_access_profile",
		reference_id=str(target_ap.id),
	).first()
	assert log is not None
	assert log.actor_id == admin_user.id
	assert log.extra.get("target_user_id") == target_user.id
	assert log.extra.get("before", {}).get("level") == AccessLevel.USER
	assert log.extra.get("after", {}).get("level") == AccessLevel.QA


@pytest.mark.django_db
def test_access_profile_toggle_revoke_action_blocks_self_and_allows_others():
	admin_user = User.objects.create_user(
		phone="0500000210",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard, _ = Dashboard.objects.get_or_create(code="admin_control", defaults={"name_ar": "إدارة الصلاحيات والتقارير", "sort_order": 1})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([access_dashboard])

	target_user = User.objects.create_user(phone="0500000211", password="Pass12345!", is_staff=True)
	target_ap = UserAccessProfile.objects.create(user=target_user, level=AccessLevel.USER)

	c = Client()
	assert c.login(phone="0500000210", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	# revoke other user
	url_other = reverse("dashboard:access_profile_toggle_revoke_action", args=[target_ap.id])
	res_other = c.post(url_other, data={})
	assert res_other.status_code == 302
	target_ap.refresh_from_db()
	assert target_ap.revoked_at is not None
	log_revoke = AuditLog.objects.filter(
		action=AuditAction.ACCESS_PROFILE_REVOKED,
		reference_type="backoffice.user_access_profile",
		reference_id=str(target_ap.id),
	).first()
	assert log_revoke is not None
	assert log_revoke.actor_id == admin_user.id

	# cannot revoke self
	self_ap = admin_user.access_profile
	url_self = reverse("dashboard:access_profile_toggle_revoke_action", args=[self_ap.id])
	res_self = c.post(url_self, data={})
	assert res_self.status_code == 302
	self_ap.refresh_from_db()
	assert self_ap.revoked_at is None

	# un-revoke other user
	res_unrevoke = c.post(url_other, data={})
	assert res_unrevoke.status_code == 302
	target_ap.refresh_from_db()
	assert target_ap.revoked_at is None
	log_unrevoke = AuditLog.objects.filter(
		action=AuditAction.ACCESS_PROFILE_UNREVOKED,
		reference_type="backoffice.user_access_profile",
		reference_id=str(target_ap.id),
	).first()
	assert log_unrevoke is not None
	assert log_unrevoke.actor_id == admin_user.id


@pytest.mark.django_db
def test_unified_requests_list_dashboard_page_and_csv_export():
	admin_user = User.objects.create_user(
		phone="0500000991",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000992", password="Pass12345!")
	UnifiedRequest.objects.create(
		request_type="promo",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="طلب ترويج تجريبي",
		source_app="promo",
		source_model="PromoRequest",
		source_object_id="77",
		assigned_team_code="promo",
		assigned_team_name="الترويج",
	)

	c = Client()
	assert c.login(phone="0500000991", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	url = reverse("dashboard:unified_requests_list")
	res = c.get(url)
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "الطلبات الموحدة" in html
	assert "إجمالي النتائج" in html
	assert "بانتظار الدفع" in html
	assert "MD الترويج" in html
	assert "AD التوثيق" in html
	assert ">1<" in html or " 1 " in html
	assert "/dashboard/promo/77/" in html
	assert "/dashboard/unified-requests/" in html

	res_csv = c.get(url, {"export": "csv", "type": "promo"})
	assert res_csv.status_code == 200
	assert "text/csv" in res_csv["Content-Type"]
	body = res_csv.content.decode("utf-8")
	assert "الكود" in body
	assert "طلب ترويج تجريبي" in body
	assert AuditLog.objects.filter(
		action=AuditAction.DATA_EXPORTED,
		reference_type="export",
		reference_id="unified_requests.csv",
	).exists()


@pytest.mark.django_db
def test_unified_request_detail_dashboard_page():
	admin_user = User.objects.create_user(
		phone="0500000995",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000996", password="Pass12345!")
	provider_profile = ProviderProfile.objects.create(
		user=requester,
		provider_type="individual",
		display_name="مختص تجريبي",
		bio="bio",
		city="الرياض",
		years_experience=1,
	)
	invoice = Invoice.objects.create(
		user=requester,
		title="فاتورة توثيق",
		subtotal="100.00",
		reference_type="verification_request",
		reference_id="15",
	)
	ur = UnifiedRequest.objects.create(
		request_type="verification",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="طلب توثيق",
		source_app="verification",
		source_model="VerificationRequest",
		source_object_id="15",
		assigned_team_code="verify",
		assigned_team_name="التوثيق",
	)
	ur.status_logs.create(from_status="", to_status="pending_payment", changed_by=admin_user, note="created")
	ur.assignment_logs.create(from_team_code="", to_team_code="verify", changed_by=admin_user)
	UnifiedRequestMetadata.objects.create(request=ur, payload={"badge_type": "blue", "invoice_id": invoice.id})

	c = Client()
	assert c.login(phone="0500000995", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:unified_request_detail", args=[ur.id]))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "طلب موحد" in html
	assert "Metadata" in html
	assert "/dashboard/verification/15/" in html
	assert f"/dashboard/requests/?q={requester.phone}" in html
	assert "/dashboard/billing/?q=" in html
	assert (invoice.code or str(invoice.id)) in html
	assert f"/dashboard/billing/?q={requester.phone}" in html
	assert f"/dashboard/providers/{provider_profile.id}/" in html


@pytest.mark.django_db
def test_unified_request_detail_hides_quick_links_without_target_dashboard_access():
	staff_user = User.objects.create_user(
		phone="0500000999",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000988", password="Pass12345!")
	ProviderProfile.objects.create(
		user=requester,
		provider_type="individual",
		display_name="مختص",
		bio="bio",
		city="الرياض",
		years_experience=1,
	)
	invoice = Invoice.objects.create(
		user=requester,
		title="فاتورة",
		subtotal="50.00",
		reference_type="verification_request",
		reference_id="22",
	)
	ur = UnifiedRequest.objects.create(
		request_type="verification",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="طلب توثيق",
		source_app="verification",
		source_model="VerificationRequest",
		source_object_id="22",
	)
	UnifiedRequestMetadata.objects.create(request=ur, payload={"invoice_id": invoice.id})

	c = Client()
	assert c.login(phone=staff_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:unified_request_detail", args=[ur.id]))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "روابط تشغيل" in html
	assert "/dashboard/verification/22/" not in html
	assert "/dashboard/billing/?q=" not in html
	assert f"/dashboard/requests/?q={requester.phone}" not in html
	assert "/dashboard/providers/" not in html


@pytest.mark.django_db
def test_unified_requests_list_filters_by_date_range():
	admin_user = User.objects.create_user(
		phone="0500000997",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000998", password="Pass12345!")
	old_row = UnifiedRequest.objects.create(
		request_type="promo",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="قديم",
		source_app="promo",
		source_model="PromoRequest",
		source_object_id="101",
	)
	new_row = UnifiedRequest.objects.create(
		request_type="promo",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="حديث",
		source_app="promo",
		source_model="PromoRequest",
		source_object_id="102",
	)
	UnifiedRequest.objects.filter(pk=old_row.pk).update(created_at=timezone.now() - timedelta(days=10))
	old_row.refresh_from_db()
	new_row.refresh_from_db()

	c = Client()
	assert c.login(phone="0500000997", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	today = timezone.localdate().isoformat()
	res = c.get(reverse("dashboard:unified_requests_list"), {"from": today, "to": today})
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "حديث" in html
	assert "قديم" not in html


@pytest.mark.django_db
def test_unified_requests_list_filters_by_has_invoice():
	admin_user = User.objects.create_user(
		phone="0500000977",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000978", password="Pass12345!")
	with_invoice = UnifiedRequest.objects.create(
		request_type="verification",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="سجل بفاتورة",
		source_app="verification",
		source_model="VerificationRequest",
		source_object_id="501",
	)
	no_invoice = UnifiedRequest.objects.create(
		request_type="support",
		requester=requester,
		status="new",
		priority="normal",
		summary="سجل بدون فاتورة",
		source_app="support",
		source_model="SupportTicket",
		source_object_id="502",
	)
	UnifiedRequestMetadata.objects.create(request=with_invoice, payload={"invoice_id": 123})
	UnifiedRequestMetadata.objects.create(request=no_invoice, payload={"ticket_type": "technical"})

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	url = reverse("dashboard:unified_requests_list")
	res_yes = c.get(url, {"has_invoice": "1"})
	assert res_yes.status_code == 200
	html_yes = res_yes.content.decode("utf-8")
	assert "سجل بفاتورة" in html_yes
	assert "سجل بدون فاتورة" not in html_yes

	res_no = c.get(url, {"has_invoice": "0"})
	assert res_no.status_code == 200
	html_no = res_no.content.decode("utf-8")
	assert "سجل بفاتورة" not in html_no
	assert "سجل بدون فاتورة" in html_no


@pytest.mark.django_db
def test_unified_requests_list_filters_by_open_only_and_has_assignee():
	admin_user = User.objects.create_user(
		phone="0500000971",
		password="Pass12345!",
		is_staff=True,
	)
	assignee_user = User.objects.create_user(
		phone="0500000972",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000973", password="Pass12345!")
	UnifiedRequest.objects.create(
		request_type="helpdesk",
		requester=requester,
		status="new",
		priority="normal",
		summary="مفتوح غير مكلّف",
		source_app="support",
		source_model="SupportTicket",
		source_object_id="601",
		assigned_user=None,
	)
	UnifiedRequest.objects.create(
		request_type="helpdesk",
		requester=requester,
		status="in_progress",
		priority="normal",
		summary="مفتوح مكلّف",
		source_app="support",
		source_model="SupportTicket",
		source_object_id="602",
		assigned_user=assignee_user,
	)
	UnifiedRequest.objects.create(
		request_type="helpdesk",
		requester=requester,
		status="completed",
		priority="normal",
		summary="مغلق غير مكلّف",
		source_app="support",
		source_model="SupportTicket",
		source_object_id="603",
		assigned_user=None,
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:unified_requests_list"), {"open_only": "1", "has_assignee": "0"})
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "مفتوح غير مكلّف" in html
	assert "مفتوح مكلّف" not in html
	assert "مغلق غير مكلّف" not in html


@pytest.mark.django_db
def test_unified_requests_list_preset_open_unassigned():
	admin_user = User.objects.create_user(
		phone="0500000961",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000962", password="Pass12345!")
	UnifiedRequest.objects.create(
		request_type="promo",
		requester=requester,
		status="new",
		priority="normal",
		summary="Preset match",
		source_app="promo",
		source_model="PromoRequest",
		source_object_id="701",
	)
	UnifiedRequest.objects.create(
		request_type="promo",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="Preset no (status)",
		source_app="promo",
		source_model="PromoRequest",
		source_object_id="702",
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:unified_requests_list"), {"preset": "open_unassigned"})
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "فلاتر سريعة" in html
	assert "مفتوح وغير مكلّف" in html
	assert "Preset match" in html
	assert "Preset no (status)" not in html


@pytest.mark.django_db
def test_dashboard_home_shows_unified_request_kpis():
	admin_user = User.objects.create_user(
		phone="0500000993",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000994", password="Pass12345!")
	UnifiedRequest.objects.create(
		request_type="helpdesk",
		requester=requester,
		status="new",
		priority="normal",
		summary="بلاغ تجريبي",
		source_app="support",
		source_model="SupportTicket",
		source_object_id="1",
	)
	UnifiedRequest.objects.create(
		request_type="promo",
		requester=requester,
		status="pending_payment",
		priority="normal",
		summary="إعلان تجريبي",
		source_app="promo",
		source_model="PromoRequest",
		source_object_id="2",
	)
	UnifiedRequest.objects.create(
		request_type="verification",
		requester=requester,
		status="active",
		priority="normal",
		summary="توثيق مفعل",
		source_app="verification",
		source_model="VerificationRequest",
		source_object_id="3",
	)
	UnifiedRequest.objects.create(
		request_type="extras",
		requester=requester,
		status="completed",
		priority="normal",
		summary="إضافة مكتملة",
		source_app="extras",
		source_model="ExtraPurchase",
		source_object_id="4",
	)

	c = Client()
	assert c.login(phone="0500000993", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:home"))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "الطلبات التشغيلية الموحدة" in html
	assert "/dashboard/unified-requests/" in html
	assert "/dashboard/promo/2/" in html
	assert "const uni =" in html
	assert "الطلبات الموحدة" in html


@pytest.mark.django_db
def test_dashboard_home_hides_latest_requests_link_without_content_access():
	staff_user = User.objects.create_user(
		phone="0500000990",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 10})
	UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER).allowed_dashboards.set([analytics_dashboard])

	c = Client()
	assert c.login(phone=staff_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:home"))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "آخر الطلبات" in html
	assert '<a class="px-4 py-2 rounded-lg bg-gradient-to-r from-purple-600 to-indigo-600 text-white hover:shadow-lg transition-all text-sm font-semibold" href="/dashboard/requests/">' not in html
	assert "cursor-not-allowed" in html


@pytest.mark.django_db
def test_subscriptions_ops_page_shows_inquiries_and_requests():
	admin_user = User.objects.create_user(phone="0500000951", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 10})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000952", password="Pass12345!")
	team = SupportTeam.objects.create(code="subs", name_ar="إدارة الاشتراكات", is_active=True, sort_order=1)
	ticket = SupportTicket.objects.create(
		requester=requester,
		ticket_type=SupportTicketType.SUBS,
		status=SupportTicketStatus.NEW,
		priority=SupportPriority.NORMAL,
		description="استفسار اشتراك",
		assigned_team=team,
	)
	plan = SubscriptionPlan.objects.create(code="PIONEER", title="الريادية", period="year", price="199.00", is_active=True)
	invoice = Invoice.objects.create(user=requester, title="فاتورة اشتراك", subtotal="199.00", reference_type="subscription", reference_id="1")
	sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT, invoice=invoice)
	UnifiedRequest.objects.create(
		request_type="subscription",
		requester=requester,
		status="pending_payment",
		priority="normal",
		source_app="subscriptions",
		source_model="Subscription",
		source_object_id=str(sub.id),
		assigned_team_code="subs",
		assigned_team_name="الاشتراكات",
		summary="اشتراك الريادية",
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:subscriptions_ops"))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "فريق إدارة الاشتراكات" in html
	assert "قائمة استفسارات الاشتراكات" in html
	assert "قائمة طلبات الاشتراكات" in html
	assert (ticket.code or "HD") in html
	assert "الريادية" in html
	assert reverse("dashboard:subscription_request_detail", args=[sub.id]) in html


@pytest.mark.django_db
def test_subscription_request_detail_page_shows_invoice_and_unified_links():
	admin_user = User.objects.create_user(phone="0500000953", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 10})
	billing_dashboard, _ = Dashboard.objects.get_or_create(code="billing", defaults={"name_ar": "الفوترة", "sort_order": 11})
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 12})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard, billing_dashboard, analytics_dashboard])

	requester = User.objects.create_user(phone="0500000954", password="Pass12345!")
	plan = SubscriptionPlan.objects.create(code="PRO", title="الاحترافية", period="year", price="999.00", is_active=True)
	invoice = Invoice.objects.create(user=requester, title="فاتورة اشتراك", subtotal="999.00", reference_type="subscription", reference_id="55")
	sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT, invoice=invoice)
	ur = UnifiedRequest.objects.create(
		request_type="subscription",
		requester=requester,
		status="pending_payment",
		priority="normal",
		source_app="subscriptions",
		source_model="Subscription",
		source_object_id=str(sub.id),
		summary="اشتراك الاحترافية",
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:subscription_request_detail", args=[sub.id]))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "تفاصيل طلب الاشتراك" in html
	assert "ملخص طلب الترقية والتكلفة" in html
	assert reverse("dashboard:unified_request_detail", args=[ur.id]) in html
	assert "/dashboard/billing/?q=" in html


@pytest.mark.django_db
def test_subscription_request_detail_adds_operational_note():
	admin_user = User.objects.create_user(phone="0500000941", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 15})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000942", password="Pass12345!")
	plan = SubscriptionPlan.objects.create(code="NOTE_SUB", title="الريادية", period="year", price="199.00", is_active=True)
	sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT)
	ur = UnifiedRequest.objects.create(
		request_type="subscription",
		requester=requester,
		status="pending_payment",
		priority="normal",
		source_app="subscriptions",
		source_model="Subscription",
		source_object_id=str(sub.id),
		summary="اشتراك الريادية",
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	note_text = "تم التواصل مع العميل وتم توضيح خطوات الدفع."
	res_post = c.post(
		reverse("dashboard:subscription_request_add_note_action", args=[sub.id]),
		data={"note": note_text},
	)
	assert res_post.status_code == 302

	md = UnifiedRequestMetadata.objects.get(request=ur)
	assert isinstance(md.payload.get("ops_notes"), list)
	assert md.payload["ops_notes"][-1]["text"] == note_text
	audit = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_REQUEST_NOTE_ADDED,
		reference_type="subscription_request.unified",
		reference_id=str(ur.id),
	).first()
	assert audit is not None
	assert audit.extra.get("subscription_id") == sub.id

	res = c.get(reverse("dashboard:subscription_request_detail", args=[sub.id]))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "ملاحظات تشغيلية (داخلية)" in html
	assert note_text in html


@pytest.mark.django_db
def test_subscription_request_detail_quick_status_updates_unified_request():
	admin_user = User.objects.create_user(phone="0500000921", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 18})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000922", password="Pass12345!")
	plan = SubscriptionPlan.objects.create(code="SD_STATUS", title="الريادية", period="year", price="199.00", is_active=True)
	sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT)
	ur = UnifiedRequest.objects.create(
		request_type="subscription",
		requester=requester,
		status="new",
		priority="normal",
		source_app="subscriptions",
		source_model="Subscription",
		source_object_id=str(sub.id),
		summary="طلب اشتراك",
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.post(
		reverse("dashboard:subscription_request_set_status_action", args=[sub.id]),
		data={"status": "in_progress", "note": "بدأت المعالجة"},
	)
	assert res.status_code == 302
	ur.refresh_from_db()
	assert ur.status == "in_progress"
	log = ur.status_logs.first()
	assert log is not None
	assert log.to_status == "in_progress"

	res2 = c.post(
		reverse("dashboard:subscription_request_set_status_action", args=[sub.id]),
		data={"status": "completed"},
	)
	assert res2.status_code == 302
	ur.refresh_from_db()
	assert ur.status == "closed"
	assert ur.closed_at is not None
	audit = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_REQUEST_STATUS_CHANGED,
		reference_type="subscription_request.unified",
		reference_id=str(ur.id),
	).first()
	assert audit is not None
	assert audit.extra.get("subscription_id") == sub.id


@pytest.mark.django_db
def test_subscription_request_detail_assigns_unified_request():
	admin_user = User.objects.create_user(phone="0500000911", password="Pass12345!", is_staff=True)
	assignee_user = User.objects.create_user(phone="0500000912", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 19})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])
	UserAccessProfile.objects.create(user=assignee_user, level=AccessLevel.USER).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000913", password="Pass12345!")
	plan = SubscriptionPlan.objects.create(code="SD_ASSIGN", title="الأساسية", period="year", price="100.00", is_active=True)
	sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT)
	ur = UnifiedRequest.objects.create(
		request_type="subscription",
		requester=requester,
		status="new",
		priority="normal",
		source_app="subscriptions",
		source_model="Subscription",
		source_object_id=str(sub.id),
		summary="طلب اشتراك",
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.post(
		reverse("dashboard:subscription_request_assign_action", args=[sub.id]),
		data={"assigned_to": str(assignee_user.id), "note": "تكليف مباشر"},
	)
	assert res.status_code == 302
	ur.refresh_from_db()
	assert ur.assigned_user_id == assignee_user.id
	assert ur.assigned_team_code == "subs"
	assign_log = ur.assignment_logs.first()
	assert assign_log is not None
	assert assign_log.to_user_id == assignee_user.id
	audit = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_REQUEST_ASSIGNED,
		reference_type="subscription_request.unified",
		reference_id=str(ur.id),
	).first()
	assert audit is not None
	assert audit.extra.get("to_user_id") == assignee_user.id


@pytest.mark.django_db
def test_subscription_account_detail_page_and_actions():
	admin_user = User.objects.create_user(phone="0500000955", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 20})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000956", password="Pass12345!")
	ProviderProfile.objects.create(
		user=requester,
		provider_type="individual",
		display_name="Requester Provider",
		bio="bio",
	)
	plan_basic = SubscriptionPlan.objects.create(code="BASIC_Y2", title="الأساسية", period="year", price="100.00", is_active=True)
	plan_pro = SubscriptionPlan.objects.create(code="PRO_Y2", tier=PlanTier.PRO, title="الاحترافية", period="year", price="999.00", is_active=True)
	invoice = Invoice.objects.create(user=requester, title="فاتورة اشتراك", subtotal="100.00", reference_type="subscription", reference_id="77")
	sub = Subscription.objects.create(user=requester, plan=plan_basic, status=SubscriptionStatus.ACTIVE, invoice=invoice)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	# detail page
	res = c.get(reverse("dashboard:subscription_account_detail", args=[sub.id]))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "تفاصيل الحساب المشترك" in html
	assert "تجديد الاشتراك" in html
	assert "ترقية الاشتراك" in html
	assert "تنبيهات الاشتراك" in html
	assert "سجل عمليات الاشتراك" in html

	# renew -> new pending subscription request created
	count_before = Subscription.objects.count()
	res_renew = c.post(reverse("dashboard:subscription_account_renew_action", args=[sub.id]), data={})
	assert res_renew.status_code == 302
	assert Subscription.objects.count() == count_before + 1
	newest = Subscription.objects.order_by("-id").first()
	assert newest is not None
	assert newest.user_id == requester.id
	assert newest.plan_id == plan_basic.id
	assert newest.status == SubscriptionStatus.PENDING_PAYMENT
	audit_renew = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_ACCOUNT_RENEW_REQUESTED,
		reference_type="subscription.account",
		reference_id=str(sub.id),
	).first()
	assert audit_renew is not None
	assert audit_renew.extra.get("new_subscription_id") == newest.id

	# upgrade -> another new pending subscription with selected plan
	count_before_upgrade = Subscription.objects.count()
	res_upgrade = c.post(
		reverse("dashboard:subscription_account_upgrade_action", args=[sub.id]),
		data={"plan_id": str(plan_pro.id)},
	)
	assert res_upgrade.status_code == 302
	assert Subscription.objects.count() == count_before_upgrade + 1
	upgraded = Subscription.objects.order_by("-id").first()
	assert upgraded is not None
	assert upgraded.plan_id == plan_pro.id
	assert upgraded.status == SubscriptionStatus.PENDING_PAYMENT
	audit_upgrade = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_ACCOUNT_UPGRADE_REQUESTED,
		reference_type="subscription.account",
		reference_id=str(sub.id),
	).first()
	assert audit_upgrade is not None
	assert audit_upgrade.extra.get("to_plan_id") == plan_pro.id
	assert audit_upgrade.extra.get("new_subscription_id") == upgraded.id

	# cancel (soft)
	res_cancel = c.post(reverse("dashboard:subscription_account_cancel_action", args=[sub.id]), data={})
	assert res_cancel.status_code == 302
	sub.refresh_from_db()
	assert sub.status == SubscriptionStatus.CANCELLED
	audit_cancel = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_ACCOUNT_CANCELLED,
		reference_type="subscription.account",
		reference_id=str(sub.id),
	).first()
	assert audit_cancel is not None
	assert audit_cancel.extra.get("status") == SubscriptionStatus.CANCELLED


@pytest.mark.django_db
def test_subscription_account_detail_adds_operational_note():
	admin_user = User.objects.create_user(phone="0500000931", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 25})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000932", password="Pass12345!")
	plan = SubscriptionPlan.objects.create(code="ACC_NOTE", title="الأساسية", period="year", price="100.00", is_active=True)
	sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.ACTIVE)
	ur = UnifiedRequest.objects.create(
		request_type="subscription",
		requester=requester,
		status="active",
		priority="normal",
		source_app="subscriptions",
		source_model="Subscription",
		source_object_id=str(sub.id),
		summary="اشتراك حساب",
	)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	note_text = "تمت مراجعة بيانات الاشتراك وتأكيد صلاحية المدة."
	res_post = c.post(reverse("dashboard:subscription_account_add_note_action", args=[sub.id]), data={"note": note_text})
	assert res_post.status_code == 302

	md = UnifiedRequestMetadata.objects.get(request=ur)
	assert md.payload["account_ops_notes"][-1]["text"] == note_text
	audit = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_ACCOUNT_NOTE_ADDED,
		reference_type="subscription_account.unified",
		reference_id=str(ur.id),
	).first()
	assert audit is not None
	assert audit.extra.get("subscription_id") == sub.id

	res = c.get(reverse("dashboard:subscription_account_detail", args=[sub.id]))
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert "ملاحظات تشغيلية للحساب" in html
	assert note_text in html


@pytest.mark.django_db
def test_subscription_plans_compare_and_upgrade_summary_pages():
	admin_user = User.objects.create_user(phone="0500000957", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 30})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000958", password="Pass12345!")
	plan_basic = SubscriptionPlan.objects.create(code="BASIC_CMP", title="الأساسية", period="year", price="100.00", features=["verify_blue"], is_active=True)
	plan_pro = SubscriptionPlan.objects.create(code="PRO_CMP", title="الاحترافية", period="year", price="999.00", features=["verify_blue", "verify_green", "promo_ads"], is_active=True)
	sub = Subscription.objects.create(user=requester, plan=plan_basic, status=SubscriptionStatus.ACTIVE)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res_compare = c.get(reverse("dashboard:subscription_plans_compare"), {"subscription_id": str(sub.id)})
	assert res_compare.status_code == 200
	html_compare = res_compare.content.decode("utf-8")
	assert "الصفحة التفصيلية لخيارات الاشتراك" in html_compare
	assert "فئة الباقة" in html_compare
	assert "رسوم التوثيق الأزرق" in html_compare
	assert "الأساسية" in html_compare
	assert "الاحترافية" in html_compare
	assert "توثيق (شارة زرقاء)" not in html_compare

	res_summary = c.get(reverse("dashboard:subscription_upgrade_summary", args=[sub.id]), {"plan_id": str(plan_pro.id)})
	assert res_summary.status_code == 200
	html_summary = res_summary.content.decode("utf-8")
	assert "ملخص طلب الترقية والتكلفة" in html_summary
	assert "VAT" in html_summary
	assert "999.00" in html_summary or "999" in html_summary
	assert reverse("dashboard:subscription_account_upgrade_action", args=[sub.id]) in html_summary


@pytest.mark.django_db
def test_subscription_payment_checkout_and_success_flow():
	admin_user = User.objects.create_user(phone="0500000959", password="Pass12345!", is_staff=True)
	subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 40})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

	requester = User.objects.create_user(phone="0500000960", password="Pass12345!")
	plan = SubscriptionPlan.objects.create(code="PAYFLOW", title="الريادية", period="year", price="199.00", is_active=True)
	invoice = Invoice.objects.create(user=requester, title="فاتورة اشتراك", subtotal="199.00", reference_type="subscription", reference_id="88")
	invoice.mark_pending()
	invoice.save(update_fields=["status", "paid_at", "cancelled_at", "updated_at"])
	sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT, invoice=invoice)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res_checkout = c.get(reverse("dashboard:subscription_payment_checkout", args=[sub.id]))
	assert res_checkout.status_code == 200
	html_checkout = res_checkout.content.decode("utf-8")
	assert "شاشة الدفع" in html_checkout
	assert "دفع" in html_checkout
	audit_checkout = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_PAYMENT_CHECKOUT_OPENED,
		reference_type="subscription.payment",
		reference_id=str(sub.id),
	).first()
	assert audit_checkout is not None
	assert audit_checkout.extra.get("invoice_id") == invoice.id

	res_pay = c.post(reverse("dashboard:subscription_payment_complete_action", args=[sub.id]), data={})
	assert res_pay.status_code == 302
	assert reverse("dashboard:subscription_payment_success", args=[sub.id]) in res_pay["Location"]

	sub.refresh_from_db()
	invoice.refresh_from_db()
	assert invoice.status == "paid"
	assert sub.status == SubscriptionStatus.ACTIVE
	audit_pay = AuditLog.objects.filter(
		action=AuditAction.SUBSCRIPTION_PAYMENT_COMPLETED,
		reference_type="subscription.payment",
		reference_id=str(sub.id),
	).first()
	assert audit_pay is not None
	assert audit_pay.extra.get("invoice_id") == invoice.id
	assert audit_pay.extra.get("invoice_status") == "paid"

	res_success = c.get(reverse("dashboard:subscription_payment_success", args=[sub.id]))
	assert res_success.status_code == 200
	html_success = res_success.content.decode("utf-8")
	assert "تمت عملية سداد الرسوم بنجاح" in html_success


@pytest.mark.django_db
def test_features_overview_shows_verification_fees_by_subscription_tier():
	admin_user = User.objects.create_user(phone="0500000961", password="Pass12345!", is_staff=True)
	analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 50})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([analytics_dashboard])

	requester = User.objects.create_user(phone="0500000962", password="Pass12345!")
	plan = SubscriptionPlan.objects.create(
		code="PRO_ANALYTICS",
		tier="pro",
		title="الاحترافية",
		period="year",
		price="999.00",
		features=["verify_blue", "verify_green", "promo_ads"],
		is_active=True,
	)
	Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.ACTIVE)

	c = Client()
	assert c.login(phone=admin_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:features_overview"), {"q": requester.phone})
	assert res.status_code == 200
	html = res.content.decode("utf-8")
	assert requester.phone in html
	assert "فئة الباقة" in html
	assert "احترافية" in html
	assert "0.00 ر.س" in html


@pytest.mark.django_db
def test_access_profile_create_action_creates_profile_and_audit():
	admin_user = User.objects.create_user(
		phone="0500000212",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard, _ = Dashboard.objects.get_or_create(code="admin_control", defaults={"name_ar": "صلاحيات التشغيل", "sort_order": 10})
	content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([access_dashboard])

	target_user = User.objects.create_user(phone="0500000213", password="Pass12345!")
	assert not hasattr(target_user, "access_profile")

	c = Client()
	assert c.login(phone="0500000212", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()
	url = reverse("dashboard:access_profile_create_action")
	res = c.post(
		url,
		data={
			"target_phone": target_user.phone,
			"level": AccessLevel.USER,
			"expires_at": "2031-01-01T11:00",
			"dashboard_ids": [str(content_dashboard.id)],
		},
	)
	assert res.status_code == 302

	target_ap = UserAccessProfile.objects.get(user=target_user)
	assert target_ap.level == AccessLevel.USER
	assert list(target_ap.allowed_dashboards.values_list("code", flat=True)) == ["content"]
	target_user.refresh_from_db()
	assert target_user.is_staff is True

	log = AuditLog.objects.filter(
		action=AuditAction.ACCESS_PROFILE_CREATED,
		reference_type="backoffice.user_access_profile",
		reference_id=str(target_ap.id),
	).first()
	assert log is not None
	assert log.actor_id == admin_user.id
	assert log.extra.get("created") is True


@pytest.mark.django_db
def test_requests_list_export_xlsx_returns_xlsx_file():
	staff_user = User.objects.create_user(phone="0500000991", password="Pass12345!", is_staff=True)
	content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
	UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN).allowed_dashboards.set([content_dashboard])

	cat = Category.objects.create(name="تصميم", is_active=True)
	sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)
	client_user = User.objects.create_user(phone="0500000992")
	ServiceRequest.objects.create(
		client=client_user,
		subcategory=sub,
		title="طلب",
		description="وصف",
		request_type="competitive",
		status=RequestStatus.NEW,
		city="الرياض",
	)

	c = Client()
	assert c.login(phone=staff_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	url = reverse("dashboard:requests_list") + "?export=xlsx"
	res = c.get(url)
	assert res.status_code == 200
	assert res["Content-Type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
	assert res.content[:2] == b"PK"


@pytest.mark.django_db
def test_requests_list_export_pdf_returns_pdf_file():
    pytest.importorskip("reportlab")
    staff_user = User.objects.create_user(phone="0500000993", password="Pass12345!", is_staff=True)
    content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
    UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN).allowed_dashboards.set([content_dashboard])

    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)
    client_user = User.objects.create_user(phone="0500000994")
    ServiceRequest.objects.create(
        client=client_user,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type="competitive",
        status=RequestStatus.NEW,
        city="الرياض",
    )

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    url = reverse("dashboard:requests_list") + "?export=pdf"
    res = c.get(url)
    assert res.status_code == 200
    assert res["Content-Type"] == "application/pdf"
    assert res.content[:4] == b"%PDF"


@pytest.mark.django_db
def test_access_profile_create_action_updates_existing_profile():
	admin_user = User.objects.create_user(
		phone="0500000214",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard, _ = Dashboard.objects.get_or_create(code="admin_control", defaults={"name_ar": "صلاحيات التشغيل", "sort_order": 10})
	content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
	support_dashboard, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 30})
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([access_dashboard])

	target_user = User.objects.create_user(phone="0500000215", password="Pass12345!")
	target_ap = UserAccessProfile.objects.create(user=target_user, level=AccessLevel.QA)
	target_ap.allowed_dashboards.set([support_dashboard])

	c = Client()
	assert c.login(phone="0500000214", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()
	url = reverse("dashboard:access_profile_create_action")
	res = c.post(
		url,
		data={
			"target_phone": target_user.phone,
			"level": AccessLevel.POWER,
			"dashboard_ids": [str(content_dashboard.id)],
		},
	)
	assert res.status_code == 302

	target_ap.refresh_from_db()
	assert target_ap.level == AccessLevel.POWER
	assert list(target_ap.allowed_dashboards.values_list("code", flat=True)) == ["content"]
	target_user.refresh_from_db()
	assert target_user.is_staff is True

	log = AuditLog.objects.filter(
		action=AuditAction.ACCESS_PROFILE_UPDATED,
		reference_type="backoffice.user_access_profile",
		reference_id=str(target_ap.id),
	).first()
	assert log is not None
	assert log.actor_id == admin_user.id
	assert log.extra.get("created") is False


@pytest.mark.django_db
def test_staff_cannot_access_unallowed_dashboard_page_and_is_redirected():
	staff_user = User.objects.create_user(
		phone="0500000220",
		password="Pass12345!",
		is_staff=True,
	)
	content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
	support_dashboard, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 30})
	UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER).allowed_dashboards.set([content_dashboard])

	c = Client()
	assert c.login(phone=staff_user.phone, password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()

	res = c.get(reverse("dashboard:support_tickets_list"))
	assert res.status_code == 302
	assert reverse("dashboard:requests_list") in res["Location"]


@pytest.mark.django_db
def test_guard_prevents_demoting_last_active_admin():
	admin_user = User.objects.create_user(
		phone="0500000216",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard, _ = Dashboard.objects.get_or_create(code="admin_control", defaults={"name_ar": "صلاحيات التشغيل", "sort_order": 10})
	content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
	admin_ap = UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)
	admin_ap.allowed_dashboards.set([access_dashboard, content_dashboard])

	c = Client()
	assert c.login(phone="0500000216", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()
	url = reverse("dashboard:access_profile_update_action", args=[admin_ap.id])
	res = c.post(
		url,
		data={
			"level": AccessLevel.USER,
			"dashboard_ids": [str(content_dashboard.id)],
		},
	)
	assert res.status_code == 302
	admin_ap.refresh_from_db()
	assert admin_ap.level == AccessLevel.ADMIN


@pytest.mark.django_db
def test_guard_prevents_revoking_last_active_admin():
	operator_user = User.objects.create_user(
		phone="0500000217",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard, _ = Dashboard.objects.get_or_create(code="admin_control", defaults={"name_ar": "صلاحيات التشغيل", "sort_order": 10})
	operator_ap = UserAccessProfile.objects.create(user=operator_user, level=AccessLevel.USER)
	operator_ap.allowed_dashboards.set([access_dashboard])

	sole_admin_user = User.objects.create_user(phone="0500000218", password="Pass12345!", is_staff=True)
	sole_admin_ap = UserAccessProfile.objects.create(
		user=sole_admin_user,
		level=AccessLevel.ADMIN,
	)

	c = Client()
	assert c.login(phone="0500000217", password="Pass12345!")
	s = c.session
	s[SESSION_OTP_VERIFIED_KEY] = True
	s.save()
	url = reverse("dashboard:access_profile_toggle_revoke_action", args=[sole_admin_ap.id])
	res = c.post(url, data={})
	assert res.status_code == 302
	sole_admin_ap.refresh_from_db()
	assert sole_admin_ap.revoked_at is None

	# With another active admin present, revoke should be allowed.
	second_admin_user = User.objects.create_user(phone="0500000219", password="Pass12345!", is_staff=True)
	UserAccessProfile.objects.create(user=second_admin_user, level=AccessLevel.ADMIN)
	res2 = c.post(url, data={})
	assert res2.status_code == 302
	sole_admin_ap.refresh_from_db()
	assert sole_admin_ap.revoked_at is not None


@pytest.mark.django_db
def test_qa_readonly_cannot_execute_content_post_action():
    qa_user = User.objects.create_user(phone="0500000220", password="Pass12345!", is_staff=True)
    content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
    ap = UserAccessProfile.objects.create(user=qa_user, level=AccessLevel.QA)
    ap.allowed_dashboards.set([content_dashboard])

    c = Client()
    assert c.login(phone=qa_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    url = reverse("dashboard:content_links_update_action")
    res = c.post(url, data={"x_url": "https://example.com"})
    assert res.status_code in {302, 403}
    assert SiteLinks.objects.count() == 0


@pytest.mark.django_db
def test_power_user_has_global_write_access_and_can_post_content_links():
    power_user = User.objects.create_user(phone="0500000221", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=power_user, level=AccessLevel.POWER)

    assert _dashboard_allowed(power_user, "content", write=True) is True
    assert _dashboard_allowed(power_user, "support", write=True) is True
    assert _dashboard_allowed(power_user, "access", write=True) is True

    c = Client()
    assert c.login(phone=power_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    url = reverse("dashboard:content_links_update_action")
    res = c.post(url, data={"x_url": "https://example.com"})
    assert res.status_code == 302
    assert SiteLinks.objects.count() == 1
    assert SiteLinks.objects.first().x_url == "https://example.com"


@pytest.mark.django_db
def test_subscription_request_status_rejects_invalid_transition_new_to_completed():
    admin_user = User.objects.create_user(phone="0500000971", password="Pass12345!", is_staff=True)
    subs_dashboard, _ = Dashboard.objects.get_or_create(code="subs", defaults={"name_ar": "الاشتراكات", "sort_order": 31})
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([subs_dashboard])

    requester = User.objects.create_user(phone="0500000972", password="Pass12345!")
    plan = SubscriptionPlan.objects.create(code="SD_GUARD", title="خطة", period="year", price="99.00", is_active=True)
    sub = Subscription.objects.create(user=requester, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT)
    ur = UnifiedRequest.objects.create(
        request_type="subscription",
        requester=requester,
        status=UnifiedRequestStatus.NEW,
        priority="normal",
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
        summary="طلب اشتراك",
    )

    c = Client()
    assert c.login(phone=admin_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    res = c.post(
        reverse("dashboard:subscription_request_set_status_action", args=[sub.id]),
        data={"status": UnifiedRequestStatus.COMPLETED, "note": "قفزة غير مسموحة"},
    )
    assert res.status_code == 302
    ur.refresh_from_db()
    assert ur.status == UnifiedRequestStatus.NEW


@pytest.mark.django_db
def test_extras_request_status_allows_only_three_stage_and_guarded_transitions():
    admin_user = User.objects.create_user(phone="0500000973", password="Pass12345!", is_staff=True)
    extras_dashboard, _ = Dashboard.objects.get_or_create(code="extras", defaults={"name_ar": "الخدمات الإضافية", "sort_order": 32})
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([extras_dashboard])

    requester = User.objects.create_user(phone="0500000974", password="Pass12345!")
    purchase = ExtraPurchase.objects.create(
        user=requester,
        sku="uploads_10gb_month",
        title="Upload Boost",
        extra_type="time_based",
        subtotal="50.00",
        status=ExtraPurchaseStatus.PENDING_PAYMENT,
    )
    ur = UnifiedRequest.objects.create(
        request_type="extras",
        requester=requester,
        status=UnifiedRequestStatus.NEW,
        priority="normal",
        source_app="extras",
        source_model="ExtraPurchase",
        source_object_id=str(purchase.id),
        summary="طلب خدمة إضافية",
    )

    c = Client()
    assert c.login(phone=admin_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    invalid_status_res = c.post(
        reverse("dashboard:extras_request_status_action", args=[ur.id]),
        data={"status": UnifiedRequestStatus.CLOSED},
    )
    assert invalid_status_res.status_code == 302
    ur.refresh_from_db()
    assert ur.status == UnifiedRequestStatus.NEW

    invalid_transition_res = c.post(
        reverse("dashboard:extras_request_status_action", args=[ur.id]),
        data={"status": UnifiedRequestStatus.COMPLETED},
    )
    assert invalid_transition_res.status_code == 302
    ur.refresh_from_db()
    assert ur.status == UnifiedRequestStatus.NEW

    valid_transition_res = c.post(
        reverse("dashboard:extras_request_status_action", args=[ur.id]),
        data={"status": UnifiedRequestStatus.IN_PROGRESS},
    )
    assert valid_transition_res.status_code == 302
    ur.refresh_from_db()
    assert ur.status == UnifiedRequestStatus.IN_PROGRESS


@pytest.mark.django_db
def test_requests_list_export_csv_sanitizes_csv_injection_cells():
    content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
    staff_user = User.objects.create_user(phone="0500000222", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN)
    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="هوية", is_active=True)
    client_user = User.objects.create_user(phone="0500000223")

    ServiceRequest.objects.create(
        client=client_user,
        subcategory=sub,
        title="=HYPERLINK(\"http://evil\")",
        description="+cmd",
        request_type="competitive",
        status=RequestStatus.NEW,
        city="@riyadh",
    )

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    res = c.get(reverse("dashboard:requests_list"), {"export": "csv"})
    assert res.status_code == 200
    assert "text/csv" in (res["Content-Type"] or "")
    body = res.content.decode("utf-8")
    assert "'=HYPERLINK" in body
    assert "'@riyadh" in body


@pytest.mark.django_db
def test_dashboard_home_date_range_filters_request_kpis():
    analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "الرئيسية", "sort_order": 1})
    admin_user = User.objects.create_user(phone="0500000224", password="Pass12345!", is_staff=True)
    ap = UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)
    ap.allowed_dashboards.set([analytics_dashboard])

    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)
    client_user = User.objects.create_user(phone="0500000225")
    old_req = ServiceRequest.objects.create(
        client=client_user,
        subcategory=sub,
        title="قديم",
        description="قديم",
        request_type="competitive",
        status=RequestStatus.NEW,
        city="الرياض",
    )
    new_req = ServiceRequest.objects.create(
        client=client_user,
        subcategory=sub,
        title="جديد",
        description="جديد",
        request_type="competitive",
        status=RequestStatus.NEW,
        city="الرياض",
    )
    ServiceRequest.objects.filter(id=old_req.id).update(created_at=timezone.now() - timedelta(days=90))
    ServiceRequest.objects.filter(id=new_req.id).update(created_at=timezone.now())

    c = Client()
    assert c.login(phone=admin_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    res = c.get(
        reverse("dashboard:home"),
        {
            "date_from": (timezone.localdate() - timedelta(days=7)).isoformat(),
            "date_to": timezone.localdate().isoformat(),
        },
    )
    assert res.status_code == 200
    assert res.context["total_requests"] == 1
    assert res.context["date_from_val"]
    assert res.context["date_to_val"]


@pytest.mark.django_db
def test_dashboard_home_requires_otp_verified_session_for_authenticated_staff():
    analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "الرئيسية", "sort_order": 1})
    staff_user = User.objects.create_user(phone="0500000226", password="Pass12345!", is_staff=True)
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([analytics_dashboard])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    res = c.get(reverse("dashboard:home"))
    assert res.status_code == 302
    assert reverse("dashboard:otp") in res.url


@pytest.mark.django_db
@override_settings(DEBUG=True, OTP_DEV_BYPASS_ENABLED=True, OTP_DEV_ACCEPT_ANY_4_DIGITS=True)
def test_dashboard_otp_dev_accepts_any_4_digits_and_sets_session_flag():
    analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "الرئيسية", "sort_order": 1})
    staff_user = User.objects.create_user(phone="0500000227", password="Pass12345!")
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([analytics_dashboard])

    c = Client()
    login_res = c.post(reverse("dashboard:login"), data={"phone": staff_user.phone})
    assert login_res.status_code == 302
    assert reverse("dashboard:otp") in login_res.url

    otp_res = c.post(reverse("dashboard:otp"), data={"code": "1234"})
    assert otp_res.status_code == 302
    assert otp_res.url == reverse("dashboard:home")

    s = c.session
    assert s.get(SESSION_OTP_VERIFIED_KEY) is True
    staff_user.refresh_from_db()
    assert staff_user.is_staff is True


@pytest.mark.django_db
@override_settings(DEBUG=True, OTP_DEV_BYPASS_ENABLED=True, OTP_DEV_ACCEPT_ANY_4_DIGITS=True)
def test_dashboard_otp_redirects_to_first_allowed_dashboard_for_limited_user():
    support_dashboard, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 1})
    staff_user = User.objects.create_user(
        phone="0500000228",
        password="Pass12345!",
    )
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([support_dashboard])

    c = Client()
    login_res = c.post(reverse("dashboard:login"), data={"phone": staff_user.phone})
    assert login_res.status_code == 302
    assert reverse("dashboard:otp") in login_res.url

    otp_res = c.post(reverse("dashboard:otp"), data={"code": "1234"})
    assert otp_res.status_code == 302
    assert otp_res.url == reverse("dashboard:support_tickets_list")


@pytest.mark.django_db
@override_settings(DEBUG=False, OTP_DEV_BYPASS_ENABLED=False, OTP_DEV_ACCEPT_ANY_4_DIGITS=False)
def test_dashboard_otp_requires_real_code_when_dev_bypass_disabled():
    analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "الرئيسية", "sort_order": 1})
    staff_user = User.objects.create_user(phone="0500000231", password="Pass12345!")
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([analytics_dashboard])

    c = Client()
    login_res = c.post(reverse("dashboard:login"), data={"phone": staff_user.phone})
    assert login_res.status_code == 302
    assert reverse("dashboard:otp") in login_res.url

    otp_res = c.post(reverse("dashboard:otp"), data={"code": "1234"})
    assert otp_res.status_code == 200
    assert SESSION_OTP_VERIFIED_KEY not in c.session


@pytest.mark.django_db
def test_requests_list_export_uses_platform_config_limits(mocker):
    content_dashboard, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "إدارة المحتوى", "sort_order": 20})
    staff_user = User.objects.create_user(phone="0500000232", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN).allowed_dashboards.set([content_dashboard])

    config = PlatformConfig.load()
    config.export_xlsx_max_rows = 1
    config.export_pdf_max_rows = 1
    config.save()

    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)
    client_user = User.objects.create_user(phone="0500000233")
    for idx in range(3):
        ServiceRequest.objects.create(
            client=client_user,
            subcategory=sub,
            title=f"طلب {idx}",
            description="وصف",
            request_type="competitive",
            status=RequestStatus.NEW,
            city="الرياض",
        )

    captured: dict[str, list] = {}

    def _fake_xlsx_response(filename, sheet_name, headers, rows):
        captured["xlsx"] = rows
        return HttpResponse(b"PK", content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    def _fake_pdf_response(filename, title, headers, rows, landscape=False):
        captured["pdf"] = rows
        return HttpResponse(b"%PDF", content_type="application/pdf")

    mocker.patch("apps.dashboard.exports.xlsx_response", side_effect=_fake_xlsx_response)
    mocker.patch("apps.dashboard.exports.pdf_response", side_effect=_fake_pdf_response)

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    xlsx_res = c.get(reverse("dashboard:requests_list"), {"export": "xlsx"})
    pdf_res = c.get(reverse("dashboard:requests_list"), {"export": "pdf"})

    assert xlsx_res.status_code == 200
    assert pdf_res.status_code == 200
    assert len(captured["xlsx"]) == 1
    assert len(captured["pdf"]) == 1


@pytest.mark.django_db
def test_user_update_role_demotes_operational_access_and_revokes_profile():
    access_dashboard, _ = Dashboard.objects.get_or_create(code="admin_control", defaults={"name_ar": "صلاحيات التشغيل", "sort_order": 1})
    support_dashboard, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 2})

    admin_user = User.objects.create_user(
        phone="0500000229",
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    admin_ap = UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)
    admin_ap.allowed_dashboards.set([access_dashboard])

    target_user = User.objects.create_user(
        phone="0500000230",
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    target_ap = UserAccessProfile.objects.create(user=target_user, level=AccessLevel.USER)
    target_ap.allowed_dashboards.set([support_dashboard])

    c = Client()
    assert c.login(phone=admin_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    res = c.post(
        reverse("dashboard:user_update_role", args=[target_user.id]),
        data={"role_state": UserRole.CLIENT},
    )
    assert res.status_code == 302

    target_user.refresh_from_db()
    target_ap.refresh_from_db()
    assert target_user.role_state == UserRole.CLIENT
    assert target_user.is_staff is False
    assert target_ap.revoked_at is not None


@pytest.mark.django_db
def test_promo_campaign_create_dashboard_creates_bundle_request_with_valid_items():
    staff_user = User.objects.create_user(
        phone="0500000811",
        password="Pass12345!",
        is_staff=True,
    )
    promo_dashboard, _ = Dashboard.objects.get_or_create(code="promo", defaults={"name_ar": "الترويج", "sort_order": 10})
    UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN).allowed_dashboards.set([promo_dashboard])

    target_user = User.objects.create_user(
        phone="0500000812",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    target_provider = ProviderProfile.objects.create(
        user=target_user,
        provider_type="individual",
        display_name="مزود مستهدف",
        bio="bio",
        city="الرياض",
        years_experience=3,
    )

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(days=2)
    send_at = start_at + timedelta(hours=6)
    upload = SimpleUploadedFile(
        "dashboard-promo.png",
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
        content_type="image/png",
    )

    response = c.post(
        reverse("dashboard:promo_campaign_create"),
        data={
            "title": "حملة تشغيلية متكاملة",
            "ad_type": PromoAdType.BANNER_HOME,
            "status": PromoRequestStatus.ACTIVE,
            "start_at": start_at.strftime("%Y-%m-%dT%H:%M"),
            "end_at": end_at.strftime("%Y-%m-%dT%H:%M"),
            "send_at": send_at.strftime("%Y-%m-%dT%H:%M"),
            "search_scope": "main_results",
            "search_position": "top5",
            "target_category": "تصميم داخلي",
            "target_city": "الرياض",
            "provider": str(target_provider.id),
            "redirect_url": "https://example.com/promo",
            "promo_message_title": "عرض خاص",
            "promo_message_body": "تفاصيل العرض التشغيلي",
            "promo_attachment_specs": "صورة مربعة",
            "use_notification_channel": "on",
            "home_banner_mobile_scale": "92",
            "home_banner_tablet_scale": "104",
            "home_banner_desktop_scale": "118",
            "service_types": [
                PromoServiceType.HOME_BANNER,
                PromoServiceType.SEARCH_RESULTS,
                PromoServiceType.PROMO_MESSAGES,
            ],
            "assets": upload,
        },
    )

    assert response.status_code == 302
    pr = PromoRequest.objects.get()
    assert pr.ad_type == PromoAdType.BUNDLE
    assert pr.status == PromoRequestStatus.ACTIVE
    assert pr.assigned_to_id == staff_user.id
    assert pr.assets.count() == 1
    assert pr.items.count() == 3
    assert pr.mobile_scale == 92
    assert pr.tablet_scale == 104
    assert pr.desktop_scale == 118

    search_item = pr.items.get(service_type=PromoServiceType.SEARCH_RESULTS)
    assert search_item.search_scope == "main_results"
    assert search_item.search_position == "top5"
    assert search_item.target_provider_id == target_provider.id

    message_item = pr.items.get(service_type=PromoServiceType.PROMO_MESSAGES)
    assert message_item.send_at is not None
    assert message_item.use_notification_channel is True
    assert message_item.use_chat_channel is False
    assert message_item.message_body == "تفاصيل العرض التشغيلي"


@pytest.mark.django_db
def test_promo_home_banner_create_dashboard_rejects_media_type_mismatch():
    staff_user = User.objects.create_user(
        phone="0500000810",
        password="Pass12345!",
        is_staff=True,
    )
    promo_dashboard, _ = Dashboard.objects.get_or_create(code="promo", defaults={"name_ar": "الترويج", "sort_order": 10})
    UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN).allowed_dashboards.set([promo_dashboard])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    response = c.post(
        reverse("dashboard:promo_home_banner_create"),
        data={
            "title": "بانر غير متوافق",
            "media_type": "video",
            "display_order": "1",
            "media_file": SimpleUploadedFile(
                "banner.png",
                b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
                content_type="image/png",
            ),
        },
    )

    assert response.status_code == 302
    assert HomeBanner.objects.count() == 0


@pytest.mark.django_db
def test_promo_campaign_create_dashboard_rejects_unsupported_direct_ad_type():
    staff_user = User.objects.create_user(
        phone="0500000813",
        password="Pass12345!",
        is_staff=True,
    )
    promo_dashboard, _ = Dashboard.objects.get_or_create(code="promo", defaults={"name_ar": "الترويج", "sort_order": 10})
    UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN).allowed_dashboards.set([promo_dashboard])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(days=1)
    response = c.post(
        reverse("dashboard:promo_campaign_create"),
        data={
            "title": "نوع غير مدعوم",
            "ad_type": PromoAdType.BANNER_CATEGORY,
            "status": PromoRequestStatus.NEW,
            "start_at": start_at.strftime("%Y-%m-%dT%H:%M"),
            "end_at": end_at.strftime("%Y-%m-%dT%H:%M"),
        },
    )

    assert response.status_code == 302
    assert PromoRequest.objects.count() == 0


# ──────── Phase 2 RBAC Enforcement Tests ────────


@pytest.mark.django_db
def test_rbac_admin_auto_allowed_all_backoffice_dashboards():
    """Admin level gets auto-access to all dashboards except client_extras."""
    admin_user = User.objects.create_user(phone="0500009001", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)

    for code in ("admin_control", "support", "content", "promo", "verify", "subs", "extras", "analytics", "billing"):
        assert _dashboard_allowed(admin_user, code, write=False) is True
        assert _dashboard_allowed(admin_user, code, write=True) is True

    # client_extras is blocked
    assert _dashboard_allowed(admin_user, "client_extras", write=False) is False


@pytest.mark.django_db
def test_rbac_power_user_auto_allowed_except_client_extras():
    """Power user mirrors admin access except client_extras."""
    power_user = User.objects.create_user(phone="0500009002", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=power_user, level=AccessLevel.POWER)

    assert _dashboard_allowed(power_user, "support", write=True) is True
    assert _dashboard_allowed(power_user, "admin_control", write=True) is True
    assert _dashboard_allowed(power_user, "client_extras", write=False) is False


@pytest.mark.django_db
def test_rbac_alias_access_resolves_to_admin_control():
    """Backward-compatible alias: 'access' resolves to 'admin_control'."""
    admin_user = User.objects.create_user(phone="0500009003", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)

    # Using old code "access" still works
    assert _dashboard_allowed(admin_user, "access", write=True) is True
    assert _dashboard_allowed(admin_user, "access", write=False) is True


@pytest.mark.django_db
def test_rbac_qa_read_only_all_dashboards():
    """QA level can read allowed dashboards but never write."""
    qa_user = User.objects.create_user(phone="0500009004", password="Pass12345!", is_staff=True)
    support_db, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 10})
    promo_db, _ = Dashboard.objects.get_or_create(code="promo", defaults={"name_ar": "الترويج", "sort_order": 30})
    ap = UserAccessProfile.objects.create(user=qa_user, level=AccessLevel.QA)
    ap.allowed_dashboards.set([support_db, promo_db])

    assert _dashboard_allowed(qa_user, "support", write=False) is True
    assert _dashboard_allowed(qa_user, "support", write=True) is False
    assert _dashboard_allowed(qa_user, "promo", write=False) is True
    assert _dashboard_allowed(qa_user, "promo", write=True) is False
    # Not assigned to content
    assert _dashboard_allowed(qa_user, "content", write=False) is False


@pytest.mark.django_db
def test_rbac_user_level_restricted_to_assigned_dashboards():
    """User level only accesses dashboards explicitly in allowed_dashboards."""
    user = User.objects.create_user(phone="0500009005", password="Pass12345!", is_staff=True)
    support_db, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 10})
    ap = UserAccessProfile.objects.create(user=user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([support_db])

    assert _dashboard_allowed(user, "support", write=True) is True
    assert _dashboard_allowed(user, "support", write=False) is True
    assert _dashboard_allowed(user, "promo", write=False) is False
    assert _dashboard_allowed(user, "admin_control", write=False) is False


@pytest.mark.django_db
def test_rbac_client_only_accesses_client_extras():
    """Client level only accesses client_extras, nothing else."""
    from apps.dashboard.access import can_access_dashboard
    client_user = User.objects.create_user(phone="0500009006", password="Pass12345!")
    UserAccessProfile.objects.create(user=client_user, level=AccessLevel.CLIENT)

    assert can_access_dashboard(client_user, "client_extras", write=False) is True
    assert can_access_dashboard(client_user, "client_extras", write=True) is True
    assert can_access_dashboard(client_user, "support", write=False) is False
    assert can_access_dashboard(client_user, "extras", write=False) is False
    assert can_access_dashboard(client_user, "admin_control", write=False) is False


@pytest.mark.django_db
def test_rbac_has_action_permission_user_level():
    """User level needs explicit granted_permissions for action permissions."""
    from apps.dashboard.access import has_action_permission
    from apps.backoffice.models import AccessPermission

    user = User.objects.create_user(phone="0500009007", password="Pass12345!", is_staff=True)
    perm, _ = AccessPermission.objects.get_or_create(
        code="admin_control.manage_access",
        defaults={"name_ar": "إدارة صلاحيات", "dashboard_code": "admin_control", "sort_order": 1},
    )
    ap = UserAccessProfile.objects.create(user=user, level=AccessLevel.USER)

    # Without permission
    assert has_action_permission(user, "admin_control.manage_access") is False

    # Grant the permission
    ap.granted_permissions.add(perm)
    assert has_action_permission(user, "admin_control.manage_access") is True


@pytest.mark.django_db
def test_rbac_has_action_permission_admin_auto():
    """Admin/Power get all action permissions automatically."""
    from apps.dashboard.access import has_action_permission

    admin_user = User.objects.create_user(phone="0500009008", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)

    assert has_action_permission(admin_user, "admin_control.manage_access") is True
    assert has_action_permission(admin_user, "promo.quote_activate") is True
    assert has_action_permission(admin_user, "support.assign") is True


@pytest.mark.django_db
def test_rbac_has_action_permission_qa_denied():
    """QA level has no action permissions (read-only)."""
    from apps.dashboard.access import has_action_permission

    qa_user = User.objects.create_user(phone="0500009009", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=qa_user, level=AccessLevel.QA)

    assert has_action_permission(qa_user, "admin_control.manage_access") is False
    assert has_action_permission(qa_user, "support.assign") is False


@pytest.mark.django_db
def test_rbac_has_action_permission_client_denied():
    """Client level has no action permissions."""
    from apps.dashboard.access import has_action_permission

    client_user = User.objects.create_user(phone="0500009010", password="Pass12345!")
    UserAccessProfile.objects.create(user=client_user, level=AccessLevel.CLIENT)

    assert has_action_permission(client_user, "admin_control.manage_access") is False


@pytest.mark.django_db
def test_rbac_admin_control_user_toggle_requires_permission():
    """user_toggle_active requires admin_control.manage_access permission."""
    from apps.backoffice.models import AccessPermission

    # Create a User-level staff with admin_control dashboard access but no manage_access permission
    staff_user = User.objects.create_user(phone="0500009011", password="Pass12345!", is_staff=True)
    admin_control_db, _ = Dashboard.objects.get_or_create(
        code="admin_control", defaults={"name_ar": "إدارة الصلاحيات", "sort_order": 1},
    )
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([admin_control_db])

    target_user = User.objects.create_user(phone="0500009012", password="Pass12345!", is_staff=True)

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Should be denied — no manage_access permission
    res = c.post(reverse("dashboard:user_toggle_active", args=[target_user.id]))
    assert res.status_code == 302
    target_user.refresh_from_db()
    assert target_user.is_active is True  # unchanged

    # Grant permission and retry
    perm, _ = AccessPermission.objects.get_or_create(
        code="admin_control.manage_access",
        defaults={"name_ar": "إدارة صلاحيات", "dashboard_code": "admin_control", "sort_order": 1},
    )
    ap.granted_permissions.add(perm)

    res2 = c.post(reverse("dashboard:user_toggle_active", args=[target_user.id]))
    assert res2.status_code == 302
    target_user.refresh_from_db()
    assert target_user.is_active is False  # now toggled


@pytest.mark.django_db
def test_rbac_audit_log_requires_view_audit_permission():
    """audit_log_list requires admin_control.view_audit permission."""
    from apps.backoffice.models import AccessPermission

    staff_user = User.objects.create_user(phone="0500009013", password="Pass12345!", is_staff=True)
    admin_control_db, _ = Dashboard.objects.get_or_create(
        code="admin_control", defaults={"name_ar": "إدارة الصلاحيات", "sort_order": 1},
    )
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([admin_control_db])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Without view_audit permission → redirect
    res = c.get(reverse("dashboard:audit_log_list"))
    assert res.status_code == 302

    # Grant permission
    perm, _ = AccessPermission.objects.get_or_create(
        code="admin_control.view_audit",
        defaults={"name_ar": "عرض سجل التدقيق", "dashboard_code": "admin_control", "sort_order": 2},
    )
    ap.granted_permissions.add(perm)
    res2 = c.get(reverse("dashboard:audit_log_list"))
    assert res2.status_code == 200


@pytest.mark.django_db
def test_rbac_promo_pricing_requires_quote_activate_permission():
    """promo_pricing_update_action requires promo.quote_activate permission."""
    from apps.backoffice.models import AccessPermission

    staff_user = User.objects.create_user(phone="0500009014", password="Pass12345!", is_staff=True)
    promo_db, _ = Dashboard.objects.get_or_create(code="promo", defaults={"name_ar": "الترويج", "sort_order": 30})
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([promo_db])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Without quote_activate → redirect
    res = c.post(reverse("dashboard:promo_pricing_update_action"), data={"code": "test", "amount": "100"})
    assert res.status_code == 302

    # Grant permission
    perm, _ = AccessPermission.objects.get_or_create(
        code="promo.quote_activate",
        defaults={"name_ar": "تسعير الترويج", "dashboard_code": "promo", "sort_order": 60},
    )
    ap.granted_permissions.add(perm)
    res2 = c.post(reverse("dashboard:promo_pricing_update_action"), data={"code": "nonexistent", "amount": "100"})
    # Now it should pass the permission check but fail on invalid rule code
    assert res2.status_code == 302


@pytest.mark.django_db
def test_rbac_expired_profile_denied():
    """Expired access profile blocks all access."""
    user = User.objects.create_user(phone="0500009015", password="Pass12345!", is_staff=True)
    support_db, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 10})
    ap = UserAccessProfile.objects.create(
        user=user,
        level=AccessLevel.USER,
        expires_at=timezone.now() - timedelta(hours=1),
    )
    ap.allowed_dashboards.set([support_db])

    assert _dashboard_allowed(user, "support", write=False) is False


@pytest.mark.django_db
def test_rbac_revoked_profile_denied():
    """Revoked access profile blocks all access."""
    user = User.objects.create_user(phone="0500009016", password="Pass12345!", is_staff=True)
    support_db, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 10})
    ap = UserAccessProfile.objects.create(
        user=user,
        level=AccessLevel.ADMIN,
        revoked_at=timezone.now(),
    )
    ap.allowed_dashboards.set([support_db])

    assert _dashboard_allowed(user, "support", write=False) is False
    assert _dashboard_allowed(user, "support", write=True) is False


@pytest.mark.django_db
def test_rbac_superuser_bypasses_all():
    """Superuser bypasses all RBAC checks."""
    su = User.objects.create_superuser(phone="0500009017", password="Pass12345!")

    assert _dashboard_allowed(su, "support", write=True) is True
    assert _dashboard_allowed(su, "admin_control", write=True) is True
    assert _dashboard_allowed(su, "client_extras", write=True) is True

    from apps.dashboard.access import has_action_permission
    assert has_action_permission(su, "admin_control.manage_access") is True


@pytest.mark.django_db
def test_rbac_dashboard_panel_required_decorator():
    """dashboard_panel_required decorator blocks unauthorized and passes authorized."""
    from apps.dashboard.access import dashboard_panel_required
    from django.test import RequestFactory

    factory = RequestFactory()

    # Create an admin user
    admin_user = User.objects.create_user(phone="0500009018", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)

    @dashboard_panel_required("support", write=True)
    def dummy_view(request):
        return HttpResponse("OK", status=200)

    # Admin should pass
    req = factory.get("/dummy/")
    req.user = admin_user
    # Mock _messages storage for the middleware
    from django.contrib.messages.storage.fallback import FallbackStorage
    setattr(req, 'session', {SESSION_OTP_VERIFIED_KEY: True})
    setattr(req, '_messages', FallbackStorage(req))
    resp = dummy_view(req)
    assert resp.status_code == 200

    # QA should be blocked (write=True)
    qa_user = User.objects.create_user(phone="0500009019", password="Pass12345!", is_staff=True)
    support_db, _ = Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 10})
    qa_ap = UserAccessProfile.objects.create(user=qa_user, level=AccessLevel.QA)
    qa_ap.allowed_dashboards.set([support_db])

    req2 = factory.get("/dummy/")
    req2.user = qa_user
    setattr(req2, 'session', {SESSION_OTP_VERIFIED_KEY: True})
    setattr(req2, '_messages', FallbackStorage(req2))
    resp2 = dummy_view(req2)
    assert resp2.status_code == 302  # Redirect on denied


# ── Phase 4B: Content Panel Policy Enforcement Tests ─────────────


@pytest.mark.django_db
@override_settings(FEATURE_RBAC_ENFORCE=True)
def test_content_block_update_requires_content_manage_policy():
    """content_block_update_action enforces ContentManagePolicy."""
    from apps.backoffice.models import AccessPermission

    staff_user = User.objects.create_user(phone="0500040001", password="Pass12345!", is_staff=True)
    content_db, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "المحتوى", "sort_order": 20})
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([content_db])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Without content.manage permission → redirect (policy denied)
    res = c.post(
        reverse("dashboard:content_block_update_action", args=["hero_section"]),
        data={"title_ar": "عنوان", "body_ar": "محتوى"},
    )
    assert res.status_code == 302

    # Grant permission
    perm, _ = AccessPermission.objects.get_or_create(
        code="content.manage",
        defaults={"name_ar": "إدارة محتوى المنصة", "dashboard_code": "content", "sort_order": 20},
    )
    ap.granted_permissions.add(perm)
    res2 = c.post(
        reverse("dashboard:content_block_update_action", args=["hero_section"]),
        data={"title_ar": "عنوان جديد", "body_ar": "محتوى جديد"},
    )
    # Passes policy, then redirects after save
    assert res2.status_code == 302


@pytest.mark.django_db
@override_settings(FEATURE_RBAC_ENFORCE=True)
def test_content_links_update_requires_content_manage_policy():
    """content_links_update_action enforces ContentManagePolicy."""
    from apps.backoffice.models import AccessPermission

    staff_user = User.objects.create_user(phone="0500040002", password="Pass12345!", is_staff=True)
    content_db, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "المحتوى", "sort_order": 20})
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([content_db])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Without permission → redirect
    res = c.post(reverse("dashboard:content_links_update_action"), data={"x_url": "https://x.com/test"})
    assert res.status_code == 302

    # Grant permission
    perm, _ = AccessPermission.objects.get_or_create(
        code="content.manage",
        defaults={"name_ar": "إدارة محتوى المنصة", "dashboard_code": "content", "sort_order": 20},
    )
    ap.granted_permissions.add(perm)
    res2 = c.post(reverse("dashboard:content_links_update_action"), data={"x_url": "https://x.com/test"})
    assert res2.status_code == 302  # Passes policy, saves & redirects


@pytest.mark.django_db
@override_settings(FEATURE_RBAC_ENFORCE=True)
def test_category_toggle_requires_content_hide_delete_policy():
    """category_toggle_active enforces ContentHideDeletePolicy."""
    from apps.backoffice.models import AccessPermission
    from apps.providers.models import Category

    staff_user = User.objects.create_user(phone="0500040003", password="Pass12345!", is_staff=True)
    content_db, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "المحتوى", "sort_order": 20})
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([content_db])

    cat = Category.objects.create(name="تصنيف اختبار", is_active=True)

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Without content.hide_delete → redirect
    res = c.post(reverse("dashboard:category_toggle_active", args=[cat.id]))
    assert res.status_code == 302
    cat.refresh_from_db()
    assert cat.is_active is True  # Not toggled

    # Grant permission
    perm, _ = AccessPermission.objects.get_or_create(
        code="content.hide_delete",
        defaults={"name_ar": "إخفاء وحذف المحتوى", "dashboard_code": "content", "sort_order": 10},
    )
    ap.granted_permissions.add(perm)
    res2 = c.post(reverse("dashboard:category_toggle_active", args=[cat.id]))
    assert res2.status_code == 302
    cat.refresh_from_db()
    assert cat.is_active is False  # Now toggled


@pytest.mark.django_db
@override_settings(FEATURE_RBAC_ENFORCE=True)
def test_review_respond_requires_reviews_moderate_policy():
    """reviews_dashboard_respond_action enforces ReviewModerationPolicy."""
    from apps.backoffice.models import AccessPermission
    from apps.providers.models import Category, ProviderProfile, SubCategory
    from apps.marketplace.models import ServiceRequest
    from apps.reviews.models import Review

    staff_user = User.objects.create_user(phone="0500040004", password="Pass12345!", is_staff=True)
    content_db, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "المحتوى", "sort_order": 20})
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    ap.allowed_dashboards.set([content_db])

    # Set up review dependencies
    client_user = User.objects.create_user(phone="0500040005", password="Pass12345!")
    provider_user = User.objects.create_user(phone="0500040007", password="Pass12345!")
    provider = ProviderProfile.objects.create(
        user=provider_user, provider_type="individual",
        display_name="مزود", bio="وصف",
    )
    cat = Category.objects.create(name="تصنيف")
    subcat = SubCategory.objects.create(category=cat, name="فرعي")
    sr = ServiceRequest.objects.create(
        client=client_user, provider=provider, subcategory=subcat,
        title="طلب", description="وصف", request_type="quote", city="الرياض",
    )
    review = Review.objects.create(
        request=sr, provider=provider, client=client_user,
        rating=5, comment="ممتاز",
    )

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Without reviews.moderate → redirect
    res = c.post(
        reverse("dashboard:reviews_dashboard_respond_action", args=[review.id]),
        data={"management_reply": "شكراً لتقييمك"},
    )
    assert res.status_code == 302
    review.refresh_from_db()
    assert not review.management_reply  # Not saved

    # Grant permission
    perm, _ = AccessPermission.objects.get_or_create(
        code="reviews.moderate",
        defaults={"name_ar": "إدارة المراجعات", "dashboard_code": "content", "sort_order": 15},
    )
    ap.granted_permissions.add(perm)
    res2 = c.post(
        reverse("dashboard:reviews_dashboard_respond_action", args=[review.id]),
        data={"management_reply": "شكراً لتقييمك"},
    )
    assert res2.status_code == 302
    review.refresh_from_db()
    assert review.management_reply == "شكراً لتقييمك"  # Now saved


@pytest.mark.django_db
@override_settings(FEATURE_RBAC_ENFORCE=True)
def test_admin_and_power_bypass_content_policy():
    """Admin/Power users bypass the Policy checks (superuser-like fallback)."""
    staff_user = User.objects.create_user(phone="0500040006", password="Pass12345!", is_staff=True)
    content_db, _ = Dashboard.objects.get_or_create(code="content", defaults={"name_ar": "المحتوى", "sort_order": 20})

    # Admin level — no explicit permission needed
    ap = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.ADMIN)
    ap.allowed_dashboards.set([content_db])

    c = Client()
    assert c.login(phone=staff_user.phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()

    # Admin should pass ContentManagePolicy without content.manage permission
    res = c.post(reverse("dashboard:content_links_update_action"), data={"x_url": ""})
    assert res.status_code == 302  # Passes policy
