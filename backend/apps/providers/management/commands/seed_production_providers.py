from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP

from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Avg, Count
from django.db.models.signals import post_delete, post_save, pre_save
from django.utils import timezone
from django.utils.text import slugify

from apps.accounts.models import User, UserRole
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.promo.models import (
    HomeBanner,
    HomeBannerMediaType,
    PromoAdType,
    PromoOpsStatus,
    PromoPosition,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoSearchScope,
    PromoServiceType,
)
from apps.providers.models import (
    Category,
    ProviderCategory,
    ProviderFollow,
    ProviderLike,
    ProviderPortfolioItem,
    ProviderProfile,
    ProviderService,
    SaudiCity,
    SaudiRegion,
    SubCategory,
    sync_provider_accepts_urgent_flag,
)
from apps.reviews.models import Review, ReviewModerationStatus


SEED_PREFIX = "prod-demo"
PROVIDER_PHONE_BASE = "059880"
CLIENT_PHONE_BASE = "059881"


@dataclass(frozen=True)
class ProviderSeed:
    name: str
    provider_type: str
    category: str
    subcategory: str
    city: str
    region: str
    lat: Decimal
    lng: Decimal
    years: int
    rating_values: tuple[int, ...]
    service_title: str
    service_description: str
    price_from: Decimal
    price_to: Decimal | None
    keywords: str


