import json
from urllib.parse import urlencode

from django.urls import reverse
from django.utils.text import slugify
from django.views.generic import TemplateView
from django.views.generic.base import RedirectView

from apps.providers.models import ProviderProfile


def _clean_meta_text(value, fallback=""):
    return " ".join(str(value or fallback).split()).strip()


def _provider_image_absolute_url(request, provider):
    for field in (getattr(provider, "cover_image", None), getattr(provider, "profile_image", None)):
        if not field:
            continue
        try:
            url = field.url
        except Exception:
            url = ""
        if url:
            return request.build_absolute_uri(url)
    return ""


def _provider_social_urls(provider):
    urls = []
    for item in getattr(provider, "social_links", []) or []:
        if isinstance(item, dict):
            url = str(item.get("url") or item.get("href") or item.get("link") or "").strip()
        else:
            url = str(item or "").strip()
        if not url or url.lower().startswith("mailto:"):
            continue
        if url.startswith("http://") or url.startswith("https://"):
            urls.append(url)
    return list(dict.fromkeys(urls))


def _normalized_provider_slug(value):
    raw = _clean_meta_text(value)
    if not raw:
        return ""
    return slugify(raw, allow_unicode=True).strip("-")


def _provider_canonical_path(provider_id, provider_slug=""):
    if provider_slug:
        return f"/provider/{provider_id}/{provider_slug}/"
    return f"/provider/{provider_id}/"


def _provider_meta_context(request, provider):
    seo_slug = _normalized_provider_slug(getattr(provider, "seo_slug", ""))
    canonical_path = _provider_canonical_path(provider.id, seo_slug)
    canonical_url = request.build_absolute_uri(canonical_path)
    display_name = _clean_meta_text(getattr(provider, "display_name", ""), "مقدم خدمة")
    seo_title = _clean_meta_text(getattr(provider, "seo_title", "")) or display_name
    page_title = f"{seo_title} | نوافــذ"
    description = (
        _clean_meta_text(getattr(provider, "seo_meta_description", ""))
        or _clean_meta_text(getattr(provider, "bio", ""))
        or _clean_meta_text(getattr(provider, "about_details", ""))
        or f"تعرف على خدمات {display_name} عبر منصة نوافــذ."
    )
    keywords = _clean_meta_text(getattr(provider, "seo_keywords", ""))
    image_url = _provider_image_absolute_url(request, provider)
    structured = {
        "@context": "https://schema.org",
        "@type": "ProfessionalService",
        "name": display_name,
        "description": description,
        "url": canonical_url,
    }
    if image_url:
        structured["image"] = image_url
    if getattr(provider, "city", ""):
        structured["areaServed"] = {
            "@type": "City",
            "name": str(provider.city).strip(),
        }
    phone_value = _clean_meta_text(getattr(provider, "whatsapp", "") or getattr(getattr(provider, "user", None), "phone", ""))
    if phone_value:
        structured["telephone"] = phone_value
    same_as = _provider_social_urls(provider)
    if same_as:
        structured["sameAs"] = same_as
    rating_count = int(getattr(provider, "rating_count", 0) or 0)
    if rating_count > 0:
        structured["aggregateRating"] = {
            "@type": "AggregateRating",
            "ratingValue": str(getattr(provider, "rating_avg", "0.00") or "0.00"),
            "ratingCount": rating_count,
        }
    return {
        "page_meta_title": page_title,
        "page_meta_description": description,
        "page_meta_keywords": keywords,
        "page_meta_canonical": canonical_url,
        "page_meta_image": image_url,
        "page_meta_url": canonical_url,
        "page_meta_robots": "index,follow,max-image-preview:large",
        "page_structured_data_json": json.dumps(structured, ensure_ascii=False),
    }


class MobileWebHomeView(TemplateView):
    """
    Serves the mobile-web home page shell.
    All data is fetched client-side via API — no server-side data injection.
    """
    template_name = "mobile_web/home.html"


class MobileWebLoginView(TemplateView):
    template_name = "mobile_web/login.html"


class MobileWebOnboardingView(TemplateView):
    template_name = "mobile_web/onboarding.html"


class MobileWebTwoFAView(TemplateView):
    template_name = "mobile_web/twofa.html"


class MobileWebSignupView(TemplateView):
    template_name = "mobile_web/signup.html"


class MobileWebSearchView(TemplateView):
    template_name = "mobile_web/search.html"


class MobileWebOrdersView(TemplateView):
    template_name = "mobile_web/orders.html"


class MobileWebOrderDetailView(TemplateView):
    template_name = "mobile_web/order_detail.html"


class MobileWebInteractiveView(TemplateView):
    template_name = "mobile_web/interactive.html"


class MobileWebProfileView(TemplateView):
    template_name = "mobile_web/profile.html"


class MobileWebProviderDetailView(TemplateView):
    template_name = "mobile_web/provider_detail.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        provider_id = kwargs.get("provider_id")
        provider = (
            ProviderProfile.objects.select_related("user")
            .filter(pk=provider_id, user__is_active=True)
            .first()
        )
        if not provider:
            return context
        context.update(_provider_meta_context(self.request, provider))
        return context


class MobileWebNotificationsView(TemplateView):
    template_name = "mobile_web/notifications.html"


class MobileWebChatsView(TemplateView):
    template_name = "mobile_web/chats.html"


class MobileWebChatDetailView(TemplateView):
    template_name = "mobile_web/chat_detail.html"


