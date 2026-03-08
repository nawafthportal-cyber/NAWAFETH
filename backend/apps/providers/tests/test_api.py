from decimal import Decimal

import pytest
from rest_framework.test import APIClient

from apps.accounts.models import OTP
from apps.providers.models import (
    Category,
    ProviderCategory,
    ProviderFollow,
    ProviderLike,
    ProviderPortfolioItem,
    ProviderPortfolioLike,
    ProviderPortfolioSave,
    ProviderProfile,
    ProviderSpotlightItem,
    ProviderSpotlightLike,
    ProviderSpotlightSave,
    RoleContext,
    SubCategory,
)
from apps.subscriptions.models import Subscription, SubscriptionStatus
from django.core.files.uploadedfile import SimpleUploadedFile


@pytest.mark.django_db
def test_get_categories_returns_active_with_subcategories():
    active = Category.objects.create(name="تصميم", is_active=True)
    SubCategory.objects.create(category=active, name="شعارات", is_active=True)

    Category.objects.create(name="غير نشط", is_active=False)

    client = APIClient()
    res = client.get("/api/providers/categories/")

    assert res.status_code == 200
    assert isinstance(res.json(), list)

    payload = res.json()
    assert len(payload) == 1
    assert payload[0]["name"] == "تصميم"
    assert payload[0]["subcategories"][0]["name"] == "شعارات"


@pytest.mark.django_db
def test_provider_register_flow_via_otp_and_jwt():
    client = APIClient()

    # 1) OTP send
    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000000"},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000000").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    # 2) OTP verify -> JWT
    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000000", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]

    # 3) Authenticated register provider
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    # 2.5) Complete registration (level 3)
    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "Test",
            "last_name": "Provider",
            "username": "user_0500000000",
            "email": "0500000000@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    reg = client.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "محمد التصميم",
            "bio": "مصمم جرافيك محترف",
            "years_experience": 5,
            "city": "الرياض",
            "accepts_urgent": True,
        },
        format="json",
    )

    assert reg.status_code == 201
    assert ProviderProfile.objects.count() == 1
    profile = ProviderProfile.objects.first()
    assert profile is not None
    assert profile.display_name == "محمد التصميم"
    assert profile.city == "الرياض"
    basic_sub = Subscription.objects.filter(
        user=profile.user,
        status=SubscriptionStatus.ACTIVE,
        plan__code="basic",
    ).select_related("plan").first()
    assert basic_sub is not None
    assert Subscription.objects.filter(
        user=profile.user,
        status=SubscriptionStatus.ACTIVE,
        plan__code="basic",
    ).count() == 1
    assert basic_sub.plan.price == Decimal("0.00")


def _register_and_auth_provider(client: APIClient, phone: str = "0500000000") -> str:
    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": phone},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone=phone).order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": phone, "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]

    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "Test",
            "last_name": "Provider",
            "username": f"user_{phone}",
            "email": f"{phone}@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    reg = client.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "محمد التصميم",
            "bio": "مصمم جرافيك محترف",
            "years_experience": 5,
            "city": "الرياض",
            "accepts_urgent": True,
        },
        format="json",
    )
    assert reg.status_code == 201
    return access


@pytest.mark.django_db
def test_provider_services_requires_auth():
    client = APIClient()
    res = client.get("/api/providers/me/services/")
    assert res.status_code in (401, 403)


