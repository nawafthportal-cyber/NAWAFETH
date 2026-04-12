from datetime import datetime
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db.models import Q
from django.http import HttpResponse
from django.test import RequestFactory, SimpleTestCase, TestCase, override_settings
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.middleware import InlinePromoSchedulerMiddleware
from apps.core.models import PlatformConfig
from apps.billing.models import Invoice, InvoiceLineItem
from apps.promo.models import PromoAdType, PromoOpsStatus, PromoRequest, PromoRequestItem, PromoRequestStatus, PromoServiceType
from apps.providers.models import ProviderProfile
from apps.promo.serializers import PromoRequestCreateSerializer, PromoRequestDetailSerializer, PromoRequestItemCreateSerializer
from apps.promo.services import (
    _locked_promo_request_queryset,
    calculate_sponsorship_end_at,
    cleanup_incomplete_unpaid_promo_requests,
    discard_incomplete_promo_request,
    quote_and_create_invoice,
    set_promo_ops_status,
)
from apps.promo.validators import promo_asset_upload_limit_mb


class PromoPaymentWorkflowTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000001", password="secret")
        self.staff = get_user_model().objects.create_user(
            phone="0500000002",
            password="secret",
            is_staff=True,
        )

    def _create_request(self):
        invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة ترويج",
            reference_type="promo_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("0.00"),
        )
        request_obj = PromoRequest.objects.create(
            requester=self.user,
            title="حملة تجريبية",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=7),
            status=PromoRequestStatus.PENDING_PAYMENT,
            ops_status=PromoOpsStatus.NEW,
            invoice=invoice,
        )
        invoice.reference_id = request_obj.code
        invoice.save(update_fields=["reference_id", "updated_at"])
        return request_obj

    def _mark_invoice_paid(self, request_obj: PromoRequest):
        invoice = request_obj.invoice
        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="promo-test",
            event_id=f"promo-{request_obj.pk}",
            amount=Decimal("100.00"),
            currency="SAR",
        )
        invoice.save()

    def test_paid_request_returns_to_new_without_activation(self):
        request_obj = self._create_request()

        self._mark_invoice_paid(request_obj)
        request_obj.refresh_from_db()

        self.assertEqual(request_obj.status, PromoRequestStatus.NEW)
        self.assertEqual(request_obj.ops_status, PromoOpsStatus.NEW)
        self.assertIsNone(request_obj.activated_at)

    def test_cannot_move_ops_forward_before_payment(self):
        request_obj = self._create_request()

        with self.assertRaisesMessage(ValueError, "لا يمكن بدء أو إكمال تنفيذ طلب الترويج قبل اعتماد الدفع."):
            set_promo_ops_status(
                pr=request_obj,
                new_status=PromoOpsStatus.IN_PROGRESS,
                by_user=self.staff,
            )

    def test_ops_completion_activates_paid_request(self):
        request_obj = self._create_request()
        self._mark_invoice_paid(request_obj)
        request_obj.refresh_from_db()

        request_obj = set_promo_ops_status(
            pr=request_obj,
            new_status=PromoOpsStatus.IN_PROGRESS,
            by_user=self.staff,
        )
        request_obj = set_promo_ops_status(
            pr=request_obj,
            new_status=PromoOpsStatus.COMPLETED,
            by_user=self.staff,
        )
        request_obj.refresh_from_db()

        self.assertEqual(request_obj.status, PromoRequestStatus.ACTIVE)
        self.assertEqual(request_obj.ops_status, PromoOpsStatus.COMPLETED)
        self.assertIsNotNone(request_obj.activated_at)
        self.assertIsNotNone(request_obj.ops_started_at)
        self.assertIsNotNone(request_obj.ops_completed_at)

    def test_provider_status_shows_awaiting_review_after_payment(self):
        request_obj = self._create_request()

        self._mark_invoice_paid(request_obj)
        request_obj.refresh_from_db()
        data = PromoRequestDetailSerializer(request_obj).data

        self.assertEqual(data["status"], PromoRequestStatus.NEW)
        self.assertEqual(data["ops_status"], PromoOpsStatus.NEW)
        self.assertEqual(data["provider_status_code"], "awaiting_review")
        self.assertEqual(data["provider_status_label"], "بانتظار المراجعة")

    def test_provider_status_moves_to_in_progress_before_activation(self):
        request_obj = self._create_request()

        self._mark_invoice_paid(request_obj)
        request_obj.refresh_from_db()
        request_obj = set_promo_ops_status(
            pr=request_obj,
            new_status=PromoOpsStatus.IN_PROGRESS,
            by_user=self.staff,
        )
        data = PromoRequestDetailSerializer(request_obj).data

        self.assertEqual(data["status"], PromoRequestStatus.NEW)
        self.assertEqual(data["ops_status"], PromoOpsStatus.IN_PROGRESS)
        self.assertEqual(data["provider_status_code"], PromoOpsStatus.IN_PROGRESS)
        self.assertEqual(data["provider_status_label"], "تحت المعالجة")

    def test_late_payment_does_not_override_rejected_request(self):
        invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة ترويج",
            reference_type="promo_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("0.00"),
        )
        request_obj = PromoRequest.objects.create(
            requester=self.user,
            title="طلب مرفوض",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() - timezone.timedelta(days=4),
            end_at=timezone.now() - timezone.timedelta(days=1),
            status=PromoRequestStatus.REJECTED,
            ops_status=PromoOpsStatus.NEW,
            invoice=invoice,
            reject_reason="مرفوض إداريًا",
        )
        Invoice.objects.filter(pk=invoice.pk).update(reference_id=request_obj.code)
        invoice.refresh_from_db()

        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="promo-late-payment",
            event_id=f"promo-late-{request_obj.pk}",
            amount=Decimal("100.00"),
            currency="SAR",
        )
        invoice.save()
        request_obj.refresh_from_db()

        self.assertEqual(request_obj.status, PromoRequestStatus.REJECTED)
        self.assertEqual(request_obj.reject_reason, "مرفوض إداريًا")

    def test_unpaid_invoice_save_does_not_reopen_cancelled_request(self):
        invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة ترويج",
            reference_type="promo_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("0.00"),
        )
        request_obj = PromoRequest.objects.create(
            requester=self.user,
            title="طلب ملغي",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=7),
            status=PromoRequestStatus.CANCELLED,
            ops_status=PromoOpsStatus.NEW,
            invoice=invoice,
        )
        Invoice.objects.filter(pk=invoice.pk).update(reference_id=request_obj.code)
        invoice.refresh_from_db()

        invoice.description = "updated"
        invoice.save(update_fields=["description", "updated_at"])
        request_obj.refresh_from_db()

        self.assertEqual(request_obj.status, PromoRequestStatus.CANCELLED)

    def test_locked_request_query_avoids_nullable_invoice_join(self):
        request_obj = self._create_request()

        sql = str(_locked_promo_request_queryset().filter(pk=request_obj.pk).query).upper()

        self.assertNotIn("JOIN", sql)


class PromoIncompleteRequestCleanupTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000061", password="secret")

    def test_discard_incomplete_request_deletes_unpaid_draft(self):
        pr = PromoRequest.objects.create(
            requester=self.user,
            title="مسودة ناقصة",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )

        deleted = discard_incomplete_promo_request(pr=pr, by_user=self.user, reason="test")

        self.assertTrue(deleted)
        self.assertFalse(PromoRequest.objects.filter(pk=pr.pk).exists())

    def test_discard_incomplete_request_keeps_paid_request(self):
        invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة مدفوعة",
            reference_type="promo_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("0.00"),
        )
        pr = PromoRequest.objects.create(
            requester=self.user,
            title="طلب مدفوع بانتظار التنفيذ",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
            invoice=invoice,
        )
        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="keep-paid",
            event_id=f"keep-paid-{pr.pk}",
            amount=Decimal("100.00"),
            currency="SAR",
        )
        invoice.save()

        deleted = discard_incomplete_promo_request(pr=pr, by_user=self.user, reason="should_not_delete")

        self.assertFalse(deleted)
        self.assertTrue(PromoRequest.objects.filter(pk=pr.pk).exists())

    def test_cleanup_incomplete_unpaid_requests_only(self):
        old_unpaid = PromoRequest.objects.create(
            requester=self.user,
            title="قديم غير مدفوع",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )
        PromoRequest.objects.filter(pk=old_unpaid.pk).update(
            created_at=timezone.now() - timezone.timedelta(hours=3)
        )

        paid_invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة مدفوعة",
            reference_type="promo_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("0.00"),
        )
        paid_request = PromoRequest.objects.create(
            requester=self.user,
            title="مدفوع يجب ألا يُحذف",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
            invoice=paid_invoice,
        )
        PromoRequest.objects.filter(pk=paid_request.pk).update(
            created_at=timezone.now() - timezone.timedelta(hours=3)
        )
        paid_invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="paid-keep",
            event_id=f"paid-keep-{paid_request.pk}",
            amount=Decimal("100.00"),
            currency="SAR",
        )
        paid_invoice.save()

        removed = cleanup_incomplete_unpaid_promo_requests(
            now=timezone.now(),
            max_age_minutes=30,
            limit=50,
        )

        self.assertEqual(removed, 1)
        self.assertFalse(PromoRequest.objects.filter(pk=old_unpaid.pk).exists())
        self.assertTrue(PromoRequest.objects.filter(pk=paid_request.pk).exists())


class PromoRequestsListVisibilityTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000171", password="secret")
        ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود قائمة",
            bio="bio",
            city="الرياض",
        )
        refresh = RefreshToken.for_user(self.user)
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {refresh.access_token}"

    def _list_rows(self):
        response = self.client.get("/api/promo/requests/my/", HTTP_HOST="127.0.0.1")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        if isinstance(payload, dict) and isinstance(payload.get("results"), list):
            return payload["results"]
        if isinstance(payload, list):
            return payload
        return []

    def test_my_requests_hides_unpaid_new_drafts_without_invoice(self):
        now = timezone.now()
        hidden = PromoRequest.objects.create(
            requester=self.user,
            title="draft-hidden",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=now + timezone.timedelta(days=1),
            end_at=now + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )
        visible_invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة مرئية",
            reference_type="promo_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("0.00"),
        )
        visible = PromoRequest.objects.create(
            requester=self.user,
            title="pending-visible",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=now + timezone.timedelta(days=1),
            end_at=now + timezone.timedelta(days=2),
            status=PromoRequestStatus.PENDING_PAYMENT,
            ops_status=PromoOpsStatus.NEW,
            invoice=visible_invoice,
        )

        rows = self._list_rows()
        ids = {int(row.get("id")) for row in rows if row.get("id")}
        self.assertNotIn(hidden.id, ids)
        self.assertIn(visible.id, ids)


class PromoFailedInvoiceAutoDiscardTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000172", password="secret")
        ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود فشل دفع",
            bio="bio",
            city="الرياض",
        )

    def test_failed_invoice_discards_incomplete_promo_request(self):
        now = timezone.now()
        invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة ترويج",
            reference_type="promo_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("0.00"),
        )
        pr = PromoRequest.objects.create(
            requester=self.user,
            title="طلب بانتظار الدفع",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=now + timezone.timedelta(days=1),
            end_at=now + timezone.timedelta(days=2),
            status=PromoRequestStatus.PENDING_PAYMENT,
            ops_status=PromoOpsStatus.NEW,
            invoice=invoice,
        )

        invoice.status = "failed"
        invoice.save(update_fields=["status", "updated_at"])

        self.assertFalse(PromoRequest.objects.filter(pk=pr.pk).exists())
        self.assertFalse(Invoice.objects.filter(pk=invoice.pk).exists())


