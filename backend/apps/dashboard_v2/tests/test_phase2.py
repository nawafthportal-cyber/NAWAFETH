from __future__ import annotations

import pytest
from django.test import Client, override_settings
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.content.models import ContentBlockKey, SiteContentBlock
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.moderation.models import ModerationCase


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
def test_phase2_content_and_excellence_routes_access():
    content_dashboard = _dashboard("content", "المحتوى")
    excellence_dashboard = _dashboard("excellence", "التميز")

    user = User.objects.create_user(phone="0500200001", password="Pass12345!", is_staff=True)
    _access_profile(user, level=AccessLevel.USER, dashboards=[content_dashboard, excellence_dashboard])

    client = Client()
    _login_dashboard_v2(client, user=user)

    assert client.get(reverse("dashboard_v2:content_home")).status_code == 200
    assert client.get(reverse("dashboard_v2:excellence_home")).status_code == 200


@pytest.mark.django_db
@override_settings(FEATURE_RBAC_ENFORCE=True)
def test_phase2_content_write_requires_manage_permission():
    content_dashboard = _dashboard("content", "المحتوى")
    qa_user = User.objects.create_user(phone="0500200002", password="Pass12345!", is_staff=True)
    _access_profile(qa_user, level=AccessLevel.QA, dashboards=[content_dashboard])
    target_key = ContentBlockKey.HOME_HERO_TITLE
    block, _ = SiteContentBlock.objects.get_or_create(
        key=target_key,
        defaults={"title_ar": "initial-title", "body_ar": "initial-body", "is_active": True},
    )
    original_title = block.title_ar

    # QA is read-only and must not write content blocks.
    qa_client = Client()
    _login_dashboard_v2(qa_client, user=qa_user)
    response = qa_client.post(
        reverse("dashboard_v2:content_block_update_action", args=[target_key]),
        data={"title_ar": "qa-denied-title", "body_ar": "qa-denied-body", "is_active": "1"},
    )
    assert response.status_code == 302
    block.refresh_from_db()
    assert block.title_ar == original_title

    user = User.objects.create_user(phone="0500200007", password="Pass12345!", is_staff=True)
    profile = _access_profile(user, level=AccessLevel.USER, dashboards=[content_dashboard])
    permission, _ = AccessPermission.objects.get_or_create(
        code="content.manage",
        defaults={
            "name_ar": "إدارة محتوى المنصة",
            "dashboard_code": "content",
            "sort_order": 20,
            "is_active": True,
        },
    )
    profile.granted_permissions.add(permission)

    client = Client()
    _login_dashboard_v2(client, user=user)
    response2 = client.post(
        reverse("dashboard_v2:content_block_update_action", args=[target_key]),
        data={"title_ar": "عنوان", "body_ar": "وصف", "is_active": "1"},
    )
    assert response2.status_code == 302
    block.refresh_from_db()
    assert block.title_ar == "عنوان"


@pytest.mark.django_db
@override_settings(FEATURE_MODERATION_CENTER=True)
def test_phase2_moderation_detail_enforces_object_access():
    moderation_dashboard = _dashboard("moderation", "الإشراف")

    reviewer = User.objects.create_user(phone="0500200003", password="Pass12345!", is_staff=True)
    assignee = User.objects.create_user(phone="0500200004", password="Pass12345!", is_staff=True)
    reporter = User.objects.create_user(phone="0500200005", password="Pass12345!")
    _access_profile(reviewer, level=AccessLevel.USER, dashboards=[moderation_dashboard])
    _access_profile(assignee, level=AccessLevel.USER, dashboards=[moderation_dashboard])

    case = ModerationCase.objects.create(
        reporter=reporter,
        reason="بلاغ اختبار",
        summary="case-private",
        assigned_to=assignee,
    )

    client = Client()
    _login_dashboard_v2(client, user=reviewer)

    # list is accessible, but foreign assigned case detail must be blocked.
    assert client.get(reverse("dashboard_v2:moderation_list")).status_code == 200
    assert client.get(reverse("dashboard_v2:moderation_detail", args=[case.id])).status_code == 403


@pytest.mark.django_db
def test_phase2_reviews_rendering_is_read_only_without_permission():
    reviews_dashboard = _dashboard("reviews", "المراجعات")

    user = User.objects.create_user(phone="0500200006", password="Pass12345!", is_staff=True)
    _access_profile(user, level=AccessLevel.USER, dashboards=[reviews_dashboard])

    client = Client()
    _login_dashboard_v2(client, user=user)

    response = client.get(reverse("dashboard_v2:reviews_list"))
    assert response.status_code == 200
    html = response.content.decode("utf-8")
    assert "Read Only" in html