@pytest.mark.django_db
def test_provider_services_crud_and_public_list():
    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)

    client = APIClient()
    _register_and_auth_provider(client, phone="0500000001")

    create = client.post(
        "/api/providers/me/services/",
        {
            "title": "تصميم شعار احترافي",
            "description": "3 نماذج + تسليم الملفات المفتوحة",
            "price_from": "250.00",
            "price_to": "500.00",
            "price_unit": "fixed",
            "is_active": True,
            "subcategory_id": sub.id,
        },
        format="json",
    )
    assert create.status_code == 201
    service = create.json()
    assert service["title"] == "تصميم شعار احترافي"
    assert service["subcategory"]["id"] == sub.id
    assert service["price_unit_label"] == "سعر ثابت"
    service_id = service["id"]

    me_list = client.get("/api/providers/me/services/")
    assert me_list.status_code == 200
    assert isinstance(me_list.json(), list)
    assert len(me_list.json()) == 1

    patch = client.patch(
        f"/api/providers/me/services/{service_id}/",
        {"title": "تصميم شعار (محدث)"},
        format="json",
    )
    assert patch.status_code == 200
    assert patch.json()["title"] == "تصميم شعار (محدث)"

    provider_id = ProviderProfile.objects.first().id
    public_list = client.get(f"/api/providers/{provider_id}/services/")
    assert public_list.status_code == 200
    assert len(public_list.json()) == 1

    public_detail = client.get(f"/api/providers/services/{service_id}/")
    assert public_detail.status_code == 200
    assert public_detail.json()["id"] == service_id
    assert public_detail.json()["provider_id"] == provider_id
    assert public_detail.json()["provider_name"] == "محمد التصميم"
    assert public_detail.json()["category_name"] == "تصميم"
    assert public_detail.json()["price_unit_label"] == "سعر ثابت"

    delete = client.delete(f"/api/providers/me/services/{service_id}/")
    assert delete.status_code in (200, 204)

    public_list2 = client.get(f"/api/providers/{provider_id}/services/")
    assert public_list2.status_code == 200
    assert len(public_list2.json()) == 0

    public_detail2 = client.get(f"/api/providers/services/{service_id}/")
    assert public_detail2.status_code == 404


@pytest.mark.django_db
def test_provider_list_supports_urgent_and_location_filters():
    cat = Category.objects.create(name="خدمات منزلية", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    from apps.accounts.models import User

    p1_user = User.objects.create(phone="0501111111", username="provider_a")
    p1 = ProviderProfile.objects.create(
        user=p1_user,
        provider_type="individual",
        display_name="مزود عاجل مع موقع",
        bio="bio",
        years_experience=2,
        city="الرياض",
        accepts_urgent=True,
        lat=24.7136,
        lng=46.6753,
    )
    ProviderCategory.objects.get_or_create(provider=p1, subcategory=sub)

    p2_user = User.objects.create(phone="0502222222", username="provider_b")
    p2 = ProviderProfile.objects.create(
        user=p2_user,
        provider_type="individual",
        display_name="مزود بدون موقع",
        bio="bio",
        years_experience=2,
        city="الرياض",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=p2, subcategory=sub)

    p3_user = User.objects.create(phone="0503333333", username="provider_c")
    p3 = ProviderProfile.objects.create(
        user=p3_user,
        provider_type="individual",
        display_name="مزود غير عاجل",
        bio="bio",
        years_experience=2,
        city="الرياض",
        accepts_urgent=False,
        lat=24.7200,
        lng=46.6800,
    )
    ProviderCategory.objects.get_or_create(provider=p3, subcategory=sub)

    client = APIClient()
    res = client.get(
        "/api/providers/list/",
        {
            "subcategory_id": sub.id,
            "city": "الرياض",
            "has_location": "true",
            "accepts_urgent": "true",
        },
    )

    assert res.status_code == 200
    payload = res.json()
    assert len(payload) == 1
    assert payload[0]["display_name"] == "مزود عاجل مع موقع"


@pytest.mark.django_db
def test_provider_can_upload_profile_and_cover_images(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path
    settings.STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }

    client = APIClient()
    _register_and_auth_provider(client, phone="0500000099")

    png_bytes = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
        b"\x00\x00\x00\x0cIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfeA\x89\x1e\x1b\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    profile_upload = SimpleUploadedFile("profile.png", png_bytes, content_type="image/png")
    cover_upload = SimpleUploadedFile("cover.png", png_bytes, content_type="image/png")

    res = client.patch(
        "/api/providers/me/profile/",
        {
            "profile_image": profile_upload,
            "cover_image": cover_upload,
        },
        format="multipart",
    )
    assert res.status_code == 200
    payload = res.json()
    assert payload.get("profile_image")
    assert payload.get("cover_image")

    profile = ProviderProfile.objects.get(user__phone="0500000099")
    assert bool(profile.profile_image)
    assert bool(profile.cover_image)


@pytest.mark.django_db
def test_provider_profile_hides_missing_media_urls(settings, tmp_path):
    """When a file path is stored in DB but the file is missing from storage,
    we still return the URL (no ``storage.exists()`` check) so that R2/S3
    backends are not penalised with a HEAD request per file.  The client
    handles 404 gracefully.
    """
    settings.MEDIA_ROOT = tmp_path
    settings.STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }

    client = APIClient()
    _register_and_auth_provider(client, phone="0500000100")
    profile = ProviderProfile.objects.get(user__phone="0500000100")
    profile.profile_image = "providers/profile/2026/03/missing_profile.jpg"
    profile.cover_image = "providers/cover/2026/03/missing_cover.jpg"
    profile.save(update_fields=["profile_image", "cover_image"])

    me = client.get("/api/providers/me/profile/")
    assert me.status_code == 200
    me_payload = me.json()
    # URL is returned even if the file doesn't exist on disk
    assert "missing_profile.jpg" in (me_payload.get("profile_image") or "")
    assert "missing_cover.jpg" in (me_payload.get("cover_image") or "")

    public = client.get(f"/api/providers/{profile.id}/")
    assert public.status_code == 200
    public_payload = public.json()
    assert "missing_profile.jpg" in (public_payload.get("profile_image") or "")
    assert "missing_cover.jpg" in (public_payload.get("cover_image") or "")