class PromoAssetUploadLimitConfigTests(TestCase):
    def setUp(self):
        cache.clear()
        self.cfg = PlatformConfig.load()
        self.cfg.promo_asset_image_max_file_size_mb = 5
        self.cfg.promo_asset_video_max_file_size_mb = 15
        self.cfg.promo_asset_pdf_max_file_size_mb = 7
        self.cfg.promo_asset_other_max_file_size_mb = 3
        self.cfg.promo_home_banner_image_max_file_size_mb = 8
        self.cfg.promo_home_banner_video_max_file_size_mb = 22
        self.cfg.save()

    def test_validator_reads_per_asset_limits_from_platform_config(self):
        self.assertEqual(
            promo_asset_upload_limit_mb(asset_type="image", requires_home_banner_dims=False),
            5,
        )
        self.assertEqual(
            promo_asset_upload_limit_mb(asset_type="video", requires_home_banner_dims=False),
            15,
        )
        self.assertEqual(
            promo_asset_upload_limit_mb(asset_type="pdf", requires_home_banner_dims=False),
            7,
        )
        self.assertEqual(
            promo_asset_upload_limit_mb(asset_type="other", requires_home_banner_dims=False),
            3,
        )
        self.assertEqual(
            promo_asset_upload_limit_mb(asset_type="image", requires_home_banner_dims=True),
            8,
        )
        self.assertEqual(
            promo_asset_upload_limit_mb(asset_type="video", requires_home_banner_dims=True),
            22,
        )

    def test_pricing_guide_exposes_upload_limits_payload(self):
        response = self.client.get("/api/promo/pricing/guide/")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["asset_upload_limits_mb"]["image"], 5)
        self.assertEqual(payload["asset_upload_limits_mb"]["video"], 15)
        self.assertEqual(payload["asset_upload_limits_mb"]["pdf"], 7)
        self.assertEqual(payload["asset_upload_limits_mb"]["other"], 3)
        self.assertEqual(payload["asset_upload_limits_mb"]["home_banner_image"], 8)
        self.assertEqual(payload["asset_upload_limits_mb"]["home_banner_video"], 22)


class PromoAssetLegacyMultipartGuardTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000191", password="secret")
        ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود اختبار",
            bio="bio",
            city="الرياض",
        )
        refresh = RefreshToken.for_user(self.user)
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {refresh.access_token}"
        now = timezone.now()
        self.request_obj = PromoRequest.objects.create(
            requester=self.user,
            title="طلب رفع فيديو",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=now + timezone.timedelta(days=1),
            end_at=now + timezone.timedelta(days=3),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )
        self.item = PromoRequestItem.objects.create(
            request=self.request_obj,
            service_type=PromoServiceType.HOME_BANNER,
            start_at=self.request_obj.start_at,
            end_at=self.request_obj.end_at,
            title="بنر رئيسي",
        )

    def test_legacy_multipart_upload_rejects_video_files(self):
        video_file = SimpleUploadedFile(
            "promo-video.mp4",
            b"fake-video-content",
            content_type="video/mp4",
        )

        response = self.client.post(
            f"/api/promo/requests/{self.request_obj.id}/assets/",
            data={
                "asset_type": "video",
                "item_id": str(self.item.id),
                "title": "اختبار فيديو",
                "file": video_file,
            },
            HTTP_HOST="127.0.0.1",
        )

        self.assertEqual(response.status_code, 400)
        payload = response.json()
        self.assertEqual(payload.get("error_code"), "direct_upload_required_for_video")
        self.assertIn("الرفع المباشر", str(payload.get("detail", "")))
        self.assertFalse(self.request_obj.assets.exists())


class PromoLegacyWebRedirectTests(SimpleTestCase):
    def test_legacy_promo_request_url_redirects_to_promotion_page(self):
        response = self.client.get("/promo/requests/24/?mode=provider")

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "/promotion/?mode=provider&request_id=24")


