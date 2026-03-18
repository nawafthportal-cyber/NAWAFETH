import pytest
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.moderation.models import ModerationCase, ModerationDecisionCode, ModerationStatus
from apps.moderation.services import change_case_status, create_case, record_decision


pytestmark = pytest.mark.django_db


def test_moderation_case_generates_code_and_summary():
    reporter = User.objects.create_user(phone="0580000001", password="Pass12345!", role_state=UserRole.PHONE_ONLY)

    case = ModerationCase.objects.create(
        reporter=reporter,
        source_app="messaging",
        source_model="Thread",
        source_object_id="15",
        source_label="محادثة",
        reason="إساءة",
        details="تفاصيل البلاغ",
    )

    assert case.code.startswith("MC")
    assert "إساءة" in case.summary


def test_record_decision_updates_final_status():
    reporter = User.objects.create_user(phone="0580000002", password="Pass12345!", role_state=UserRole.PHONE_ONLY)
    moderator = User.objects.create_user(phone="0580000003", password="Pass12345!", role_state=UserRole.STAFF)
    case = create_case(reporter=reporter, payload={"reason": "مخالف", "details": "test"})

    decision = record_decision(
        case=case,
        decision_code=ModerationDecisionCode.DELETE,
        note="حذف المحتوى",
        by_user=moderator,
    )

    case.refresh_from_db()
    assert decision.case_id == case.id
    assert case.status == ModerationStatus.ACTION_TAKEN
    assert case.decisions.count() == 1
    assert case.action_logs.count() >= 2


def test_escalation_and_latest_decision_meta_are_tracked():
    reporter = User.objects.create_user(phone="0580000004", password="Pass12345!", role_state=UserRole.PHONE_ONLY)
    moderator = User.objects.create_user(phone="0580000005", password="Pass12345!", role_state=UserRole.STAFF)
    case = create_case(reporter=reporter, payload={"reason": "تصعيد", "details": "test"})

    change_case_status(case=case, new_status=ModerationStatus.ESCALATED, note="needs senior review", by_user=moderator)
    record_decision(
        case=case,
        decision_code=ModerationDecisionCode.WARN,
        note="warn user",
        by_user=moderator,
        is_final=True,
    )

    case.refresh_from_db()
    assert int(case.meta.get("escalation_count") or 0) >= 1
    assert case.meta.get("last_escalated_by_id") == moderator.id
    assert case.meta.get("last_decision", {}).get("decision_code") == ModerationDecisionCode.WARN
    assert case.closed_at is not None
    assert case.sla_state(now=timezone.now()) in {"open", "none", "closed"}
