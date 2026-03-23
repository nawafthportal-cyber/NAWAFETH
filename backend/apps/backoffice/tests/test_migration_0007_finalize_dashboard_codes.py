from __future__ import annotations

import importlib

import pytest

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile


class _MigrationAppsProxy:
    def get_model(self, app_label: str, model_name: str):
        if app_label != "backoffice":
            raise LookupError(f"Unexpected app label: {app_label}")
        mapping = {
            "Dashboard": Dashboard,
            "UserAccessProfile": UserAccessProfile,
        }
        return mapping[model_name]


@pytest.mark.django_db
def test_migration_0007_finalize_dashboard_codes_is_safe_and_idempotent():
    legacy_access, _ = Dashboard.objects.update_or_create(
        code="access",
        defaults={"name_ar": "صلاحيات", "sort_order": 1, "is_active": True},
    )
    legacy_admin, _ = Dashboard.objects.update_or_create(
        code="admin",
        defaults={"name_ar": "إدارة", "sort_order": 2, "is_active": True},
    )
    support_dashboard, _ = Dashboard.objects.update_or_create(
        code="support",
        defaults={"name_ar": "الدعم", "sort_order": 10, "is_active": True},
    )

    staff_user = User.objects.create_user(phone="0500092001", password="Pass12345!", is_staff=True)
    profile = UserAccessProfile.objects.create(user=staff_user, level=AccessLevel.USER)
    profile.allowed_dashboards.set([legacy_access, legacy_admin, support_dashboard])

    extra_user = User.objects.create_user(phone="0500092002", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=extra_user, level=AccessLevel.QA)

    legacy_permission = AccessPermission.objects.create(
        code="legacy.access.audit",
        name_ar="صلاحية قديمة",
        dashboard_code="access",
        is_active=True,
    )
    profile.granted_permissions.add(legacy_permission)

    migration_module = importlib.import_module("apps.backoffice.migrations.0007_finalize_dashboard_codes")
    apps_proxy = _MigrationAppsProxy()

    migration_module.forward(apps_proxy, schema_editor=None)
    migration_module.forward(apps_proxy, schema_editor=None)

    profile.refresh_from_db()
    allowed_codes = list(profile.allowed_dashboards.order_by("code").values_list("code", flat=True))
    allowed_codes_set = set(allowed_codes)

    assert "admin_control" in allowed_codes_set
    assert "support" in allowed_codes_set
    assert "access" not in allowed_codes_set
    assert "admin" not in allowed_codes_set
    assert allowed_codes.count("admin_control") == 1

    assert Dashboard.objects.filter(code="access").exists() is False
    assert Dashboard.objects.filter(code="admin").exists() is False

    for expected_code in {
        "support",
        "content",
        "moderation",
        "reviews",
        "promo",
        "verify",
        "subs",
        "extras",
        "analytics",
        "admin_control",
        "client_extras",
    }:
        assert Dashboard.objects.filter(code=expected_code, is_active=True).exists()

    # Sanity: accounts and granted permissions remain intact.
    assert User.objects.filter(id=staff_user.id).exists()
    assert User.objects.filter(id=extra_user.id).exists()
    assert profile.granted_permissions.filter(id=legacy_permission.id).exists()