class PromoSponsorshipScheduleTests(SimpleTestCase):
    def test_calculate_sponsorship_end_at_clamps_to_last_day_of_target_month(self):
        start_at = timezone.make_aware(datetime(2026, 1, 31, 9, 30))

        end_at = calculate_sponsorship_end_at(start_at=start_at, months=1)

        self.assertEqual(end_at, timezone.make_aware(datetime(2026, 2, 28, 9, 30)))

    def test_sponsorship_item_serializer_auto_populates_end_at_from_months(self):
        start_at = timezone.now() + timezone.timedelta(days=2)
        serializer = PromoRequestItemCreateSerializer(
            data={
                "service_type": "sponsorship",
                "title": "رعاية شهرية",
                "start_at": start_at.isoformat(),
                "sponsor_name": "شركة تجريبية",
                "message_body": "رسالة الرعاية",
                "sponsorship_months": 2,
                "asset_count": 1,
            }
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(
            serializer.validated_data["end_at"],
            calculate_sponsorship_end_at(start_at=serializer.validated_data["start_at"], months=2),
        )


class PromoRequestTitleInputRemovalTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000090", password="secret")
        self.request_factory = RequestFactory()

    def test_bundle_create_serializer_ignores_client_request_title(self):
        request = self.request_factory.post("/api/promo/requests/create/")
        request.user = self.user
        start_at = timezone.now() + timezone.timedelta(days=1)
        end_at = start_at + timezone.timedelta(days=1)

        serializer = PromoRequestCreateSerializer(
            data={
                "title": "عنوان من العميل يجب تجاهله",
                "items": [
                    {
                        "service_type": "home_banner",
                        "start_at": start_at.isoformat(),
                        "end_at": end_at.isoformat(),
                        "asset_count": 1,
                    }
                ],
            },
            context={"request": request},
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)
        request_obj = serializer.save()

        self.assertNotEqual(request_obj.title, "عنوان من العميل يجب تجاهله")
        self.assertEqual(request_obj.title, "بنر الصفحة الرئيسية")


class PromoInvoiceLineItemCodeTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000003", password="secret")
        self.staff = get_user_model().objects.create_user(
            phone="0500000004",
            password="secret",
            is_staff=True,
        )

    def test_quote_and_create_invoice_accepts_long_pricing_rule_codes(self):
        request_obj = PromoRequest.objects.create(
            requester=self.user,
            title="حملة رسائل دعائية",
            ad_type=PromoAdType.BUNDLE,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )
        request_obj.items.create(
            service_type="promo_messages",
            title="الرسائل الدعائية",
            send_at=timezone.now() + timezone.timedelta(days=1, minutes=5),
            use_notification_channel=True,
            use_chat_channel=True,
            message_body="رسالة دعائية تجريبية",
            pricing_rule_code="messages_notification+messages_chat",
            subtotal=Decimal("1600.00"),
            duration_days=1,
        )

        request_obj = quote_and_create_invoice(pr=request_obj, by_user=self.staff, quote_note="")
        line_items = list(InvoiceLineItem.objects.filter(invoice=request_obj.invoice).order_by("sort_order", "id"))

        self.assertGreaterEqual(InvoiceLineItem._meta.get_field("item_code").max_length, 35)
        self.assertEqual(len(line_items), 1)
        self.assertEqual(line_items[0].item_code, "messages_notification+messages_chat")

    def test_quote_and_create_invoice_falls_back_to_service_type_for_legacy_db_limit(self):
        request_obj = PromoRequest.objects.create(
            requester=self.user,
            title="حملة رسائل دعائية",
            ad_type=PromoAdType.BUNDLE,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )
        request_obj.items.create(
            service_type="promo_messages",
            title="الرسائل الدعائية",
            send_at=timezone.now() + timezone.timedelta(days=1, minutes=5),
            use_notification_channel=True,
            use_chat_channel=True,
            message_body="رسالة دعائية تجريبية",
            pricing_rule_code="messages_notification+messages_chat",
            subtotal=Decimal("1600.00"),
            duration_days=1,
        )

        with patch("apps.promo.services._invoice_line_item_code_db_max_length", return_value=20):
            request_obj = quote_and_create_invoice(pr=request_obj, by_user=self.staff, quote_note="")

        line_items = list(InvoiceLineItem.objects.filter(invoice=request_obj.invoice).order_by("sort_order", "id"))

        self.assertEqual(len(line_items), 1)
        self.assertEqual(line_items[0].item_code, "promo_messages")


class PromoRequestProviderDisplayNameTests(TestCase):
    def test_detail_serializer_prefers_requester_provider_display_name(self):
        requester = get_user_model().objects.create_user(phone="0537720207", password="secret")
        ProviderProfile.objects.create(
            user=requester,
            provider_type="individual",
            display_name="اسم مزود الخدمة الصحيح",
            bio="نبذة مختصرة",
        )
        request_obj = PromoRequest.objects.create(
            requester=requester,
            title="طلب ترويج لاختبار الاسم",
            ad_type=PromoAdType.BUNDLE,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )

        data = PromoRequestDetailSerializer(request_obj).data

        self.assertEqual(data["provider_display_name"], "اسم مزود الخدمة الصحيح")


class PromoMessageEndToEndTests(TestCase):
    """
    End-to-end test for the promotional messages (الرسائل الدعائية) flow:
      1. Provider creates a BUNDLE request containing a PROMO_MESSAGES item
      2. Backoffice quotes and generates invoice
      3. Invoice is paid → request resets to NEW (awaiting ops)
      4. Ops moves status to IN_PROGRESS → COMPLETED → request activates
      5. Scheduled dispatch sends messages to eligible recipients
      6. Expiry marks the request as EXPIRED after its window ends
    """

    def setUp(self):
        User = get_user_model()
        from apps.providers.models import Category, SubCategory, ProviderCategory

        # --- sender (the provider submitting the promo request) ---
        self.sender = User.objects.create_user(
            phone="0511110001", password="secret",
            role_state="provider", is_active=True,
        )
        self.sender_profile = ProviderProfile.objects.create(
            user=self.sender,
            provider_type="individual",
            display_name="مختص الترويج",
            bio="مقدم خدمة",
            city="الرياض",
        )

        # --- staff operator ---
        self.staff = User.objects.create_user(
            phone="0511110002", password="secret",
            is_staff=True, is_active=True,
        )

        # --- recipient providers ---
        self.cat = Category.objects.create(name="كهرباء", is_active=True)
        self.subcat = SubCategory.objects.create(category=self.cat, name="تمديدات", is_active=True)

        self.recipient_a = User.objects.create_user(
            phone="0511110003", password="secret",
            role_state="provider", is_active=True,
        )
        self.recipient_a_profile = ProviderProfile.objects.create(
            user=self.recipient_a,
            provider_type="individual",
            display_name="مستلم أ",
            bio="مقدم خدمة",
            city="الرياض",
        )
        ProviderCategory.objects.create(
            provider=self.recipient_a_profile, subcategory=self.subcat,
        )

        self.recipient_b = User.objects.create_user(
            phone="0511110004", password="secret",
            role_state="provider", is_active=True,
        )
        self.recipient_b_profile = ProviderProfile.objects.create(
            user=self.recipient_b,
            provider_type="individual",
            display_name="مستلم ب",
            bio="مقدم خدمة",
            city="الرياض",
        )
        ProviderCategory.objects.create(
            provider=self.recipient_b_profile, subcategory=self.subcat,
        )

        # non-matching recipient (different city)
        self.recipient_other_city = User.objects.create_user(
            phone="0511110005", password="secret",
            role_state="provider", is_active=True,
        )
        ProviderProfile.objects.create(
            user=self.recipient_other_city,
            provider_type="individual",
            display_name="مستلم مدينة أخرى",
            bio="...",
            city="جدة",
        )

    # ------------------------------------------------------------------
    # STEP 1 – Create promo request with PROMO_MESSAGES item
    # ------------------------------------------------------------------
    def _create_promo_message_request(self):
        from apps.promo.models import PromoRequestItem, PromoServiceType
        now = timezone.now()
        send_at = now + timezone.timedelta(hours=6)
        end_at = now + timezone.timedelta(days=3)

        pr = PromoRequest.objects.create(
            requester=self.sender,
            title="طلب ترويج متعدد الخدمات",
            ad_type=PromoAdType.BUNDLE,
            start_at=send_at,
            end_at=end_at,
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )
        item = PromoRequestItem.objects.create(
            request=pr,
            service_type=PromoServiceType.PROMO_MESSAGES,
            title="رسالة دعائية لأهل الرياض",
            send_at=send_at,
            target_city="الرياض",
            target_category="كهرباء",
            use_notification_channel=True,
            use_chat_channel=True,
            message_title="عرض خاص",
            message_body="خصم 30% على جميع الخدمات",
        )
        return pr, item

    # ------------------------------------------------------------------
    # STEP 2+3 – Quote → Pay → Verify status transitions
    # ------------------------------------------------------------------
    def _quote_and_pay(self, pr):
        pr = quote_and_create_invoice(pr=pr, by_user=self.staff, quote_note="تسعير مباشر")
        self.assertEqual(pr.status, PromoRequestStatus.PENDING_PAYMENT)
        self.assertIsNotNone(pr.invoice)
        self.assertTrue(pr.invoice.total > 0)

        # Verify invoice line items match the promo items
        lines = list(pr.invoice.lines.all().order_by("sort_order"))
        self.assertEqual(len(lines), 1)
        self.assertIn("messages", lines[0].item_code)

        # Simulate payment
        pr.invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="promo-e2e",
            event_id=f"promo-e2e-{pr.pk}",
            amount=pr.invoice.total,
            currency="SAR",
        )
        pr.invoice.save()
        pr.refresh_from_db()

        # After payment, request resets to NEW (awaiting ops review)
        self.assertEqual(pr.status, PromoRequestStatus.NEW)
        self.assertIsNone(pr.activated_at)
        return pr

    # ------------------------------------------------------------------
    # STEP 4 – Ops completes → request activates
    # ------------------------------------------------------------------
    def _ops_complete(self, pr):
        pr = set_promo_ops_status(
            pr=pr, new_status=PromoOpsStatus.IN_PROGRESS, by_user=self.staff,
        )
        self.assertEqual(pr.ops_status, PromoOpsStatus.IN_PROGRESS)
        self.assertIsNotNone(pr.ops_started_at)

        pr = set_promo_ops_status(
            pr=pr, new_status=PromoOpsStatus.COMPLETED, by_user=self.staff,
        )
        pr.refresh_from_db()
        self.assertEqual(pr.status, PromoRequestStatus.ACTIVE)
        self.assertEqual(pr.ops_status, PromoOpsStatus.COMPLETED)
        self.assertIsNotNone(pr.activated_at)
        self.assertIsNotNone(pr.ops_completed_at)
        return pr

    # ------------------------------------------------------------------
    # STEP 5 – Scheduled dispatch sends messages
    # ------------------------------------------------------------------
    def _dispatch_messages(self, pr, item):
        from apps.promo.services import dispatch_promo_message_item
        from apps.messaging.models import Thread

        # Dispatch at the scheduled send_at time
        dispatch_time = item.send_at
        count = dispatch_promo_message_item(item=item, now=dispatch_time)

        item.refresh_from_db()
        self.assertIsNotNone(item.message_sent_at)
        self.assertEqual(item.message_dispatch_error, "")

        # Only الرياض providers in كهرباء category should receive
        # (recipient_a and recipient_b match; sender and other_city don't)
        self.assertEqual(count, 2)
        self.assertEqual(item.message_recipients_count, 2)

        # Verify notification channel messages created
        from apps.notifications.models import Notification
        notif_a = Notification.objects.filter(user=self.recipient_a, kind="promo_offer")
        notif_b = Notification.objects.filter(user=self.recipient_b, kind="promo_offer")
        self.assertTrue(notif_a.exists(), "recipient_a should have a promo notification")
        self.assertTrue(notif_b.exists(), "recipient_b should have a promo notification")
        self.assertEqual(notif_a.first().title, "عرض خاص")
        self.assertIn("خصم 30%", notif_b.first().body)

        # Sender should NOT receive their own promo
        notif_sender = Notification.objects.filter(user=self.sender, kind="promo_offer")
        self.assertFalse(notif_sender.exists(), "sender must not receive own promo")

        # Other-city provider should NOT receive
        notif_other = Notification.objects.filter(user=self.recipient_other_city, kind="promo_offer")
        self.assertFalse(notif_other.exists(), "other-city provider must not receive")

        # Verify chat channel threads created
        threads_a = Thread.objects.filter(
            is_direct=True, is_system_thread=True,
            system_thread_key="promo_messages",
        ).filter(
            Q(participant_1=self.sender, participant_2=self.recipient_a) |
            Q(participant_1=self.recipient_a, participant_2=self.sender)
        )
        self.assertTrue(threads_a.exists(), "chat thread for recipient_a should exist")

        thread_a = threads_a.first()
        messages_a = thread_a.messages.all()
        self.assertTrue(messages_a.exists(), "chat messages for recipient_a should exist")
        body_messages = [m for m in messages_a if m.body == "خصم 30% على جميع الخدمات"]
        self.assertEqual(len(body_messages), 1, "exactly one body message per recipient thread")

        return count

    # ------------------------------------------------------------------
    # STEP 6 – Expiry
    # ------------------------------------------------------------------
    def _expire(self, pr):
        from apps.promo.services import expire_due_promos
        expired = expire_due_promos(now=pr.end_at + timezone.timedelta(seconds=1))
        self.assertGreaterEqual(expired, 1)
        pr.refresh_from_db()
        self.assertEqual(pr.status, PromoRequestStatus.EXPIRED)

    # ------------------------------------------------------------------
    # FULL E2E TEST
    # ------------------------------------------------------------------
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_promo_message_full_lifecycle(self, mock_sync, mock_ops_notif, mock_status_notif, mock_notif_pref):
        """
        Full lifecycle: create → quote → pay → ops → dispatch → expire
        """
        # Step 1: Create
        pr, item = self._create_promo_message_request()
        self.assertTrue(pr.code.startswith("MD"))
        self.assertEqual(item.service_type, "promo_messages")

        # Step 2+3: Quote & Pay
        pr = self._quote_and_pay(pr)

        # Step 4: Ops completes → activates
        pr = self._ops_complete(pr)

        # Step 5: Dispatch messages
        self._dispatch_messages(pr, item)

        # Step 6: Expire
        self._expire(pr)

        # Verify status notification was called for key transitions
        status_calls = [call.kwargs.get("status") or call[1].get("status", "") for call in mock_status_notif.call_args_list]
        self.assertIn(PromoRequestStatus.PENDING_PAYMENT, status_calls)
        self.assertIn(PromoRequestStatus.ACTIVE, status_calls)
        self.assertIn(PromoRequestStatus.EXPIRED, status_calls)
        # Ops completed notification
        self.assertTrue(mock_ops_notif.called)

    # ------------------------------------------------------------------
    # Dispatch idempotency: second run should be a no-op
    # ------------------------------------------------------------------
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_dispatch_is_idempotent(self, mock_sync, mock_ops_notif, mock_status_notif, mock_notif_pref):
        from apps.promo.services import dispatch_promo_message_item

        pr, item = self._create_promo_message_request()
        pr = self._quote_and_pay(pr)
        pr = self._ops_complete(pr)

        # First dispatch
        count1 = dispatch_promo_message_item(item=item, now=item.send_at)
        self.assertEqual(count1, 2)

        # Second dispatch should return previous count (already sent)
        count2 = dispatch_promo_message_item(item=item, now=item.send_at)
        self.assertEqual(count2, 2)

        # Verify only 2 notifications total (not 4)
        from apps.notifications.models import Notification
        total_promo_notifs = Notification.objects.filter(kind="promo_offer").count()
        self.assertEqual(total_promo_notifs, 2)

    # ------------------------------------------------------------------
    # Cannot dispatch before activation
    # ------------------------------------------------------------------
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_dispatch_fails_when_request_not_active(self, mock_sync, mock_status_notif, mock_notif_pref):
        from apps.promo.services import dispatch_promo_message_item

        pr, item = self._create_promo_message_request()
        # Request is still NEW, not ACTIVE
        with self.assertRaises(ValueError):
            dispatch_promo_message_item(item=item, now=item.send_at)

    # ------------------------------------------------------------------
    # Cannot dispatch after request window expired
    # ------------------------------------------------------------------
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_dispatch_returns_zero_after_window_expires(self, mock_sync, mock_ops_notif, mock_status_notif, mock_notif_pref):
        from apps.promo.services import dispatch_promo_message_item

        pr, item = self._create_promo_message_request()
        pr = self._quote_and_pay(pr)
        pr = self._ops_complete(pr)

        # Dispatch AFTER the campaign window ends
        after_end = pr.end_at + timezone.timedelta(days=1)
        count = dispatch_promo_message_item(item=item, now=after_end)
        self.assertEqual(count, 0)
        item.refresh_from_db()
        self.assertIsNone(item.message_sent_at)

    # ------------------------------------------------------------------
    # send_due_promo_messages picks up due items
    # ------------------------------------------------------------------
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_send_due_promo_messages_processes_due_items(self, mock_sync, mock_ops_notif, mock_status_notif, mock_notif_pref):
        from apps.promo.services import send_due_promo_messages

        pr, item = self._create_promo_message_request()
        pr = self._quote_and_pay(pr)
        pr = self._ops_complete(pr)

        # Run scheduler at send_at time
        processed = send_due_promo_messages(now=item.send_at)
        self.assertEqual(processed, 1)

        item.refresh_from_db()
        self.assertIsNotNone(item.message_sent_at)
        self.assertEqual(item.message_recipients_count, 2)

    # ------------------------------------------------------------------
    # send_due does NOT pick up items scheduled in the future
    # ------------------------------------------------------------------
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_send_due_skips_future_items(self, mock_sync, mock_ops_notif, mock_status_notif, mock_notif_pref):
        from apps.promo.services import send_due_promo_messages

        pr, item = self._create_promo_message_request()
        pr = self._quote_and_pay(pr)
        pr = self._ops_complete(pr)

        # Run scheduler BEFORE send_at
        before_send = item.send_at - timezone.timedelta(hours=1)
        processed = send_due_promo_messages(now=before_send)
        self.assertEqual(processed, 0)

        item.refresh_from_db()
        self.assertIsNone(item.message_sent_at)

    # ------------------------------------------------------------------
    # Pricing: notification + chat = combined cost
    # ------------------------------------------------------------------
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_promo_messages_pricing_both_channels(self, mock_sync, mock_status_notif):
        from apps.promo.models import PromoRequestItem, PromoServiceType
        from apps.promo.services import calc_promo_item_quote, ensure_default_pricing_rules

        ensure_default_pricing_rules()

        pr = PromoRequest.objects.create(
            requester=self.sender,
            title="test",
            ad_type=PromoAdType.BUNDLE,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=2),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )
        item = PromoRequestItem.objects.create(
            request=pr,
            service_type=PromoServiceType.PROMO_MESSAGES,
            send_at=timezone.now() + timezone.timedelta(days=1, hours=1),
            use_notification_channel=True,
            use_chat_channel=True,
            message_body="test",
        )
        quote = calc_promo_item_quote(item=item)
        # Default: notification=900 + chat=700 = 1600
        self.assertEqual(quote["subtotal"], Decimal("1600.00"))
        self.assertIn("messages_notification", quote.get("rule_code", ""))
        self.assertIn("messages_chat", quote.get("rule_code", ""))

    # ------------------------------------------------------------------
    # Recipient filtering: city only, category only
    # ------------------------------------------------------------------
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_recipients_filtered_by_city_only(self, mock_sync, mock_ops_notif, mock_status_notif, mock_notif_pref):
        """When target_city is set but target_category is empty, all providers in the city receive."""
        from apps.promo.models import PromoRequestItem, PromoServiceType
        from apps.promo.services import dispatch_promo_message_item

        now = timezone.now()
        pr = PromoRequest.objects.create(
            requester=self.sender,
            title="city-only",
            ad_type=PromoAdType.BUNDLE,
            start_at=now + timezone.timedelta(hours=1),
            end_at=now + timezone.timedelta(days=3),
            status=PromoRequestStatus.ACTIVE,
            activated_at=now,
            ops_status=PromoOpsStatus.COMPLETED,
        )
        pr.invoice = Invoice.objects.create(
            user=self.sender, title="inv", subtotal=Decimal("900"),
            reference_type="promo_request", reference_id=pr.code,
            vat_percent=Decimal("0"),
        )
        pr.invoice.mark_payment_confirmed(
            provider="m", provider_reference="r", event_id="e",
            amount=Decimal("900"), currency="SAR",
        )
        pr.invoice.save()
        pr.save(update_fields=["invoice"])

        item = PromoRequestItem.objects.create(
            request=pr,
            service_type=PromoServiceType.PROMO_MESSAGES,
            title="city only test",
            send_at=now + timezone.timedelta(hours=2),
            target_city="الرياض",
            target_category="",  # no category filter
            use_notification_channel=True,
            use_chat_channel=False,
            message_title="عرض",
            message_body="رسالة لأهل الرياض فقط",
        )

        count = dispatch_promo_message_item(item=item, now=item.send_at)
        # recipient_a (الرياض) and recipient_b (الرياض) = 2
        self.assertEqual(count, 2)

    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_recipients_include_clients_with_client_audience_mode(self, mock_sync, mock_ops_notif, mock_status_notif, mock_notif_pref):
        from apps.accounts.models import UserRole
        from apps.notifications.models import Notification
        from apps.promo.models import PromoRequestItem, PromoServiceType
        from apps.promo.services import dispatch_promo_message_item

        client_in_city = get_user_model().objects.create_user(
            phone="0511110088",
            password="secret",
            role_state=UserRole.CLIENT,
            city="الرياض",
            is_active=True,
        )
        client_other_city = get_user_model().objects.create_user(
            phone="0511110089",
            password="secret",
            role_state=UserRole.CLIENT,
            city="جدة",
            is_active=True,
        )

        now = timezone.now()
        pr = PromoRequest.objects.create(
            requester=self.sender,
            title="client-targeting",
            ad_type=PromoAdType.BUNDLE,
            start_at=now + timezone.timedelta(hours=1),
            end_at=now + timezone.timedelta(days=2),
            status=PromoRequestStatus.ACTIVE,
            activated_at=now,
            ops_status=PromoOpsStatus.COMPLETED,
        )
        item = PromoRequestItem.objects.create(
            request=pr,
            service_type=PromoServiceType.PROMO_MESSAGES,
            title="رسالة للجميع",
            send_at=now + timezone.timedelta(hours=2),
            target_city="الرياض",
            target_category="كهرباء",
            use_notification_channel=True,
            use_chat_channel=False,
            message_title="عرض شامل",
            message_body="رسالة دعائية تصل للعملاء والمزودين",
        )

        count = dispatch_promo_message_item(item=item, now=item.send_at)
        # recipient_a + recipient_b + client_in_city
        self.assertEqual(count, 3)
        self.assertTrue(Notification.objects.filter(user=client_in_city, kind="promo_offer", audience_mode="client").exists())
        self.assertFalse(Notification.objects.filter(user=client_other_city, kind="promo_offer").exists())

