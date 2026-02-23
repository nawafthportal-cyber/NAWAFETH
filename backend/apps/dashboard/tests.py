import pytest
from datetime import timedelta
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.audit.models import AuditAction, AuditLog
from apps.billing.models import Invoice
from apps.dashboard.views import _compute_actions, _dashboard_allowed
from apps.dashboard.templatetags.dashboard_access import can_access
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.marketplace.models import RequestStatus, ServiceRequest
from apps.providers.models import Category, ProviderProfile, SubCategory
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata


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
		status=RequestStatus.SENT,
		city="الرياض",
	)

	# 1 query only: ProviderProfile.exists() for the special-case accept.
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
		status=RequestStatus.SENT,
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
	content_dashboard = Dashboard.objects.create(
		code="content",
		name_ar="إدارة المحتوى",
		sort_order=20,
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
	content_dashboard = Dashboard.objects.create(
		code="content",
		name_ar="إدارة المحتوى",
		sort_order=20,
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
def test_access_profile_update_action_updates_level_dashboards_and_expiry():
	admin_user = User.objects.create_user(
		phone="0500000208",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard = Dashboard.objects.create(code="access", name_ar="صلاحيات التشغيل", sort_order=10)
	content_dashboard = Dashboard.objects.create(code="content", name_ar="إدارة المحتوى", sort_order=20)
	support_dashboard = Dashboard.objects.create(code="support", name_ar="الدعم", sort_order=30)
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
	access_dashboard = Dashboard.objects.create(code="access", name_ar="صلاحيات التشغيل", sort_order=10)
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
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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


@pytest.mark.django_db
def test_unified_request_detail_dashboard_page():
	admin_user = User.objects.create_user(
		phone="0500000995",
		password="Pass12345!",
		is_staff=True,
	)
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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
	analytics_dashboard = Dashboard.objects.create(code="analytics", name_ar="التحليلات", sort_order=10)
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
def test_access_profile_create_action_creates_profile_and_audit():
	admin_user = User.objects.create_user(
		phone="0500000212",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard = Dashboard.objects.create(code="access", name_ar="صلاحيات التشغيل", sort_order=10)
	content_dashboard = Dashboard.objects.create(code="content", name_ar="إدارة المحتوى", sort_order=20)
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([access_dashboard])

	target_user = User.objects.create_user(phone="0500000213", password="Pass12345!", is_staff=True)
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
	content_dashboard = Dashboard.objects.create(code="content", name_ar="إدارة المحتوى", sort_order=20)
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
		status=RequestStatus.SENT,
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
	staff_user = User.objects.create_user(phone="0500000993", password="Pass12345!", is_staff=True)
	content_dashboard = Dashboard.objects.create(code="content", name_ar="إدارة المحتوى", sort_order=20)
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
		status=RequestStatus.SENT,
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
	access_dashboard = Dashboard.objects.create(code="access", name_ar="صلاحيات التشغيل", sort_order=10)
	content_dashboard = Dashboard.objects.create(code="content", name_ar="إدارة المحتوى", sort_order=20)
	support_dashboard = Dashboard.objects.create(code="support", name_ar="الدعم", sort_order=30)
	UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([access_dashboard])

	target_user = User.objects.create_user(phone="0500000215", password="Pass12345!", is_staff=True)
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

	log = AuditLog.objects.filter(
		action=AuditAction.ACCESS_PROFILE_UPDATED,
		reference_type="backoffice.user_access_profile",
		reference_id=str(target_ap.id),
	).first()
	assert log is not None
	assert log.actor_id == admin_user.id
	assert log.extra.get("created") is False


@pytest.mark.django_db
def test_guard_prevents_demoting_last_active_admin():
	admin_user = User.objects.create_user(
		phone="0500000216",
		password="Pass12345!",
		is_staff=True,
	)
	access_dashboard = Dashboard.objects.create(code="access", name_ar="صلاحيات التشغيل", sort_order=10)
	content_dashboard = Dashboard.objects.create(code="content", name_ar="إدارة المحتوى", sort_order=20)
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
	access_dashboard = Dashboard.objects.create(code="access", name_ar="صلاحيات التشغيل", sort_order=10)
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
