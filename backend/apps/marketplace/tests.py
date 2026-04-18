from django.core.exceptions import ValidationError
from django.test import TestCase
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.notifications.models import EventLog, EventType, Notification
from apps.notifications.services import create_notification
from apps.providers.models import Category, ProviderProfile, SubCategory

from .models import PRE_EXECUTION_REQUEST_STATUSES, RequestStatus, RequestType, ServiceRequest
from .serializers import ProviderRequestDetailSerializer
from .services.actions import execute_action
from .services.dispatch import clear_urgent_request_provider_notifications


class ServiceRequestStateTransitionTests(TestCase):
    def setUp(self):
        self.client_user = User.objects.create_user(
            phone="0501000001",
            username="client.test",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = User.objects.create_user(
            phone="0501000002",
            username="provider.test",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود اختبار",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.staff_user = User.objects.create_user(
            phone="0501000003",
            username="staff.test",
            role_state=UserRole.STAFF,
            is_staff=True,
        )
        self.category = Category.objects.create(name="صيانة")
        self.subcategory = SubCategory.objects.create(category=self.category, name="كهرباء")

    def test_stale_accept_fails_after_request_was_cancelled(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب عاجل",
            description="تفاصيل",
            request_type=RequestType.URGENT,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        stale_copy = ServiceRequest.objects.get(pk=service_request.pk)

        service_request.cancel()

        with self.assertRaisesMessage(ValidationError, "لا يمكن قبول الطلب الآن"):
            stale_copy.accept(self.provider)

        service_request.refresh_from_db()
        self.assertEqual(service_request.status, RequestStatus.CANCELLED)
        self.assertIsNone(service_request.provider_id)

    def test_pre_execution_cancel_clears_provider_assignment_and_inputs(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب عاجل",
            description="تفاصيل",
            request_type=RequestType.URGENT,
            status=RequestStatus.PROVIDER_ACCEPTED,
            city="الرياض",
            expected_delivery_at=timezone.now(),
            estimated_service_amount="250.00",
            received_amount="100.00",
            remaining_amount="150.00",
            provider_inputs_approved=False,
            provider_inputs_decided_at=timezone.now(),
            provider_inputs_decision_note="ملاحظة",
        )

        service_request.cancel(allowed_statuses=list(PRE_EXECUTION_REQUEST_STATUSES))

        service_request.refresh_from_db()
        self.assertEqual(service_request.status, RequestStatus.CANCELLED)
        self.assertIsNone(service_request.provider_id)
        self.assertIsNone(service_request.expected_delivery_at)
        self.assertIsNone(service_request.estimated_service_amount)
        self.assertIsNone(service_request.received_amount)
        self.assertIsNone(service_request.remaining_amount)
        self.assertIsNone(service_request.provider_inputs_approved)
        self.assertIsNone(service_request.provider_inputs_decided_at)
        self.assertEqual(service_request.provider_inputs_decision_note, "")

    def test_urgent_cancel_replaces_provider_notification(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب عاجل",
            description="تفاصيل",
            request_type=RequestType.URGENT,
            status=RequestStatus.PROVIDER_ACCEPTED,
            city="الرياض",
        )
        create_notification(
            user=self.provider_user,
            title="طلب خدمة عاجلة جديد",
            body="يوجد طلب عاجل جديد في تخصصك: طلب عاجل",
            kind="urgent_request",
            url=f"/requests/{service_request.id}",
            actor=self.client_user,
            event_type=EventType.REQUEST_CREATED,
            pref_key="urgent_request",
            request_id=service_request.id,
            audience_mode="provider",
            is_urgent=True,
        )

        self.assertEqual(
            Notification.objects.filter(
                user=self.provider_user,
                kind="urgent_request",
                url=f"/requests/{service_request.id}",
            ).count(),
            1,
        )

        with self.captureOnCommitCallbacks(execute=True):
            result = execute_action(
                user=self.client_user,
                request_id=service_request.id,
                action="cancel",
            )

        self.assertTrue(result.ok)
        service_request.refresh_from_db()
        self.assertEqual(service_request.status, RequestStatus.CANCELLED)
        self.assertIsNone(service_request.provider_id)
        self.assertFalse(
            Notification.objects.filter(
                user=self.provider_user,
                kind="urgent_request",
                url=f"/requests/{service_request.id}",
            ).exists()
        )

        replacement = Notification.objects.filter(
            user=self.provider_user,
            kind="request_status_change",
            title=f"إلغاء الطلب العاجل: {service_request.title}",
        ).order_by("-id").first()
        self.assertIsNotNone(replacement)
        self.assertEqual(replacement.url, "")
        self.assertIn("لم يعد متاحًا للقبول", replacement.body)
        self.assertTrue(
            EventLog.objects.filter(
                event_type=EventType.STATUS_CHANGED,
                target_user=self.provider_user,
                request_id=service_request.id,
            ).exists()
        )

    def test_competitive_cancel_replaces_provider_notification(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب تنافسي",
            description="تفاصيل",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        Notification.objects.create(
            user=self.provider_user,
            title="طلب عرض خدمة تنافسية جديد",
            body="يوجد طلب تنافسي جديد يطابق تخصصك: طلب تنافسي",
            kind="request_created",
            url=f"/requests/{service_request.id}",
            audience_mode="provider",
        )
        EventLog.objects.create(
            event_type=EventType.REQUEST_CREATED,
            actor=self.client_user,
            target_user=self.provider_user,
            request_id=service_request.id,
            meta={
                "request_type": service_request.request_type,
                "competitive": True,
                "provider_id": self.provider.id,
            },
        )

        self.assertEqual(
            Notification.objects.filter(
                user=self.provider_user,
                kind="request_created",
                url=f"/requests/{service_request.id}",
            ).count(),
            1,
        )

        with self.captureOnCommitCallbacks(execute=True):
            result = execute_action(
                user=self.client_user,
                request_id=service_request.id,
                action="cancel",
            )

        self.assertTrue(result.ok)
        service_request.refresh_from_db()
        self.assertEqual(service_request.status, RequestStatus.CANCELLED)
        self.assertFalse(
            Notification.objects.filter(
                user=self.provider_user,
                kind="request_created",
                url=f"/requests/{service_request.id}",
            ).exists()
        )

        replacement = Notification.objects.filter(
            user=self.provider_user,
            kind="request_status_change",
            title=f"إلغاء الطلب التنافسي: {service_request.title}",
        ).order_by("-id").first()
        self.assertIsNotNone(replacement)
        self.assertEqual(replacement.url, "")
        self.assertIn("لم يعد متاحًا لتقديم عرض", replacement.body)
        self.assertTrue(
            EventLog.objects.filter(
                event_type=EventType.STATUS_CHANGED,
                target_user=self.provider_user,
                request_id=service_request.id,
                meta__cancelled_from_competitive_pool=True,
            ).exists()
        )

    def test_competitive_cancel_after_deadline_uses_deadline_copy(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب تنافسي متأخر",
            description="تفاصيل",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.NEW,
            city="الرياض",
            quote_deadline=timezone.localdate() - timezone.timedelta(days=1),
        )
        Notification.objects.create(
            user=self.provider_user,
            title="طلب عرض خدمة تنافسية جديد",
            body="يوجد طلب تنافسي جديد يطابق تخصصك: طلب تنافسي متأخر",
            kind="request_created",
            url=f"/requests/{service_request.id}",
            audience_mode="provider",
        )
        EventLog.objects.create(
            event_type=EventType.REQUEST_CREATED,
            actor=self.client_user,
            target_user=self.provider_user,
            request_id=service_request.id,
            meta={"request_type": service_request.request_type, "competitive": True},
        )

        with self.captureOnCommitCallbacks(execute=True):
            result = execute_action(
                user=self.staff_user,
                request_id=service_request.id,
                action="cancel",
            )

        self.assertTrue(result.ok)
        replacement = Notification.objects.filter(
            user=self.provider_user,
            kind="request_status_change",
            title=f"إلغاء الطلب التنافسي: {service_request.title}",
        ).order_by("-id").first()
        self.assertIsNotNone(replacement)
        self.assertIn("انتهت مهلة استقبال عروض الأسعار", replacement.body)
        self.assertIn("لم يعد متاحًا لتقديم عرض", replacement.body)
        self.assertTrue(
            EventLog.objects.filter(
                event_type=EventType.STATUS_CHANGED,
                target_user=self.provider_user,
                request_id=service_request.id,
                meta__cancelled_due_to_deadline=True,
            ).exists()
        )

    def test_urgent_cancel_from_staff_uses_admin_copy(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب عاجل إداري",
            description="تفاصيل",
            request_type=RequestType.URGENT,
            status=RequestStatus.PROVIDER_ACCEPTED,
            city="الرياض",
        )
        Notification.objects.create(
            user=self.provider_user,
            title="طلب خدمة عاجلة جديد",
            body="يوجد طلب عاجل جديد في تخصصك: طلب عاجل إداري",
            kind="urgent_request",
            url=f"/requests/{service_request.id}",
            audience_mode="provider",
            is_urgent=True,
        )
        EventLog.objects.create(
            event_type=EventType.REQUEST_CREATED,
            actor=self.client_user,
            target_user=self.provider_user,
            request_id=service_request.id,
            meta={"request_type": service_request.request_type},
        )

        with self.captureOnCommitCallbacks(execute=True):
            result = execute_action(
                user=self.staff_user,
                request_id=service_request.id,
                action="cancel",
            )

        self.assertTrue(result.ok)
        replacement = Notification.objects.filter(
            user=self.provider_user,
            kind="request_status_change",
            title=f"إلغاء الطلب العاجل: {service_request.title}",
        ).order_by("-id").first()
        self.assertIsNotNone(replacement)
        self.assertIn("من الإدارة", replacement.body)
        self.assertIn("لم يعد متاحًا للقبول", replacement.body)

    def test_client_notification_mentions_provider_when_provider_cancels(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب عاجل للعميل",
            description="تفاصيل",
            request_type=RequestType.URGENT,
            status=RequestStatus.PROVIDER_ACCEPTED,
            city="الرياض",
        )

        result = execute_action(
            user=self.provider_user,
            request_id=service_request.id,
            action="cancel",
            note="تعذر الوصول للموقع",
        )

        self.assertTrue(result.ok)
        client_notification = Notification.objects.filter(
            user=self.client_user,
            kind="request_status_change",
            title=f"تحديث الطلب: {service_request.title}",
        ).order_by("-id").first()
        self.assertIsNotNone(client_notification)
        self.assertIn("مزود الخدمة", client_notification.body)
        self.assertIn("السبب: تعذر الوصول للموقع", client_notification.body)

    def test_client_notification_mentions_deadline_when_competitive_request_expires(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب تنافسي للعميل",
            description="تفاصيل",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.NEW,
            city="الرياض",
            quote_deadline=timezone.localdate() - timezone.timedelta(days=1),
        )

        result = execute_action(
            user=self.staff_user,
            request_id=service_request.id,
            action="cancel",
        )

        self.assertTrue(result.ok)
        client_notification = Notification.objects.filter(
            user=self.client_user,
            kind="request_status_change",
            title=f"تحديث الطلب: {service_request.title}",
        ).order_by("-id").first()
        self.assertIsNotNone(client_notification)
        self.assertIn("انتهت مهلة استقبال عروض الأسعار", client_notification.body)
        self.assertIn("طلبك التنافسي", client_notification.body)

    def test_accepting_urgent_request_clears_pool_notifications_for_all_providers(self):
        second_provider_user = User.objects.create_user(
            phone="0501000004",
            username="provider.second",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=second_provider_user,
            provider_type="individual",
            display_name="مزود ثاني",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )

        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب عاجل جماعي",
            description="تفاصيل",
            request_type=RequestType.URGENT,
            status=RequestStatus.NEW,
            city="الرياض",
        )

        create_notification(
            user=self.provider_user,
            title="طلب عاجل موجّه إليك",
            body="تم توجيه الطلب إليك",
            kind="request_created",
            url=f"/requests/{service_request.id}",
            actor=self.client_user,
            event_type=EventType.REQUEST_CREATED,
            pref_key="new_request",
            request_id=service_request.id,
            audience_mode="provider",
        )
        create_notification(
            user=second_provider_user,
            title="طلب خدمة عاجلة جديد",
            body="يوجد طلب عاجل جديد",
            kind="urgent_request",
            url=f"/requests/{service_request.id}",
            actor=self.client_user,
            event_type=EventType.REQUEST_CREATED,
            pref_key="urgent_request",
            request_id=service_request.id,
            audience_mode="provider",
            is_urgent=True,
        )

        self.assertEqual(
            Notification.objects.filter(url=f"/requests/{service_request.id}", audience_mode="provider").count(),
            2,
        )

        service_request.accept(self.provider)
        removed_count = clear_urgent_request_provider_notifications(service_request)

        self.assertEqual(removed_count, 2)
        self.assertFalse(
            Notification.objects.filter(
                user=self.provider_user,
                url=f"/requests/{service_request.id}",
                audience_mode="provider",
            ).exists()
        )
        self.assertFalse(
            Notification.objects.filter(
                user=second_provider_user,
                url=f"/requests/{service_request.id}",
                audience_mode="provider",
            ).exists()
        )

    def test_provider_detail_serializer_exposes_client_city_fields(self):
        self.client_user.city = "جدة"
        self.client_user.save(update_fields=["city"])

        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب مع مدينة عميل",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.PROVIDER_ACCEPTED,
            city="",
        )

        payload = ProviderRequestDetailSerializer(service_request).data

        self.assertEqual(payload["client_city"], "جدة")
        self.assertIn("جدة", payload["client_city_display"])

    def test_provider_progress_update_during_execution_returns_to_awaiting_client_and_notifies_client(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب تنفيذ قائم",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.IN_PROGRESS,
            city="الرياض",
            expected_delivery_at=timezone.now(),
            estimated_service_amount="400.00",
            received_amount="150.00",
            remaining_amount="250.00",
        )

        self.client.force_login(self.provider_user)
        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.post(
                f"/api/marketplace/provider/requests/{service_request.id}/progress-update/",
                {
                    "note": "تم تعديل خطة التنفيذ",
                    "estimated_service_amount": "450.00",
                    "received_amount": "150.00",
                },
            )

        self.assertEqual(response.status_code, 200)
        service_request.refresh_from_db()
        self.assertEqual(service_request.status, RequestStatus.AWAITING_CLIENT_APPROVAL)
        self.assertIsNone(service_request.provider_inputs_approved)
        self.assertTrue(
            Notification.objects.filter(
                user=self.client_user,
                kind="request_status_change",
                title="تحديث جديد بانتظار اعتمادك",
                url=f"/orders/{service_request.id}",
            ).exists()
        )

    def test_rejecting_pending_progress_update_returns_request_to_in_progress_and_notifies_provider(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب تحت التنفيذ",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.AWAITING_CLIENT_APPROVAL,
            city="الرياض",
            expected_delivery_at=timezone.now(),
            estimated_service_amount="450.00",
            received_amount="150.00",
            remaining_amount="300.00",
        )
        service_request.status_logs.create(
            actor=self.provider_user,
            from_status=RequestStatus.PROVIDER_ACCEPTED,
            to_status=RequestStatus.IN_PROGRESS,
            note="بدء التنفيذ",
        )

        with self.captureOnCommitCallbacks(execute=True):
            result = execute_action(
                user=self.client_user,
                request_id=service_request.id,
                action="reject_inputs",
                note="القيمة الجديدة غير مناسبة",
            )

        self.assertTrue(result.ok)
        service_request.refresh_from_db()
        self.assertEqual(service_request.status, RequestStatus.IN_PROGRESS)
        self.assertEqual(service_request.provider_inputs_approved, False)
        self.assertEqual(service_request.provider_inputs_decision_note, "القيمة الجديدة غير مناسبة")
        provider_notification = Notification.objects.filter(
            user=self.provider_user,
            kind="request_status_change",
            title="تم رفض تحديث التقدم",
            url=f"/provider-orders/{service_request.id}",
        ).order_by("-id").first()
        self.assertIsNotNone(provider_notification)
        self.assertIn("القيمة الجديدة غير مناسبة", provider_notification.body)

    def test_provider_request_detail_serializer_exposes_progress_update_stage(self):
        service_request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب متابعة",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.AWAITING_CLIENT_APPROVAL,
            city="الرياض",
        )
        service_request.status_logs.create(
            actor=self.provider_user,
            from_status=RequestStatus.PROVIDER_ACCEPTED,
            to_status=RequestStatus.IN_PROGRESS,
            note="بدء التنفيذ",
        )

        payload = ProviderRequestDetailSerializer(service_request).data
        self.assertEqual(payload["provider_inputs_stage"], "progress_update")
