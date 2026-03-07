from __future__ import annotations

from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.providers.models import ProviderProfile
from apps.verification.models import (
    VerifiedBadge,
    VerificationBadgeType,
    VerificationRequest,
    VerificationStatus,
)
from apps.verification.services import expire_verified_badges_and_sync, sync_provider_badges


pytestmark = pytest.mark.django_db


def _make_provider_user(phone: str) -> User:
    user = User.objects.create_user(phone=phone, password="Pass12345!")
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=f"provider-{phone[-4:]}",
        bio="bio",
    )
    return user


def _make_request(user: User, badge_type: str) -> VerificationRequest:
    return VerificationRequest.objects.create(requester=user, badge_type=badge_type)


def test_sync_provider_badges_reads_verified_badge_source_of_truth():
    user = _make_provider_user("0501000001")
    vr = _make_request(user, VerificationBadgeType.BLUE)

    VerifiedBadge.objects.create(
        user=user,
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق أساسي",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timedelta(days=30),
        is_active=True,
    )

    flags = sync_provider_badges(user)
    profile = user.provider_profile
    profile.refresh_from_db()

    assert flags["is_verified_blue"] is True
    assert flags["is_verified_green"] is False
    assert profile.is_verified_blue is True
    assert profile.is_verified_green is False


def test_verified_badge_signal_syncs_profile_flags_on_save_update():
    user = _make_provider_user("0501000002")
    vr = _make_request(user, VerificationBadgeType.BLUE)

    badge = VerifiedBadge.objects.create(
        user=user,
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق أساسي",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timedelta(days=30),
        is_active=True,
    )

    user.provider_profile.refresh_from_db()
    assert user.provider_profile.is_verified_blue is True

    badge.is_active = False
    badge.save(update_fields=["is_active"])

    user.provider_profile.refresh_from_db()
    assert user.provider_profile.is_verified_blue is False


def test_request_state_change_revokes_badges_when_request_is_rejected():
    user = _make_provider_user("0501000004")
    vr = VerificationRequest.objects.create(
        requester=user,
        badge_type=VerificationBadgeType.BLUE,
        status=VerificationStatus.ACTIVE,
        activated_at=timezone.now() - timedelta(days=1),
        expires_at=timezone.now() + timedelta(days=30),
    )

    VerifiedBadge.objects.create(
        user=user,
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق أساسي",
        activated_at=timezone.now() - timedelta(days=1),
        expires_at=timezone.now() + timedelta(days=30),
        is_active=True,
    )

    user.provider_profile.refresh_from_db()
    assert user.provider_profile.is_verified_blue is True

    vr.status = VerificationStatus.REJECTED
    vr.save(update_fields=["status", "updated_at"])

    user.provider_profile.refresh_from_db()
    assert VerifiedBadge.objects.filter(request=vr, is_active=True).count() == 0
    assert user.provider_profile.is_verified_blue is False


def test_expire_verified_badges_and_sync_disables_expired_badges_and_flags():
    user = _make_provider_user("0501000003")
    profile = user.provider_profile
    profile.is_verified_blue = True
    profile.save(update_fields=["is_verified_blue"])

    vr = VerificationRequest.objects.create(
        requester=user,
        badge_type=VerificationBadgeType.BLUE,
        status=VerificationStatus.ACTIVE,
        activated_at=timezone.now() - timedelta(days=10),
        expires_at=timezone.now() - timedelta(minutes=1),
    )
    badge = VerifiedBadge.objects.create(
        user=user,
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق أساسي",
        activated_at=timezone.now() - timedelta(days=10),
        expires_at=timezone.now() - timedelta(minutes=1),
        is_active=True,
    )

    changed = expire_verified_badges_and_sync()

    vr.refresh_from_db()
    badge.refresh_from_db()
    profile.refresh_from_db()
    assert changed >= 1
    assert vr.status == VerificationStatus.EXPIRED
    assert badge.is_active is False
    assert profile.is_verified_blue is False


def test_public_badges_endpoints_are_anonymous_and_backend_authored():
    client = APIClient()

    catalog = client.get("/api/public/badges/")
    assert catalog.status_code == 200
    assert catalog.data["count"] == 2
    assert {item["badge_type"] for item in catalog.data["items"]} == {"blue", "green"}

    blue = client.get("/api/public/badges/blue/")
    assert blue.status_code == 200
    assert blue.data["badge_type"] == "blue"
    assert any(req["code"] == "B1" for req in blue.data["requirements"])

    invalid = client.get("/api/public/badges/unknown/")
    assert invalid.status_code == 404