class MobileWebLegacyThreadChatRedirectView(RedirectView):
    permanent = False

    def get_redirect_url(self, *args, **kwargs):
        thread_id = kwargs.get("thread_id")
        target = reverse("chat_detail", kwargs={"thread_id": thread_id})
        query_string = str(self.request.META.get("QUERY_STRING") or "").strip()
        if query_string:
            return f"{target}?{query_string}"
        return target


class MobileWebLegacyRequestChatRedirectView(RedirectView):
    permanent = False

    def get_redirect_url(self, *args, **kwargs):
        request_id = kwargs.get("request_id")
        mode = str(self.request.GET.get("mode") or "").strip().lower()
        if mode == "provider":
            target = reverse("provider_order_detail", kwargs={"request_id": request_id})
        else:
            target = reverse("order_detail", kwargs={"request_id": request_id})
        query_string = str(self.request.META.get("QUERY_STRING") or "").strip()
        if query_string:
            return f"{target}?{query_string}"
        return target


class MobileWebLegacyPromoRequestRedirectView(RedirectView):
    permanent = False

    def get_redirect_url(self, *args, **kwargs):
        request_id = kwargs.get("request_id")
        query = self.request.GET.copy()
        query["request_id"] = str(request_id)
        encoded = query.urlencode()
        target = "/promotion/"
        if encoded:
            return f"{target}?{encoded}"
        return target


class MobileWebAddServiceView(TemplateView):
    template_name = "mobile_web/add_service.html"


class MobileWebUrgentRequestView(TemplateView):
    template_name = "mobile_web/urgent_request.html"


class MobileWebRequestQuoteView(TemplateView):
    template_name = "mobile_web/request_quote.html"


class MobileWebSettingsView(TemplateView):
    template_name = "mobile_web/settings.html"


class MobileWebTermsView(TemplateView):
    template_name = "mobile_web/terms.html"


class MobileWebAboutView(TemplateView):
    template_name = "mobile_web/about.html"


class MobileWebContactView(TemplateView):
    template_name = "mobile_web/contact.html"


class MobileWebLanguageView(TemplateView):
    template_name = "mobile_web/language.html"


class MobileWebMyQrView(TemplateView):
    template_name = "mobile_web/my_qr.html"


class MobileWebNotificationSettingsView(TemplateView):
    template_name = "mobile_web/notification_settings.html"


# ── Missing screens (1:1 parity with Flutter mobile app) ──

class MobileWebProviderDashboardView(TemplateView):
    template_name = "mobile_web/provider_dashboard.html"


class MobileWebProviderOrdersView(TemplateView):
    template_name = "mobile_web/provider_orders.html"


class MobileWebProviderOrderDetailView(TemplateView):
    template_name = "mobile_web/provider_order_detail.html"


class MobileWebPlansView(TemplateView):
    template_name = "mobile_web/plans.html"


class MobileWebPlanSummaryView(TemplateView):
    template_name = "mobile_web/plan_summary.html"


class MobileWebSubscriptionPaymentView(TemplateView):
    template_name = "mobile_web/subscription_payment.html"


class MobileWebVerificationView(TemplateView):
    template_name = "mobile_web/verification.html"


class MobileWebVerificationPaymentView(TemplateView):
    template_name = "mobile_web/verification_payment.html"


class MobileWebServiceDetailView(TemplateView):
    template_name = "mobile_web/service_detail.html"


class MobileWebServiceRequestFormView(TemplateView):
    template_name = "mobile_web/service_request_form.html"


class MobileWebProviderRegisterView(TemplateView):
    template_name = "mobile_web/provider_register.html"


class MobileWebLoginSettingsView(TemplateView):
    template_name = "mobile_web/login_settings.html"


class MobileWebPromotionView(TemplateView):
    template_name = "mobile_web/promotion.html"


class MobileWebPromotionPaymentView(TemplateView):
    template_name = "mobile_web/promotion_payment.html"


class MobileWebPromotionNewRequestView(TemplateView):
    template_name = "mobile_web/promotion_new_request.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        user = getattr(self.request, "user", None)
        provider_name = ""

        if user is not None and getattr(user, "is_authenticated", False):
            provider_profile = getattr(user, "provider_profile", None)
            first_name = str(getattr(user, "first_name", "") or "").strip()
            last_name = str(getattr(user, "last_name", "") or "").strip()
            full_name = " ".join(part for part in [first_name, last_name] if part).strip()

            provider_name = (
                str(getattr(provider_profile, "display_name", "") or "").strip()
                or full_name
                or str(getattr(user, "username", "") or "").strip()
                or str(getattr(user, "phone", "") or "").strip()
            )

        context["promo_provider_display_name"] = provider_name
        return context


class MobileWebAdditionalServicesView(TemplateView):
    template_name = "mobile_web/additional_services.html"


class MobileWebProviderServicesView(TemplateView):
    template_name = "mobile_web/provider_services.html"


class MobileWebProviderReviewsView(TemplateView):
    template_name = "mobile_web/provider_reviews.html"


class MobileWebProviderProfileEditView(TemplateView):
    template_name = "mobile_web/provider_profile_edit.html"


class MobileWebProviderPortfolioView(TemplateView):
    template_name = "mobile_web/provider_portfolio.html"


class MobileWebProfileCompletionView(TemplateView):
    template_name = "mobile_web/profile_completion.html"


class MobileWebProvidersMapView(TemplateView):
    template_name = "mobile_web/providers_map.html"


class MobileWebSearchProvidersView(TemplateView):
    template_name = "mobile_web/search_providers.html"