class InlinePromoSchedulerMiddlewareTests(PromoMessageEndToEndTests):
    def setUp(self):
        super().setUp()
        cache.clear()

    @override_settings(
        PROMO_INLINE_SCHEDULER_ENABLED=True,
        PROMO_INLINE_SCHEDULER_INTERVAL_SECONDS=60,
    )
    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_inline_scheduler_dispatches_due_messages(
        self,
        mock_sync,
        mock_ops_notif,
        mock_status_notif,
        mock_notif_pref,
    ):
        pr, item = self._create_promo_message_request()
        pr = self._quote_and_pay(pr)
        pr = self._ops_complete(pr)

        due_at = timezone.now() - timezone.timedelta(minutes=1)
        item.send_at = due_at
        item.save(update_fields=["send_at", "updated_at"])

        middleware = InlinePromoSchedulerMiddleware(lambda request: HttpResponse("ok"))
        response = middleware(RequestFactory().get("/promotion/"))

        self.assertEqual(response.status_code, 200)
        item.refresh_from_db()
        self.assertIsNotNone(item.message_sent_at)
        self.assertEqual(item.message_recipients_count, 2)

    # ------------------------------------------------------------------
    # Serializer validation for PROMO_MESSAGES items
    # ------------------------------------------------------------------
    def test_promo_message_item_requires_send_at(self):
        serializer = PromoRequestItemCreateSerializer(data={
            "service_type": "promo_messages",
            "use_notification_channel": True,
            "message_body": "test",
        })
        self.assertFalse(serializer.is_valid())

    def test_promo_message_item_requires_channel(self):
        serializer = PromoRequestItemCreateSerializer(data={
            "service_type": "promo_messages",
            "send_at": (timezone.now() + timezone.timedelta(hours=1)).isoformat(),
            "use_notification_channel": False,
            "use_chat_channel": False,
            "message_body": "test",
        })
        self.assertFalse(serializer.is_valid())

    def test_promo_message_item_requires_body_or_asset(self):
        serializer = PromoRequestItemCreateSerializer(data={
            "service_type": "promo_messages",
            "send_at": (timezone.now() + timezone.timedelta(hours=1)).isoformat(),
            "use_notification_channel": True,
            "message_body": "",
            "asset_count": 0,
        })
        self.assertFalse(serializer.is_valid())

    def test_promo_message_item_valid_with_asset_only(self):
        serializer = PromoRequestItemCreateSerializer(data={
            "service_type": "promo_messages",
            "send_at": (timezone.now() + timezone.timedelta(hours=1)).isoformat(),
            "use_notification_channel": True,
            "message_body": "",
            "asset_count": 1,
        })
        self.assertTrue(serializer.is_valid(), serializer.errors)


