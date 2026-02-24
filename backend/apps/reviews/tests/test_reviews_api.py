import pytest
from datetime import timedelta
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.providers.models import Category, SubCategory, ProviderProfile, ProviderCategory
from apps.marketplace.models import ServiceRequest, RequestType, RequestStatus
from apps.reviews.models import Review
from apps.notifications.models import Notification


@pytest.mark.django_db
def test_review_only_after_completed_and_only_owner_and_no_duplicate():
    client_user = User.objects.create_user(phone="0510000001", role_state=UserRole.CLIENT)
    other_user = User.objects.create_user(phone="0510000002")
    provider_user = User.objects.create_user(phone="0510000003")

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    cat = Category.objects.create(name="تصميم")
    sub = SubCategory.objects.create(category=cat, name="شعار")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.IN_PROGRESS,  # ليس مكتمل
        city="الرياض",
    )

    api = APIClient()

    # غير المالك ممنوع
    api.force_authenticate(user=other_user)
    r0 = api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 5,
            "cost_value": 5,
            "quality": 5,
            "credibility": 5,
            "on_time": 5,
            "comment": "x",
        },
        format="json",
    )
    assert r0.status_code in (400, 403)

    # المالك لكن قبل COMPLETED ممنوع
    api.force_authenticate(user=client_user)
    r1 = api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 5,
            "cost_value": 5,
            "quality": 5,
            "credibility": 5,
            "on_time": 5,
            "comment": "ممتاز",
        },
        format="json",
    )
    assert r1.status_code == 400

    # اجعل الطلب مكتمل ثم قيّم
    sr.status = RequestStatus.COMPLETED
    sr.save(update_fields=["status"])

    r2 = api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 4,
            "cost_value": 4,
            "quality": 4,
            "credibility": 4,
            "on_time": 4,
            "comment": "جيد",
        },
        format="json",
    )
    assert r2.status_code == 201
    assert Review.objects.filter(request=sr).count() == 1

    provider.refresh_from_db()
    assert provider.rating_count == 1
    assert float(provider.rating_avg) == 4.0

    # منع التكرار
    r3 = api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 5,
            "cost_value": 5,
            "quality": 5,
            "credibility": 5,
            "on_time": 5,
        },
        format="json",
    )
    assert r3.status_code == 400


@pytest.mark.django_db
def test_provider_rating_summary_and_reviews_list():
    client_user = User.objects.create_user(phone="0510000101", role_state=UserRole.CLIENT)
    provider_user = User.objects.create_user(phone="0510000102")

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    cat = Category.objects.create(name="برمجة")
    sub = SubCategory.objects.create(category=cat, name="ويب")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.COMPLETED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 5,
            "cost_value": 5,
            "quality": 5,
            "credibility": 5,
            "on_time": 5,
            "comment": "ممتاز",
        },
        format="json",
    )

    api2 = APIClient()
    r_sum = api2.get(f"/api/reviews/providers/{provider.id}/rating/")
    assert r_sum.status_code == 200
    assert int(r_sum.data["rating_count"]) == 1
    assert float(r_sum.data["rating_avg"]) == 5.0
    assert float(r_sum.data["response_speed_avg"]) == 5.0
    assert float(r_sum.data["cost_value_avg"]) == 5.0
    assert float(r_sum.data["quality_avg"]) == 5.0
    assert float(r_sum.data["credibility_avg"]) == 5.0
    assert float(r_sum.data["on_time_avg"]) == 5.0

    r_list = api2.get(f"/api/reviews/providers/{provider.id}/reviews/")
    assert r_list.status_code == 200
    assert len(r_list.data) >= 1


@pytest.mark.django_db
def test_review_allowed_for_cancelled_request():
    client_user = User.objects.create_user(phone="0510000201", role_state=UserRole.CLIENT)
    provider_user = User.objects.create_user(phone="0510000202")

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="تصميم داخلي")
    sub = SubCategory.objects.create(category=cat, name="ديكور")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.CANCELLED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    r = api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 4,
            "cost_value": 4,
            "quality": 4,
            "credibility": 4,
            "on_time": 4,
            "comment": "تم الإلغاء لكن التجربة واضحة",
        },
        format="json",
    )
    assert r.status_code == 201