@pytest.mark.django_db
def test_provider_following_count_in_detail_and_stats_is_scoped_by_mode():
    from apps.accounts.models import User

    owner_user = User.objects.create(phone="0500000111", username="owner_provider")
    owner_provider = ProviderProfile.objects.create(
        user=owner_user,
        provider_type="individual",
        display_name="Owner Provider",
        bio="bio",
        years_experience=2,
        city="الرياض",
    )

    target_user_1 = User.objects.create(phone="0500000112", username="target_provider_1")
    target_provider_1 = ProviderProfile.objects.create(
        user=target_user_1,
        provider_type="individual",
        display_name="Target One",
        bio="bio",
        years_experience=2,
        city="الرياض",
    )

    target_user_2 = User.objects.create(phone="0500000113", username="target_provider_2")
    target_provider_2 = ProviderProfile.objects.create(
        user=target_user_2,
        provider_type="individual",
        display_name="Target Two",
        bio="bio",
        years_experience=2,
        city="جدة",
    )

    ProviderFollow.objects.create(
        user=owner_user,
        provider=target_provider_1,
        role_context=RoleContext.CLIENT,
    )
    ProviderFollow.objects.create(
        user=owner_user,
        provider=target_provider_2,
        role_context=RoleContext.PROVIDER,
    )

    client = APIClient()

    detail_client = client.get(f"/api/providers/{owner_provider.id}/?mode=client")
    assert detail_client.status_code == 200
    assert detail_client.json().get("following_count") == 1

    detail_provider = client.get(f"/api/providers/{owner_provider.id}/?mode=provider")
    assert detail_provider.status_code == 200
    assert detail_provider.json().get("following_count") == 1

    stats_client = client.get(f"/api/providers/{owner_provider.id}/stats/?mode=client")
    assert stats_client.status_code == 200
    assert stats_client.json().get("following_count") == 1

    stats_provider = client.get(f"/api/providers/{owner_provider.id}/stats/?mode=provider")
    assert stats_provider.status_code == 200
    assert stats_provider.json().get("following_count") == 1