class PromoScheduledDispatchTests(TestCase):
    """
    Verify that promo messages scheduled during the campaign window
    are dispatched even when ops completion / activation happens after end_at.
    """

    def setUp(self):
        User = get_user_model()
        from apps.providers.models import Category, SubCategory, ProviderCategory

        self.sender = User.objects.create_user(
            phone="0522220001", password="secret",
            role_state="provider", is_active=True,
        )
        self.sender_profile = ProviderProfile.objects.create(
            user=self.sender, provider_type="individual",
            display_name="مرسل مجدول", bio="...", city="الرياض",
        )
        self.staff = User.objects.create_user(
            phone="0522220002", password="secret",
            is_staff=True, is_active=True,
        )
        self.cat = Category.objects.create(name="فئة اختبار", is_active=True)
        self.subcat = SubCategory.objects.create(category=self.cat, name="فرعي", is_active=True)
        self.recipient = User.objects.create_user(
            phone="0522220003", password="secret",
            role_state="provider", is_active=True,
        )
        self.recipient_profile = ProviderProfile.objects.create(
            user=self.recipient, provider_type="individual",
            display_name="مستلم", bio="...", city="الرياض",
        )
        ProviderCategory.objects.create(
            provider=self.recipient_profile, subcategory=self.subcat,
        )

    def _create_paid_promo_request(self, *, send_at, end_at):
        from apps.promo.models import PromoRequestItem, PromoServiceType
        from apps.promo.services import quote_and_create_invoice

        pr = PromoRequest.objects.create(
            requester=self.sender, title="طلب رسائل مجدول",
            ad_type=PromoAdType.BUNDLE,
            start_at=send_at, end_at=end_at,
            status=PromoRequestStatus.NEW, ops_status=PromoOpsStatus.NEW,
        )
        PromoRequestItem.objects.create(
            request=pr, service_type=PromoServiceType.PROMO_MESSAGES,
            title="رسالة مجدولة", send_at=send_at,
            start_at=send_at, end_at=end_at,
            message_body="رسالة اختبار", message_title="اختبار",
            use_notification_channel=True,
            target_city="الرياض", target_category=self.cat.name,
        )
        pr = quote_and_create_invoice(pr=pr, by_user=self.staff)
        pr.invoice.mark_payment_confirmed(
            provider="mock", provider_reference="sched-test",
            event_id=f"sched-test-{pr.pk}", amount=pr.invoice.total, currency="SAR",
        )
        pr.invoice.save()
        return pr

    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_dispatch_on_activation_when_send_time_already_passed(self, _sync, _ops_notif, _status_notif, _should_send):
        """Messages are dispatched inline when ops completes and send_at has passed."""
        from apps.promo.services import apply_effective_payment, set_promo_ops_status
        from apps.notifications.models import Notification

        now = timezone.now()
        send_at = now - timezone.timedelta(hours=1)  # already past
        end_at = now + timezone.timedelta(days=1)     # still in window
        pr = self._create_paid_promo_request(send_at=send_at, end_at=end_at)

        pr = apply_effective_payment(pr=pr)
        self.assertEqual(pr.status, PromoRequestStatus.NEW)

        pr = set_promo_ops_status(pr=pr, new_status=PromoOpsStatus.IN_PROGRESS, by_user=self.staff)
        pr = set_promo_ops_status(pr=pr, new_status=PromoOpsStatus.COMPLETED, by_user=self.staff)
        self.assertEqual(pr.status, PromoRequestStatus.ACTIVE)

        pr.refresh_from_db()
        item = pr.items.first()
        self.assertIsNotNone(item.message_sent_at, "Message should be sent inline on activation")
        self.assertGreater(item.message_recipients_count, 0)
        self.assertTrue(Notification.objects.filter(user=self.recipient, kind="promo_offer").exists())

    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_dispatch_on_activation_when_campaign_already_expired(self, _sync, _ops_notif, _status_notif, _should_send):
        """Messages are dispatched even when payment applied after end_at."""
        from apps.promo.services import apply_effective_payment
        from apps.notifications.models import Notification

        now = timezone.now()
        send_at = now - timezone.timedelta(hours=6)   # long past
        end_at = now - timezone.timedelta(hours=1)     # campaign expired
        pr = self._create_paid_promo_request(send_at=send_at, end_at=end_at)

        # apply_effective_payment sees end_at <= now → should dispatch then expire
        pr = apply_effective_payment(pr=pr)

        pr.refresh_from_db()
        self.assertEqual(pr.status, PromoRequestStatus.EXPIRED)

        item = pr.items.first()
        self.assertIsNotNone(item.message_sent_at, "Message should be sent even when campaign expired")
        self.assertGreater(item.message_recipients_count, 0)
        self.assertTrue(Notification.objects.filter(user=self.recipient, kind="promo_offer").exists())

    @patch("apps.notifications.services.should_send_notification", return_value=True)
    @patch("apps.promo.services._notify_promo_status_change")
    @patch("apps.promo.services._notify_promo_ops_completed")
    @patch("apps.promo.services._sync_promo_to_unified")
    def test_expire_dispatches_unsent_messages_before_expiring(self, _sync, _ops_notif, _status_notif, _should_send):
        """expire_due_promos dispatches unsent messages before marking request as expired."""
        from apps.promo.services import apply_effective_payment, set_promo_ops_status, expire_due_promos
        from apps.notifications.models import Notification

        now = timezone.now()
        send_at = now - timezone.timedelta(minutes=10)
        end_at = now + timezone.timedelta(hours=2)
        pr = self._create_paid_promo_request(send_at=send_at, end_at=end_at)

        pr = apply_effective_payment(pr=pr)
        pr = set_promo_ops_status(pr=pr, new_status=PromoOpsStatus.IN_PROGRESS, by_user=self.staff)
        pr = set_promo_ops_status(pr=pr, new_status=PromoOpsStatus.COMPLETED, by_user=self.staff)
        self.assertEqual(pr.status, PromoRequestStatus.ACTIVE)

        # Simulate message NOT yet dispatched by clearing sent_at
        item = pr.items.first()
        item.message_sent_at = None
        item.message_recipients_count = 0
        item.save(update_fields=["message_sent_at", "message_recipients_count"])

        # Expire with a future time past end_at
        expire_time = end_at + timezone.timedelta(hours=1)
        expire_due_promos(now=expire_time)

        pr.refresh_from_db()
        self.assertEqual(pr.status, PromoRequestStatus.EXPIRED)

        item.refresh_from_db()
        self.assertIsNotNone(item.message_sent_at, "Message should be sent before expiry")
        self.assertTrue(Notification.objects.filter(user=self.recipient, kind="promo_offer").exists())