@pytest.mark.django_db
def test_provider_can_reply_to_own_review_and_reply_appears_in_list():
    client_user = User.objects.create_user(phone="0510000301", role_state=UserRole.CLIENT)
    provider_user = User.objects.create_user(
        phone="0510000302",
        role_state=UserRole.PROVIDER,
    )
    other_provider_user = User.objects.create_user(
        phone="0510000303",
        role_state=UserRole.PROVIDER,
    )

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    other_provider = ProviderProfile.objects.create(
        user=other_provider_user,
        provider_type="individual",
        display_name="مزود آخر",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="تصميم")
    sub = SubCategory.objects.create(category=cat, name="هوية")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)
    ProviderCategory.objects.create(provider=other_provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.COMPLETED,
        city="الرياض",
    )

    api_client = APIClient()
    api_client.force_authenticate(user=client_user)
    r_create = api_client.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 5,
            "cost_value": 4,
            "quality": 5,
            "credibility": 5,
            "on_time": 4,
            "comment": "خدمة ممتازة",
        },
        format="json",
    )
    assert r_create.status_code == 201
    review_id = int(r_create.data["review_id"])

    api_other = APIClient()
    api_other.force_authenticate(user=other_provider_user)
    r_forbidden = api_other.post(
        f"/api/reviews/reviews/{review_id}/provider-reply/",
        {"provider_reply": "رد غير مصرح"},
        format="json",
    )
    assert r_forbidden.status_code == 403

    api_provider = APIClient()
    api_provider.force_authenticate(user=provider_user)
    r_reply = api_provider.post(
        f"/api/reviews/reviews/{review_id}/provider-reply/",
        {"provider_reply": "شكرًا لك، نسعد بخدمتك دائمًا"},
        format="json",
    )
    assert r_reply.status_code == 200
    assert r_reply.data["provider_reply"] == "شكرًا لك، نسعد بخدمتك دائمًا"
    assert r_reply.data["provider_reply_is_edited"] is False

    review = Review.objects.get(id=review_id)
    assert review.provider_reply == "شكرًا لك، نسعد بخدمتك دائمًا"
    assert review.provider_reply_at is not None
    assert review.provider_reply_edited_at is None

    r_edit = api_provider.post(
        f"/api/reviews/reviews/{review_id}/provider-reply/",
        {"provider_reply": "شكرًا لك، تم تحديث الرد"},
        format="json",
    )
    assert r_edit.status_code == 200
    assert r_edit.data["provider_reply_is_edited"] is True

    review.refresh_from_db()
    assert review.provider_reply == "شكرًا لك، تم تحديث الرد"
    assert review.provider_reply_edited_at is not None

    r_list = APIClient().get(f"/api/reviews/providers/{provider.id}/reviews/")
    assert r_list.status_code == 200
    assert len(r_list.data) >= 1
    first = r_list.data[0]
    assert first["provider_reply"] == "شكرًا لك، تم تحديث الرد"
    assert first["provider_reply_is_edited"] is True

    r_delete = api_provider.delete(f"/api/reviews/reviews/{review_id}/provider-reply/")
    assert r_delete.status_code == 200
    review.refresh_from_db()
    assert review.provider_reply == ""
    assert review.provider_reply_at is None
    assert review.provider_reply_edited_at is None

    # إشعارات للعميل: إنشاء رد + تعديل + حذف
    notes = Notification.objects.filter(user=client_user).order_by("id")
    assert notes.count() == 3
    assert "رد مقدم الخدمة" in notes[0].title
    assert "تعديل" in notes[1].title
    assert "حذف" in notes[2].title
    assert notes[0].kind == "review_reply"
    assert notes[1].kind == "review_reply"
    assert notes[2].kind == "review_reply"
    assert notes[0].url == f"/requests/{sr.id}/"


@pytest.mark.django_db
def test_review_allowed_for_in_progress_after_expected_delivery_plus_48h():
    client_user = User.objects.create_user(phone="0510000301", role_state=UserRole.CLIENT)
    provider_user = User.objects.create_user(phone="0510000302")

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="برمجة")
    sub = SubCategory.objects.create(category=cat, name="تطبيقات")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.URGENT,
        status=RequestStatus.IN_PROGRESS,
        city="الرياض",
        expected_delivery_at=timezone.now() - timedelta(hours=49),
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    r = api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 3,
            "cost_value": 3,
            "quality": 3,
            "credibility": 3,
            "on_time": 2,
            "comment": "تجاوز الوقت",
        },
        format="json",
    )
    assert r.status_code == 201


@pytest.mark.django_db
def test_delete_review_updates_provider_rating_aggregates():
    client_user = User.objects.create_user(phone="0510000401", role_state=UserRole.CLIENT)
    provider_user = User.objects.create_user(phone="0510000402")

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="تصميم")
    sub = SubCategory.objects.create(category=cat, name="شعار")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.COMPLETED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    r = api.post(
        f"/api/reviews/requests/{sr.id}/review/",
        {
            "response_speed": 5,
            "cost_value": 5,
            "quality": 5,
            "credibility": 5,
            "on_time": 5,
            "comment": "ممتاز",
        },
        format="json",
    )
    assert r.status_code == 201

    provider.refresh_from_db()
    assert provider.rating_count == 1
    assert float(provider.rating_avg) == 5.0

    review = Review.objects.get(request=sr)
    review.delete()

    provider.refresh_from_db()
    assert provider.rating_count == 0
    assert float(provider.rating_avg) == 0.0