PROVIDER_SEEDS: tuple[ProviderSeed, ...] = (
    ProviderSeed("مؤسسة إتقان التكييف", "company", "صيانة منزلية", "تكييف وتبريد", "الرياض", "منطقة الرياض", Decimal("24.713552"), Decimal("46.675296"), 9, (5, 5, 4, 5, 5, 4, 5), "صيانة وتركيب مكيفات سبليت", "فحص شامل، تنظيف فلاتر، تعبئة فريون عند الحاجة، وضمان مكتوب على العمل.", Decimal("180.00"), Decimal("450.00"), "تكييف، صيانة مكيفات، فريون، سبليت"),
    ProviderSeed("فني الكهرباء فهد العتيبي", "individual", "صيانة منزلية", "كهرباء", "جدة", "منطقة مكة المكرمة", Decimal("21.485811"), Decimal("39.192505"), 7, (5, 4, 5, 4, 5, 5), "إصلاح الأعطال الكهربائية المنزلية", "تتبع أعطال القواطع والإنارة وتركيب الأفياش والمفاتيح وفق معايير السلامة.", Decimal("120.00"), Decimal("320.00"), "كهرباء، قواطع، إنارة، صيانة منزلية"),
    ProviderSeed("سباك الرياض المحترف", "individual", "صيانة منزلية", "سباكة", "الرياض", "منطقة الرياض", Decimal("24.774265"), Decimal("46.738586"), 11, (5, 5, 5, 4, 5, 4, 5, 5), "كشف وإصلاح تسربات المياه", "معالجة التسربات، تبديل الخلاطات، تركيب السخانات، وتنظيف الانسدادات بسرعة.", Decimal("150.00"), Decimal("380.00"), "سباكة، تسربات، سخانات، انسداد"),
    ProviderSeed("لمعة كلين للخدمات المنزلية", "company", "تنظيف", "تنظيف منازل", "الدمام", "المنطقة الشرقية", Decimal("26.420682"), Decimal("50.088794"), 6, (4, 5, 4, 5, 4, 5), "تنظيف عميق للشقق والفلل", "فريق مجهز لتنظيف المطابخ والحمامات والزجاج والأرضيات بمواد آمنة.", Decimal("250.00"), Decimal("900.00"), "تنظيف، تعقيم، تنظيف فلل، تنظيف شقق"),
    ProviderSeed("نخبة الضيافة والمناسبات", "company", "فعاليات وضيافة", "تنظيم مناسبات", "الخبر", "المنطقة الشرقية", Decimal("26.217191"), Decimal("50.197138"), 8, (5, 5, 4, 4, 5, 5), "تنظيم حفلات منزلية وشركات", "تنسيق ضيافة، استقبال، بوفيه خفيف، وتجهيز كامل حسب عدد الحضور.", Decimal("900.00"), Decimal("4500.00"), "ضيافة، مناسبات، تنظيم حفلات، بوفيه"),
    ProviderSeed("استوديو زاوية للتصوير", "company", "إبداع وتصميم", "تصوير فوتوغرافي", "الرياض", "منطقة الرياض", Decimal("24.687731"), Decimal("46.721851"), 10, (5, 5, 5, 5, 4, 5, 5), "تصوير منتجات وبورتريه احترافي", "جلسات تصوير بإضاءة احترافية ومعالجة ألوان وتسليم ملفات عالية الجودة.", Decimal("600.00"), Decimal("2500.00"), "تصوير، منتجات، بورتريه، فوتوغرافي"),
    ProviderSeed("المهندسة سارة للتصميم الداخلي", "individual", "إبداع وتصميم", "تصميم داخلي", "جدة", "منطقة مكة المكرمة", Decimal("21.543333"), Decimal("39.172778"), 12, (5, 4, 5, 5, 5, 4), "تصميم داخلي للمنازل والمكاتب", "مخططات توزيع، لوحة مواد، تصورات ثلاثية الأبعاد، وقائمة مشتريات تنفيذية.", Decimal("1200.00"), Decimal("8500.00"), "تصميم داخلي، ديكور، مخططات، مكاتب"),
    ProviderSeed("حلول كود الرقمية", "company", "تقنية", "تطوير مواقع", "الرياض", "منطقة الرياض", Decimal("24.750000"), Decimal("46.680000"), 9, (5, 5, 4, 5, 5, 5), "تطوير مواقع تعريفية ومتاجر صغيرة", "تصميم واجهات سريعة ومتجاوبة، لوحة تحكم، وربط الدفع أو النماذج عند الحاجة.", Decimal("2500.00"), Decimal("12000.00"), "مواقع، متجر إلكتروني، برمجة، تطوير"),
    ProviderSeed("أمان الشبكات", "company", "تقنية", "دعم تقني وشبكات", "المدينة المنورة", "منطقة المدينة المنورة", Decimal("24.470901"), Decimal("39.612236"), 13, (4, 5, 5, 4, 5, 4), "تركيب شبكات منزلية ومكتبية", "تمديد نقاط، ضبط راوترات، تقوية واي فاي، وتأمين الشبكة للمنازل والمكاتب.", Decimal("300.00"), Decimal("1800.00"), "شبكات، واي فاي، دعم تقني، راوتر"),
    ProviderSeed("مكتب بيان للاستشارات القانونية", "company", "استشارات", "استشارات قانونية", "الرياض", "منطقة الرياض", Decimal("24.727000"), Decimal("46.698000"), 15, (5, 5, 5, 4, 5, 5), "استشارة قانونية للأفراد والمنشآت", "مراجعة عقود، مذكرات أولية، توجيه نظامي، وخطة إجراءات واضحة.", Decimal("350.00"), Decimal("1500.00"), "قانون، عقود، استشارات، منشآت"),
    ProviderSeed("مركز توازن للعلاج الطبيعي", "company", "الصحة والعافية", "علاج طبيعي", "جدة", "منطقة مكة المكرمة", Decimal("21.585000"), Decimal("39.200000"), 10, (5, 4, 5, 5, 4, 5, 5), "جلسات علاج طبيعي منزلية", "تقييم حركة، برنامج تأهيلي، وتمارين متابعة لكبار السن والإصابات الرياضية.", Decimal("220.00"), Decimal("650.00"), "علاج طبيعي، تأهيل، جلسات منزلية، إصابات"),
    ProviderSeed("مدرب اللياقة خالد", "individual", "الصحة والعافية", "تدريب شخصي", "الدمام", "المنطقة الشرقية", Decimal("26.392700"), Decimal("50.135900"), 6, (4, 5, 4, 5, 5, 4), "برنامج تدريب شخصي وتغذية", "خطة تمارين أسبوعية، متابعة قياسات، وإرشادات غذائية عملية حسب الهدف.", Decimal("300.00"), Decimal("1200.00"), "تدريب، لياقة، تغذية، برنامج رياضي"),
    ProviderSeed("روضة خطوات للتعليم المبكر", "company", "تعليم وتدريب", "دروس خصوصية", "مكة المكرمة", "منطقة مكة المكرمة", Decimal("21.389082"), Decimal("39.857912"), 8, (5, 5, 4, 5, 4, 5), "دروس تأسيس للأطفال", "تأسيس قراءة وكتابة وحساب للمرحلة الابتدائية بخطة متابعة شهرية.", Decimal("90.00"), Decimal("280.00"), "دروس، تأسيس، أطفال، تعليم"),
    ProviderSeed("أكاديمية مهارات الأعمال", "company", "تعليم وتدريب", "تدريب مهني", "الرياض", "منطقة الرياض", Decimal("24.800000"), Decimal("46.710000"), 14, (5, 4, 5, 4, 5, 5), "دورات إكسل وإدارة مشاريع", "تدريب عملي للموظفين والباحثين عن عمل مع ملفات تطبيقية وشهادة حضور.", Decimal("450.00"), Decimal("1800.00"), "تدريب مهني، إكسل، إدارة مشاريع، دورات"),
    ProviderSeed("مشاوير النخبة", "company", "نقل وخدمات", "نقل أثاث", "الخبر", "المنطقة الشرقية", Decimal("26.236124"), Decimal("50.039303"), 9, (4, 5, 5, 4, 5, 4, 5), "نقل أثاث مع الفك والتركيب", "سيارات مغلقة، تغليف، فك وتركيب غرف النوم والمكاتب، وجدولة دقيقة.", Decimal("500.00"), Decimal("2200.00"), "نقل أثاث، تغليف، فك وتركيب، نقل"),
)


