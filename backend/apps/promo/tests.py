from datetime import datetime
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import SimpleTestCase, TestCase
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceLineItem
from apps.promo.models import PromoAdType, PromoOpsStatus, PromoRequest, PromoRequestStatus
from apps.providers.models import ProviderProfile
from apps.promo.serializers import PromoRequestDetailSerializer, PromoRequestItemCreateSerializer
from apps.promo.services import (
    _locked_promo_request_queryset,
    calculate_sponsorship_end_at,
    quote_and_create_invoice,
    set_promo_ops_status,
)


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

    def test_locked_request_query_avoids_nullable_invoice_join(self):
        request_obj = self._create_request()

        sql = str(_locked_promo_request_queryset().filter(pk=request_obj.pk).query).upper()

        self.assertNotIn("JOIN", sql)


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