@pytest.mark.django_db
def test_my_following_counts_match_provider_profile_stats_unique_users():
    from apps.accounts.models import User, UserRole

    current_user = User.objects.create(
        phone="0500000211",
        username="current_client",
        role_state=UserRole.CLIENT,
    )
    owner_user = User.objects.create(
        phone="0500000212",
        username="owner_provider",
        role_state=UserRole.PROVIDER,
    )
    provider = ProviderProfile.objects.create(
        user=owner_user,
        provider_type="individual",
        display_name="Provider Profile Counts",
        bio="bio",
        years_experience=3,
        city="الرياض",
    )

    dual_role_follower = User.objects.create(phone="0500000213", username="dual_role_follower")
    provider_mode_follower = User.objects.create(phone="0500000214", username="provider_mode_follower")

    # Provider appears in current user's "following" list through client mode.
    ProviderFollow.objects.create(
        user=current_user,
        provider=provider,
        role_context=RoleContext.CLIENT,
    )
    # Same user follows from both modes; should still count as one unique follower.
    ProviderFollow.objects.create(
        user=dual_role_follower,
        provider=provider,
        role_context=RoleContext.CLIENT,
    )
    ProviderFollow.objects.create(
        user=dual_role_follower,
        provider=provider,
        role_context=RoleContext.PROVIDER,
    )
    ProviderFollow.objects.create(
        user=provider_mode_follower,
        provider=provider,
        role_context=RoleContext.PROVIDER,
    )

    ProviderLike.objects.create(
        user=dual_role_follower,
        provider=provider,
        role_context=RoleContext.CLIENT,
    )
    ProviderLike.objects.create(
        user=provider_mode_follower,
        provider=provider,
        role_context=RoleContext.CLIENT,
    )

    client = APIClient()
    client.force_authenticate(user=current_user)
    following = client.get("/api/providers/me/following/?mode=client")
    assert following.status_code == 200
    entry = next((p for p in following.json() if p.get("id") == provider.id), None)
    assert entry is not None

    stats = APIClient().get(f"/api/providers/{provider.id}/stats/?mode=client")
    assert stats.status_code == 200
    stats_payload = stats.json()

    assert stats_payload.get("followers_count") == 3
    assert entry.get("followers_count") == stats_payload.get("followers_count")
    assert entry.get("likes_count") == stats_payload.get("likes_count") == 2


@pytest.mark.django_db
def test_provider_stats_include_media_likes_and_saves_from_published_media(settings, tmp_path):
    from apps.accounts.models import User

    settings.MEDIA_ROOT = tmp_path

    owner_user = User.objects.create(phone="0500000911", username="owner_media_stats")
    owner_provider = ProviderProfile.objects.create(
        user=owner_user,
        provider_type="individual",
        display_name="Owner Media Stats",
        bio="bio",
        years_experience=2,
        city="الرياض",
    )

    png_bytes = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
        b"\x00\x00\x00\x0cIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfeA\x89\x1e\x1b\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    mp4_bytes = b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom"

    portfolio_item = ProviderPortfolioItem.objects.create(
        provider=owner_provider,
        file_type="image",
        file=SimpleUploadedFile("portfolio.png", png_bytes, content_type="image/png"),
        caption="portfolio",
    )
    spotlight_item = ProviderSpotlightItem.objects.create(
        provider=owner_provider,
        file_type="video",
        file=SimpleUploadedFile("spotlight.mp4", mp4_bytes, content_type="video/mp4"),
        caption="spotlight",
    )

    actor_one = User.objects.create(phone="0500000912", username="actor_media_one")
    actor_two = User.objects.create(phone="0500000913", username="actor_media_two")

    ProviderPortfolioLike.objects.create(
        user=actor_one,
        item=portfolio_item,
        role_context=RoleContext.CLIENT,
    )
    ProviderPortfolioLike.objects.create(
        user=actor_one,
        item=portfolio_item,
        role_context=RoleContext.PROVIDER,
    )
    ProviderSpotlightLike.objects.create(
        user=actor_two,
        item=spotlight_item,
        role_context=RoleContext.CLIENT,
    )

    ProviderPortfolioSave.objects.create(
        user=actor_two,
        item=portfolio_item,
        role_context=RoleContext.CLIENT,
    )
    ProviderSpotlightSave.objects.create(
        user=actor_one,
        item=spotlight_item,
        role_context=RoleContext.CLIENT,
    )

    ProviderLike.objects.create(
        user=actor_two,
        provider=owner_provider,
        role_context=RoleContext.CLIENT,
    )

    stats = APIClient().get(f"/api/providers/{owner_provider.id}/stats/?mode=provider")
    assert stats.status_code == 200
    payload = stats.json()

    assert payload.get("likes_count") == 1
    assert payload.get("profile_likes_count") == 1
    assert payload.get("portfolio_likes_count") == 2
    assert payload.get("spotlight_likes_count") == 1
    assert payload.get("media_likes_count") == 3
    assert payload.get("portfolio_saves_count") == 1
    assert payload.get("spotlight_saves_count") == 1
    assert payload.get("media_saves_count") == 2
