import pytest
from django.test import override_settings

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.backoffice.policies import (
    ExtrasManagePolicy,
    ModerationAssignPolicy,
    PermissionCode,
    SubscriptionManagePolicy,
    VerificationFinalizePolicy,
)


pytestmark = pytest.mark.django_db


def _profile_with_dashboard(code: str):
    dashboard, _ = Dashboard.objects.get_or_create(code=code, defaults={"name_ar": code, "sort_order": 10})
    user = User.objects.create_user(phone=f"057{User.objects.count()+1:07d}", password="Pass12345!")
    profile = UserAccessProfile.objects.create(user=user, level=AccessLevel.USER)
    profile.allowed_dashboards.add(dashboard)
    return user, profile


@override_settings(FEATURE_RBAC_ENFORCE=False, RBAC_AUDIT_ONLY=True)
def test_policy_allows_dashboard_fallback_in_audit_only_mode():
    user, _profile = _profile_with_dashboard("moderation")
    result = ModerationAssignPolicy.evaluate(user)
    assert result.allowed is True
    assert result.audit_only is True


@override_settings(FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_policy_denies_without_explicit_permission_when_enforced():
    user, _profile = _profile_with_dashboard("moderation")
    result = ModerationAssignPolicy.evaluate(user)
    assert result.allowed is False
    assert result.reason == "permission_denied"


@override_settings(FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_policy_allows_when_permission_granted():
    user, profile = _profile_with_dashboard("verify")
    permission, _ = AccessPermission.objects.get_or_create(
        code=PermissionCode.VERIFICATION_FINALIZE,
        defaults={"name_ar": "اعتماد التوثيق", "dashboard_code": "verify", "sort_order": 70},
    )
    profile.granted_permissions.add(permission)

    result = VerificationFinalizePolicy.evaluate(user)
    assert result.allowed is True
    assert result.reason == "permission_granted"


def test_admin_level_has_all_permissions():
    user = User.objects.create_user(phone="0579999999", password="Pass12345!")
    UserAccessProfile.objects.create(user=user, level=AccessLevel.ADMIN)
    result = ModerationAssignPolicy.evaluate(user)
    assert result.allowed is True


@override_settings(FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_subscription_and_extras_policies_require_explicit_permissions():
    user, profile = _profile_with_dashboard("subs")
    extras_dashboard, _ = Dashboard.objects.get_or_create(code="extras", defaults={"name_ar": "extras", "sort_order": 11})
    profile.allowed_dashboards.add(extras_dashboard)

    assert SubscriptionManagePolicy.evaluate(user).allowed is False
    assert ExtrasManagePolicy.evaluate(user).allowed is False

    subs_permission, _ = AccessPermission.objects.get_or_create(
        code=PermissionCode.SUBSCRIPTIONS_MANAGE,
        defaults={"name_ar": "إدارة الاشتراكات", "dashboard_code": "subs", "sort_order": 81},
    )
    extras_permission, _ = AccessPermission.objects.get_or_create(
        code=PermissionCode.EXTRAS_MANAGE,
        defaults={"name_ar": "إدارة الإضافات", "dashboard_code": "extras", "sort_order": 82},
    )
    profile.granted_permissions.add(subs_permission, extras_permission)

    assert SubscriptionManagePolicy.evaluate(user).allowed is True
    assert ExtrasManagePolicy.evaluate(user).allowed is True