CLIENT_NAMES = (
    ("أحمد", "السبيعي"),
    ("نورة", "الحربي"),
    ("عبدالله", "الغامدي"),
    ("ريم", "الشمري"),
    ("ماجد", "الزهراني"),
    ("هند", "العتيبي"),
    ("سلمان", "المطيري"),
    ("لينا", "القحطاني"),
)

REVIEW_COMMENTS = (
    "التواصل كان سريعاً والنتيجة ممتازة. التجربة أعطتني ثقة أطلب الخدمة مرة ثانية.",
    "التزم بالوقت وشرح لي كل خطوة قبل التنفيذ، وهذا فرق معي كثيراً.",
    "الخدمة مرتبة والسعر واضح من البداية. أنصح به لمن يبحث عن شغل محترف.",
    "تعامل راق وتفاصيل دقيقة، والنتيجة النهائية كانت أفضل من المتوقع.",
    "وصل في الموعد وأنهى العمل بدون إزعاج. تقييم مستحق.",
    "متابعة ممتازة بعد الخدمة وسرعة في الرد على الاستفسارات.",
)


class Command(BaseCommand):
    help = "Seed 15 production-like provider profiles, reviews, services, and active promo placements."

    def add_arguments(self, parser):
        parser.add_argument(
            "--confirm-production",
            action="store_true",
            help="Required safety flag. Confirms that you intentionally want to seed visible production data.",
        )
        parser.add_argument(
            "--reset-generated",
            action="store_true",
            help="Delete previously generated demo rows that use this command's phone/username/title prefixes before seeding.",
        )
        parser.add_argument(
            "--delete-only",
            action="store_true",
            help="Delete previously generated demo rows and exit without creating new ones.",
        )
        parser.add_argument(
            "--days",
            type=int,
            default=60,
            help="Number of days the generated promo placements stay active. Default: 60.",
        )
        parser.add_argument(
            "--no-media",
            action="store_true",
            help="Skip generated SVG profile, cover, portfolio, and banner media files.",
        )

    def handle(self, *args, **options):
        if not options["confirm_production"]:
            raise CommandError("استخدم --confirm-production لتأكيد إنشاء بيانات ظاهرة في بيئة الإنتاج.")

        days = max(7, min(int(options["days"] or 60), 365))
        with transaction.atomic():
            _disconnect_review_signals()
            try:
                if options["reset_generated"] or options["delete_only"]:
                    deleted = self._delete_generated_rows()
                    self.stdout.write(f"Deleted generated rows: {deleted}")
                    if options["delete_only"]:
                        return

                clients = self._ensure_clients()
                providers = []
                for index, seed in enumerate(PROVIDER_SEEDS, start=1):
                    provider = self._upsert_provider(index, seed, create_media=not options["no_media"])
                    self._upsert_social_proof(provider, clients, index)
                    self._upsert_promo(provider, seed, index, days=days, create_media=not options["no_media"])
                    providers.append(provider)
                    self.stdout.write(f"{index:02d}. {provider.display_name} - {seed.category} / {seed.subcategory}")
            finally:
                _reconnect_review_signals()

        self.stdout.write(self.style.SUCCESS(f"Seeded {len(PROVIDER_SEEDS)} production-like providers successfully."))

    def _delete_generated_rows(self) -> dict[str, int]:
        provider_users = User.objects.filter(username__startswith=f"{SEED_PREFIX}.provider.")
        client_users = User.objects.filter(username__startswith=f"{SEED_PREFIX}.client.")
        promo_requests = PromoRequest.objects.filter(title__startswith=f"[{SEED_PREFIX}]")
        home_banners = HomeBanner.objects.filter(title__startswith=f"[{SEED_PREFIX}]")

        counts = {
            "promo_requests": promo_requests.count(),
            "home_banners": home_banners.count(),
            "provider_users": provider_users.count(),
            "client_users": client_users.count(),
        }
        promo_requests.delete()
        home_banners.delete()
        provider_users.delete()
        client_users.delete()
        return counts

    def _ensure_clients(self) -> list[User]:
        clients = []
        for index, (first_name, last_name) in enumerate(CLIENT_NAMES, start=1):
            phone = f"{CLIENT_PHONE_BASE}{index:04d}"
            user, _ = User.objects.update_or_create(
                phone=phone,
                defaults={
                    "username": f"{SEED_PREFIX}.client.{index:02d}",
                    "first_name": first_name,
                    "last_name": last_name,
                    "city": "الرياض",
                    "role_state": UserRole.CLIENT,
                    "is_active": True,
                    "terms_accepted_at": timezone.now(),
                },
            )
            clients.append(user)
        return clients

    def _upsert_provider(self, index: int, seed: ProviderSeed, *, create_media: bool) -> ProviderProfile:
        category, _ = Category.objects.update_or_create(name=seed.category, defaults={"is_active": True})
        subcategory, _ = SubCategory.objects.update_or_create(
            category=category,
            name=seed.subcategory,
            defaults={"is_active": True},
        )
        region, _ = SaudiRegion.objects.update_or_create(name_ar=seed.region, defaults={"is_active": True, "sort_order": index})
        SaudiCity.objects.update_or_create(
            region=region,
            name_ar=seed.city,
            defaults={"is_active": True, "sort_order": index},
        )

        phone = f"{PROVIDER_PHONE_BASE}{index:04d}"
        user, _ = User.objects.update_or_create(
            phone=phone,
            defaults={
                "username": f"{SEED_PREFIX}.provider.{index:02d}",
                "first_name": seed.name.split()[0],
                "last_name": "مزود خدمة",
                "city": seed.city,
                "role_state": UserRole.PROVIDER,
                "is_active": True,
                "terms_accepted_at": timezone.now(),
            },
        )

        slug = slugify(seed.name, allow_unicode=True) or f"{SEED_PREFIX}-{index:02d}"
        profile, _ = ProviderProfile.objects.update_or_create(
            user=user,
            defaults={
                "provider_type": seed.provider_type,
                "display_name": seed.name,
                "bio": _bio_for(seed),
                "about_details": _about_for(seed),
                "years_experience": seed.years,
                "whatsapp": phone,
                "website": f"https://example.com/{slug}",
                "social_links": [
                    {"label": "instagram", "url": f"https://instagram.com/{slug}"},
                    {"label": "x", "url": f"https://x.com/{slug}"},
                ],
                "languages": ["العربية", "الإنجليزية"],
                "region": seed.region,
                "city": seed.city,
                "lat": seed.lat,
                "lng": seed.lng,
                "coverage_radius_km": 25,
                "qualifications": _qualifications_for(seed),
                "experiences": _experiences_for(seed),
                "content_sections": _content_sections_for(seed),
                "seo_title": f"{seed.name} | {seed.subcategory} في {seed.city}",
                "seo_keywords": seed.keywords,
                "seo_meta_description": f"{seed.name} يقدم خدمة {seed.service_title} في {seed.city} بتقييمات عالية وبيانات واضحة.",
                "seo_slug": slug,
                "accepts_urgent": index % 3 != 0,
                "is_verified_blue": index % 2 == 0,
                "is_verified_green": index % 5 == 0,
                "excellence_badges_cache": _badges_for(index, seed),
            },
        )

        if create_media:
            _save_svg_file(profile.profile_image, f"{SEED_PREFIX}/profiles/provider-{index:02d}.svg", _avatar_svg(seed.name, index))
            _save_svg_file(profile.cover_image, f"{SEED_PREFIX}/covers/provider-{index:02d}.svg", _cover_svg(seed, index))
            profile.save(update_fields=["profile_image", "cover_image", "updated_at"])

        relation, _ = ProviderCategory.objects.update_or_create(
            provider=profile,
            subcategory=subcategory,
            defaults={"accepts_urgent": bool(profile.accepts_urgent)},
        )
        sync_provider_accepts_urgent_flag(profile)

        ProviderService.objects.update_or_create(
            provider=profile,
            subcategory=subcategory,
            title=seed.service_title,
            defaults={
                "description": seed.service_description,
                "price_from": seed.price_from,
                "price_to": seed.price_to,
                "price_unit": "starting_from" if seed.price_to else "fixed",
                "is_active": True,
            },
        )

        if create_media:
            portfolio, _ = ProviderPortfolioItem.objects.update_or_create(
                provider=profile,
                caption=f"نموذج من أعمال {seed.name}",
                defaults={"file_type": "image"},
            )
            _save_svg_file(portfolio.file, f"{SEED_PREFIX}/portfolio/provider-{index:02d}.svg", _portfolio_svg(seed, index))
            portfolio.save(update_fields=["file"])

        return profile

    def _upsert_social_proof(self, provider: ProviderProfile, clients: list[User], index: int) -> None:
        selected_clients = clients[index % len(clients):] + clients[: index % len(clients)]
        for offset, client in enumerate(selected_clients[:5], start=1):
            ProviderFollow.objects.get_or_create(user=client, provider=provider, role_context="client")
            if offset <= 4:
                ProviderLike.objects.get_or_create(user=client, provider=provider, role_context="client")

        Review.objects.filter(request__title__startswith=f"[{SEED_PREFIX}] طلب مكتمل", provider=provider).delete()
        subcategory = ProviderCategory.objects.filter(provider=provider).select_related("subcategory").first().subcategory
        for offset, rating in enumerate(PROVIDER_SEEDS[index - 1].rating_values, start=1):
            client = selected_clients[(offset - 1) % len(selected_clients)]
            request, _ = ServiceRequest.objects.update_or_create(
                client=client,
                provider=provider,
                title=f"[{SEED_PREFIX}] طلب مكتمل {provider.id}-{offset}",
                defaults={
                    "subcategory": subcategory,
                    "description": f"طلب سابق لخدمة {subcategory.name} نفذه {provider.display_name}.",
                    "request_type": RequestType.NORMAL,
                    "dispatch_mode": "all",
                    "status": RequestStatus.COMPLETED,
                    "city": provider.city,
                    "request_lat": provider.lat,
                    "request_lng": provider.lng,
                    "is_urgent": False,
                    "expected_delivery_at": timezone.now() - timedelta(days=offset + 3),
                    "delivered_at": timezone.now() - timedelta(days=offset + 1),
                    "actual_service_amount": Decimal("250.00") + Decimal(offset * 35),
                },
            )
            Review.objects.update_or_create(
                request=request,
                defaults={
                    "provider": provider,
                    "client": client,
                    "rating": rating,
                    "response_speed": min(5, rating + (offset % 2)),
                    "cost_value": rating,
                    "quality": rating,
                    "credibility": min(5, rating + 1),
                    "on_time": rating,
                    "comment": REVIEW_COMMENTS[(index + offset) % len(REVIEW_COMMENTS)],
                    "provider_reply": "شكراً لثقتك، سعدنا بخدمتك ونسعد دائماً بأي ملاحظات تطويرية.",
                    "provider_reply_at": timezone.now() - timedelta(days=offset),
                    "moderation_status": ReviewModerationStatus.APPROVED,
                    "moderated_at": timezone.now() - timedelta(days=offset),
                },
            )

        aggregate = Review.objects.filter(provider=provider, moderation_status=ReviewModerationStatus.APPROVED).aggregate(
            rating_avg=Avg("rating"),
            rating_count=Count("id"),
        )
        rating_avg = Decimal(str(aggregate["rating_avg"] or "0")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        ProviderProfile.objects.filter(pk=provider.pk).update(
            rating_avg=rating_avg,
            rating_count=int(aggregate["rating_count"] or 0),
        )
        provider.refresh_from_db(fields=["rating_avg", "rating_count"])

    def _upsert_promo(self, provider: ProviderProfile, seed: ProviderSeed, index: int, *, days: int, create_media: bool) -> None:
        now = timezone.now()
        start_at = now - timedelta(hours=1)
        end_at = now + timedelta(days=days)

        promo, _ = PromoRequest.objects.update_or_create(
            requester=provider.user,
            title=f"[{SEED_PREFIX}] ترويج {provider.display_name}",
            defaults={
                "ad_type": PromoAdType.BUNDLE,
                "start_at": start_at,
                "end_at": end_at,
                "position": PromoPosition.TOP5 if index <= 5 else PromoPosition.TOP10,
                "target_category": seed.category,
                "target_city": seed.city,
                "target_provider": provider,
                "redirect_url": f"/provider/{provider.id}/",
                "status": PromoRequestStatus.ACTIVE,
                "ops_status": PromoOpsStatus.COMPLETED,
                "activated_at": now - timedelta(minutes=index),
                "ops_completed_at": now - timedelta(minutes=index),
                "subtotal": Decimal("0.00"),
                "total_days": days,
            },
        )

        PromoRequestItem.objects.update_or_create(
            request=promo,
            service_type=PromoServiceType.FEATURED_SPECIALISTS,
            target_provider=provider,
            defaults={
                "title": f"مختص مميز: {provider.display_name}",
                "start_at": start_at,
                "end_at": end_at,
                "target_category": seed.category,
                "target_city": seed.city,
                "redirect_url": f"/provider/{provider.id}/",
                "sort_order": index,
                "duration_days": days,
            },
        )
        for scope in (PromoSearchScope.DEFAULT, PromoSearchScope.MAIN_RESULTS, PromoSearchScope.CATEGORY_MATCH):
            PromoRequestItem.objects.update_or_create(
                request=promo,
                service_type=PromoServiceType.SEARCH_RESULTS,
                search_scope=scope,
                target_provider=provider,
                defaults={
                    "title": f"ظهور بحث: {provider.display_name} - {scope}",
                    "start_at": start_at,
                    "end_at": end_at,
                    "search_position": PromoPosition.FIRST if index <= 3 else PromoPosition.TOP5,
                    "target_category": seed.category if scope == PromoSearchScope.CATEGORY_MATCH else "",
                    "target_city": "",
                    "redirect_url": f"/provider/{provider.id}/",
                    "sort_order": index,
                    "duration_days": days,
                },
            )

        if create_media and index <= 5:
            banner, _ = HomeBanner.objects.update_or_create(
                title=f"[{SEED_PREFIX}] بانر {provider.display_name}",
                defaults={
                    "media_type": HomeBannerMediaType.IMAGE,
                    "link_url": f"/provider/{provider.id}/",
                    "provider": provider,
                    "display_order": index,
                    "is_active": True,
                    "start_at": start_at,
                    "end_at": end_at,
                    "created_by": provider.user,
                },
            )
            _save_svg_file(banner.media_file, f"{SEED_PREFIX}/home-banners/provider-{index:02d}.svg", _home_banner_svg(seed, index))
            banner.save(update_fields=["media_file", "updated_at"])


def _disconnect_review_signals() -> None:
    from apps.reviews import signals

    post_save.disconnect(signals.update_provider_rating, sender=Review)
    post_save.disconnect(signals.notify_provider_review_updates, sender=Review)
    post_delete.disconnect(signals.update_provider_rating_on_delete, sender=Review)
    pre_save.disconnect(signals.capture_review_previous_state, sender=Review)


def _reconnect_review_signals() -> None:
    from apps.reviews import signals

    pre_save.connect(signals.capture_review_previous_state, sender=Review)
    post_save.connect(signals.update_provider_rating, sender=Review)
    post_save.connect(signals.notify_provider_review_updates, sender=Review)
    post_delete.connect(signals.update_provider_rating_on_delete, sender=Review)


def _save_svg_file(field, name: str, svg: str) -> None:
    field.save(name, ContentFile(svg.encode("utf-8")), save=False)


def _bio_for(seed: ProviderSeed) -> str:
    return (
        f"{seed.name} يقدم {seed.service_title} في {seed.city} بخبرة {seed.years} سنوات. "
        "العمل يبدأ بتشخيص واضح، عرض سعر مكتوب، وتنفيذ منظم يحترم وقت العميل."
    )[:300]


def _about_for(seed: ProviderSeed) -> str:
    return (
        f"نركز على خدمة {seed.subcategory} بمعايير عملية: زيارة أو استشارة أولية، تحديد نطاق العمل، "
        "تسليم متفق عليه، ومتابعة بعد الخدمة. نخدم الأفراد والمنشآت داخل نطاق المدينة وما حولها."
    )


def _qualifications_for(seed: ProviderSeed) -> list[dict[str, str]]:
    return [
        {"title": f"خبرة {seed.years} سنوات في {seed.subcategory}", "issuer": "مشاريع ميدانية موثقة"},
        {"title": "التزام بمعايير السلامة وجودة الخدمة", "issuer": "سياسات تشغيل داخلية"},
    ]


def _experiences_for(seed: ProviderSeed) -> list[dict[str, str]]:
    return [
        {"title": seed.service_title, "period": f"{seed.years} سنوات", "description": seed.service_description},
        {"title": f"خدمة عملاء في {seed.city}", "period": "مستمرة", "description": "متابعة قبل وبعد التنفيذ وتوضيح الخيارات للعميل."},
    ]


def _content_sections_for(seed: ProviderSeed) -> list[dict[str, str]]:
    return [
        {"title": "آلية العمل", "body": "نبدأ بفهم الاحتياج ثم نحدد نطاق الخدمة والسعر والموعد قبل التنفيذ."},
        {"title": "ما يميزنا", "body": "وضوح في التواصل، التزام بالمواعيد، وتوثيق للخطوات المهمة أثناء الخدمة."},
    ]


def _badges_for(index: int, seed: ProviderSeed) -> list[dict[str, str]]:
    badges = [{"code": "top_rated", "label": "تقييم مرتفع"}]
    if index % 3 == 0:
        badges.append({"code": "fast_response", "label": "استجابة سريعة"})
    if seed.years >= 10:
        badges.append({"code": "experienced", "label": "خبرة موثوقة"})
    return badges


def _avatar_svg(name: str, index: int) -> str:
    initial = name.strip()[0]
    bg, fg = _palette(index)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
<rect width="512" height="512" rx="96" fill="{bg}"/>
<circle cx="256" cy="210" r="86" fill="{fg}" opacity=".92"/>
<path d="M116 438c24-88 92-132 140-132s116 44 140 132" fill="{fg}" opacity=".92"/>
<text x="256" y="282" text-anchor="middle" font-family="Arial" font-size="156" font-weight="700" fill="#fff">{initial}</text>
</svg>"""


def _cover_svg(seed: ProviderSeed, index: int) -> str:
    bg, fg = _palette(index)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="600" viewBox="0 0 1600 600">
<rect width="1600" height="600" fill="{bg}"/>
<path d="M0 420 C320 310 470 520 780 390 C1060 275 1210 250 1600 340 L1600 600 L0 600 Z" fill="{fg}" opacity=".42"/>
<text x="120" y="210" font-family="Arial" font-size="64" font-weight="700" fill="#fff">{seed.name}</text>
<text x="120" y="296" font-family="Arial" font-size="40" fill="#fff">{seed.service_title}</text>
<text x="120" y="366" font-family="Arial" font-size="32" fill="#fff">{seed.city} - خبرة {seed.years} سنوات</text>
</svg>"""


def _portfolio_svg(seed: ProviderSeed, index: int) -> str:
    bg, fg = _palette(index)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="900" viewBox="0 0 1200 900">
<rect width="1200" height="900" fill="#f7f7f2"/>
<rect x="90" y="90" width="1020" height="620" rx="36" fill="{bg}"/>
<rect x="150" y="150" width="360" height="230" rx="24" fill="#ffffff" opacity=".92"/>
<rect x="550" y="150" width="500" height="90" rx="18" fill="#ffffff" opacity=".9"/>
<rect x="550" y="270" width="430" height="60" rx="16" fill="#ffffff" opacity=".72"/>
<rect x="150" y="430" width="900" height="220" rx="24" fill="{fg}" opacity=".55"/>
<text x="120" y="790" font-family="Arial" font-size="46" font-weight="700" fill="#222">{seed.service_title}</text>
<text x="120" y="846" font-family="Arial" font-size="30" fill="#555">{seed.name}</text>
</svg>"""


def _home_banner_svg(seed: ProviderSeed, index: int) -> str:
    bg, fg = _palette(index)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="840" viewBox="0 0 1920 840">
<rect width="1920" height="840" fill="{bg}"/>
<path d="M1020 0 H1920 V840 H780 C900 690 900 510 1040 390 C1190 260 1420 320 1560 160 C1630 80 1730 35 1920 18 V0 Z" fill="{fg}" opacity=".5"/>
<text x="150" y="260" font-family="Arial" font-size="88" font-weight="700" fill="#fff">{seed.name}</text>
<text x="150" y="372" font-family="Arial" font-size="54" fill="#fff">{seed.service_title}</text>
<text x="150" y="470" font-family="Arial" font-size="40" fill="#fff">{seed.city} | تقييمات موثوقة | خدمة جاهزة الآن</text>
</svg>"""


def _palette(index: int) -> tuple[str, str]:
    palettes = (
        ("#1f7a6d", "#ffc857"),
        ("#2f6690", "#f4a261"),
        ("#6a4c93", "#8ac926"),
        ("#3d405b", "#e07a5f"),
        ("#006d77", "#ffd166"),
    )
    return palettes[(index - 1) % len(palettes)]
