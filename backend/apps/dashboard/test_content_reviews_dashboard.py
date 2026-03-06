import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.audit.models import AuditAction, AuditLog
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.marketplace.models import ServiceRequest
from apps.providers.models import Category, ProviderProfile, SubCategory
from apps.reviews.models import Review, ReviewModerationStatus
from apps.content.models import SiteContentBlock, SiteLegalDocument
from apps.unified_requests.models import UnifiedRequest


pytestmark = pytest.mark.django_db

PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\x0cIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfeA\x89\x1e\x1b\x00\x00\x00\x00IEND\xaeB`\x82"
)


def _login_dashboard_user(phone: str, level: str, dashboards: list[str], *, is_staff: bool = True):
    user = User.objects.create_user(phone=phone, password="Pass12345!", is_staff=is_staff)
    ap = UserAccessProfile.objects.create(user=user, level=level)
    dashboard_objs = []
    for i, code in enumerate(dashboards, start=1):
        dashboard, _ = Dashboard.objects.get_or_create(
            code=code,
            defaults={"name_ar": code, "sort_order": i},
        )
        dashboard_objs.append(dashboard)
    ap.allowed_dashboards.set(dashboard_objs)

    c = Client()
    assert c.login(phone=phone, password="Pass12345!")
    session = c.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return user, c


def _make_review() -> Review:
    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="هوية", is_active=True)
    client_user = User.objects.create_user(phone="0500011111", password="Pass12345!")
    provider_user = User.objects.create_user(phone="0500011112", password="Pass12345!")
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود تجريبي",
        bio="bio",
        city="الرياض",
        years_experience=1,
    )
    req = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type="competitive",
        city="الرياض",
        status="completed",
    )
    return Review.objects.create(
        request=req,
        provider=provider,
        client=client_user,
        rating=5,
        comment="ممتاز",
    )


def test_content_dashboard_admin_write_and_qa_readonly():
    _admin_user, admin_client = _login_dashboard_user("0500011200", AccessLevel.ADMIN, ["content"])
    _qa_user, qa_client = _login_dashboard_user("0500011201", AccessLevel.QA, ["content"])

    get_admin = admin_client.get(reverse("dashboard:content_management"))
    assert get_admin.status_code == 200

    post_admin = admin_client.post(
        reverse("dashboard:content_block_update_action", args=["onboarding_first_time"]),
        data={
            "title_ar": "عنوان آمن\nسطر ثان",
            "body_ar": "<script>alert(1)</script> نص\nسطر إضافي",
            "is_active": "on",
        },
    )
    assert post_admin.status_code == 302
    block = SiteContentBlock.objects.get(key="onboarding_first_time")
    assert block.title_ar == "عنوان آمن\nسطر ثان"
    assert "script" not in block.body_ar.lower()
    assert block.body_ar == "alert(1) نص\nسطر إضافي"

    get_qa = qa_client.get(reverse("dashboard:content_management"))
    assert get_qa.status_code == 200

    before_title = block.title_ar
    post_qa = qa_client.post(
        reverse("dashboard:content_block_update_action", args=["onboarding_first_time"]),
        data={"title_ar": "تعديل QA", "body_ar": "لا يجب الحفظ", "is_active": "on"},
    )
    assert post_qa.status_code in (302, 403)
    block.refresh_from_db()
    assert block.title_ar == before_title


def test_content_block_update_accepts_media_and_can_remove_it():
    _admin_user, admin_client = _login_dashboard_user("0500011202", AccessLevel.ADMIN, ["content"])

    upload = SimpleUploadedFile("hero.png", PNG_BYTES, content_type="image/png")
    save_res = admin_client.post(
        reverse("dashboard:content_block_update_action", args=["onboarding_intro"]),
        data={
            "title_ar": "عنوان مع صورة",
            "body_ar": "وصف مع صورة",
            "is_active": "on",
            "media_file": upload,
        },
    )

    assert save_res.status_code == 302
    block = SiteContentBlock.objects.get(key="onboarding_intro")
    assert block.media_type == "image"
    assert bool(block.media_file)

    remove_res = admin_client.post(
        reverse("dashboard:content_block_update_action", args=["onboarding_intro"]),
        data={
            "title_ar": "عنوان مع صورة",
            "body_ar": "وصف مع صورة",
            "is_active": "on",
            "remove_media": "on",
        },
    )

    assert remove_res.status_code == 302
    block.refresh_from_db()
    assert not block.media_file


def test_content_block_update_rejects_invalid_media_file():
    _admin_user, admin_client = _login_dashboard_user("0500011203", AccessLevel.ADMIN, ["content"])

    bad_file = SimpleUploadedFile("hero.exe", b"MZ", content_type="application/octet-stream")
    res = admin_client.post(
        reverse("dashboard:content_block_update_action", args=["settings_help"]),
        data={
            "title_ar": "عنوان",
            "body_ar": "محتوى",
            "is_active": "on",
            "media_file": bad_file,
        },
    )

    assert res.status_code == 302
    block = SiteContentBlock.objects.get(key="settings_help")
    assert not block.media_file


def test_content_document_upload_validation_rejects_invalid_file():
    _admin_user, admin_client = _login_dashboard_user("0500011300", AccessLevel.ADMIN, ["content"])

    bad_file = SimpleUploadedFile("terms.exe", b"MZ test", content_type="application/octet-stream")
    res = admin_client.post(
        reverse("dashboard:content_doc_upload_action", args=["terms"]),
        data={"file": bad_file, "version": "2.0", "is_active": "on"},
    )
    assert res.status_code == 302
    assert SiteLegalDocument.objects.count() == 0


def test_content_document_upload_accepts_multiline_text_without_file():
    _admin_user, admin_client = _login_dashboard_user("0500011301", AccessLevel.ADMIN, ["content"])

    res = admin_client.post(
        reverse("dashboard:content_doc_upload_action", args=["terms"]),
        data={
            "body_ar": "السطر الأول\nالسطر الثاني",
            "version": "2.1",
            "is_active": "on",
        },
    )

    assert res.status_code == 302
    doc = SiteLegalDocument.objects.get(doc_type="terms")
    assert doc.body_ar == "السطر الأول\nالسطر الثاني"
    assert not doc.file


def test_content_document_upload_requires_text_or_file():
    _admin_user, admin_client = _login_dashboard_user("0500011302", AccessLevel.ADMIN, ["content"])

    res = admin_client.post(
        reverse("dashboard:content_doc_upload_action", args=["privacy"]),
        data={"body_ar": "   ", "version": "1.0", "is_active": "on"},
    )

    assert res.status_code == 302
    assert SiteLegalDocument.objects.count() == 0


def test_reviews_dashboard_smoke_permissions_and_transition():
    review = _make_review()
    admin_user, admin_client = _login_dashboard_user("0500011400", AccessLevel.ADMIN, ["content"])
    _qa_user, qa_client = _login_dashboard_user("0500011401", AccessLevel.QA, ["content"])

    list_res = admin_client.get(reverse("dashboard:reviews_dashboard_list"))
    assert list_res.status_code == 200

    detail_res = admin_client.get(reverse("dashboard:reviews_dashboard_detail", args=[review.id]))
    assert detail_res.status_code == 200

    moderate_res = admin_client.post(
        reverse("dashboard:reviews_dashboard_moderate_action", args=[review.id]),
        data={"action": "hide", "moderation_note": "مخالفة"},
    )
    assert moderate_res.status_code == 302

    review.refresh_from_db()
    assert review.moderation_status == ReviewModerationStatus.HIDDEN
    assert review.moderated_by_id == admin_user.id
    ur = UnifiedRequest.objects.get(
        source_app="reviews",
        source_model="Review",
        source_object_id=str(review.id),
    )
    assert ur.request_type == "reviews"
    assert ur.status == "closed"

    log = AuditLog.objects.filter(
        action=AuditAction.REVIEW_MODERATED,
        reference_type="reviews.review",
        reference_id=str(review.id),
    ).first()
    assert log is not None

    qa_moderate = qa_client.post(
        reverse("dashboard:reviews_dashboard_moderate_action", args=[review.id]),
        data={"action": "approve", "moderation_note": "QA should not write"},
    )
    assert qa_moderate.status_code in (302, 403)
    review.refresh_from_db()
    assert review.moderation_status == ReviewModerationStatus.HIDDEN


def test_hidden_review_not_returned_in_public_provider_reviews_api():
    review = _make_review()
    review.moderation_status = ReviewModerationStatus.HIDDEN
    review.save(update_fields=["moderation_status"])

    client = APIClient()
    res = client.get(f"/api/reviews/providers/{review.provider_id}/reviews/")
    assert res.status_code == 200
    assert len(res.data) == 0


def test_access_profiles_page_clarifies_access_expiration_term():
    _admin_user, admin_client = _login_dashboard_user("0500011500", AccessLevel.ADMIN, ["access"])
    res = admin_client.get(reverse("dashboard:access_profiles_list"))
    assert res.status_code == 200
    html = res.content.decode("utf-8")
    assert "انتهاء صلاحية الوصول" in html
