from __future__ import annotations

from dataclasses import dataclass

from django.contrib.auth.models import AnonymousUser

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.core.feature_flags import rbac_audit_only_enabled, rbac_enforce_enabled
from apps.dashboard.access import active_access_profile_for_user, dashboard_allowed


class PermissionCode:
    MODERATION_ASSIGN = "moderation.assign"
    MODERATION_RESOLVE = "moderation.resolve"
    REVIEWS_MODERATE = "reviews.moderate"
    CONTENT_HIDE_DELETE = "content.hide_delete"
    SUPPORT_ASSIGN = "support.assign"
    SUPPORT_RESOLVE = "support.resolve"
    PROMO_QUOTE_ACTIVATE = "promo.quote_activate"
    VERIFICATION_FINALIZE = "verification.finalize"
    SUBSCRIPTIONS_MANAGE = "subscriptions.manage"
    EXTRAS_MANAGE = "extras.manage"
    ANALYTICS_EXPORT = "analytics.export"


@dataclass(frozen=True)
class PolicyResult:
    allowed: bool
    reason: str = ""
    audit_only: bool = False


class BaseActionPolicy:
    dashboard_code: str = ""
    permission_code: str = ""
    write: bool = True

    @classmethod
    def evaluate(cls, user) -> PolicyResult:
        user = user or AnonymousUser()
        if not getattr(user, "is_authenticated", False):
            return PolicyResult(False, "auth_required")
        if getattr(user, "is_superuser", False):
            return PolicyResult(True, "superuser")

        access_profile = active_access_profile_for_user(user)
        if not access_profile:
            return PolicyResult(False, "access_profile_required")
        if cls.write and access_profile.is_readonly():
            return PolicyResult(False, "readonly_profile")

        fallback_allowed = True
        if cls.dashboard_code:
            fallback_allowed = dashboard_allowed(user, cls.dashboard_code, write=cls.write)

        if not rbac_enforce_enabled():
            if fallback_allowed:
                return PolicyResult(True, "dashboard_fallback", audit_only=rbac_audit_only_enabled())
            return PolicyResult(False, "dashboard_access_required", audit_only=rbac_audit_only_enabled())

        if access_profile.has_permission_code(cls.permission_code):
            return PolicyResult(True, "permission_granted")
        return PolicyResult(False, "permission_denied")

    @classmethod
    def allows(cls, user) -> bool:
        return cls.evaluate(user).allowed

    @classmethod
    def log_result(
        cls,
        *,
        user,
        result: PolicyResult,
        request=None,
        reference_type: str = "",
        reference_id: str = "",
        extra: dict | None = None,
    ) -> None:
        action = AuditAction.RBAC_POLICY_ALLOWED
        if result.audit_only:
            action = AuditAction.RBAC_POLICY_AUDIT_ONLY
        elif not result.allowed:
            action = AuditAction.RBAC_POLICY_DENIED
        log_action(
            actor=user,
            action=action,
            reference_type=reference_type or cls.dashboard_code or "rbac.policy",
            reference_id=reference_id or "",
            request=request,
            extra={
                "policy": cls.__name__,
                "dashboard_code": cls.dashboard_code,
                "permission_code": cls.permission_code,
                "allowed": bool(result.allowed),
                "audit_only": bool(result.audit_only),
                "reason": result.reason,
                **(extra or {}),
            },
        )

    @classmethod
    def evaluate_and_log(
        cls,
        user,
        *,
        request=None,
        reference_type: str = "",
        reference_id: str = "",
        extra: dict | None = None,
    ) -> PolicyResult:
        result = cls.evaluate(user)
        cls.log_result(
            user=user,
            result=result,
            request=request,
            reference_type=reference_type,
            reference_id=reference_id,
            extra=extra,
        )
        return result


class ModerationAssignPolicy(BaseActionPolicy):
    dashboard_code = "moderation"
    permission_code = PermissionCode.MODERATION_ASSIGN


class ModerationResolvePolicy(BaseActionPolicy):
    dashboard_code = "moderation"
    permission_code = PermissionCode.MODERATION_RESOLVE


class ReviewModerationPolicy(BaseActionPolicy):
    dashboard_code = "content"
    permission_code = PermissionCode.REVIEWS_MODERATE


class ContentHideDeletePolicy(BaseActionPolicy):
    dashboard_code = "content"
    permission_code = PermissionCode.CONTENT_HIDE_DELETE


class SupportAssignPolicy(BaseActionPolicy):
    dashboard_code = "support"
    permission_code = PermissionCode.SUPPORT_ASSIGN


class SupportResolvePolicy(BaseActionPolicy):
    dashboard_code = "support"
    permission_code = PermissionCode.SUPPORT_RESOLVE


class PromoQuoteActivatePolicy(BaseActionPolicy):
    dashboard_code = "promo"
    permission_code = PermissionCode.PROMO_QUOTE_ACTIVATE


class VerificationFinalizePolicy(BaseActionPolicy):
    dashboard_code = "verify"
    permission_code = PermissionCode.VERIFICATION_FINALIZE


class SubscriptionManagePolicy(BaseActionPolicy):
    dashboard_code = "subs"
    permission_code = PermissionCode.SUBSCRIPTIONS_MANAGE


class ExtrasManagePolicy(BaseActionPolicy):
    dashboard_code = "extras"
    permission_code = PermissionCode.EXTRAS_MANAGE


class AnalyticsExportPolicy(BaseActionPolicy):
    dashboard_code = "analytics"
    permission_code = PermissionCode.ANALYTICS_EXPORT
