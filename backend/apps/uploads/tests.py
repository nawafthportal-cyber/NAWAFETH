from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest, ServiceRequestAttachment
from apps.providers.models import Category, SubCategory

from .tasks import schedule_video_optimization


class ScheduleVideoOptimizationTests(TestCase):
    def setUp(self):
        self.client_user = User.objects.create_user(
            phone="0507000101",
            username="uploads.client.test",
            role_state=UserRole.CLIENT,
        )
        category = Category.objects.create(name="صيانة")
        self.subcategory = SubCategory.objects.create(category=category, name="كهرباء")
        self.request = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب مع فيديو",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )

    @patch("apps.uploads.tasks.optimize_stored_video.delay", side_effect=RuntimeError("redis unavailable"))
    def test_schedule_video_optimization_does_not_raise_when_enqueue_fails(self, delay_mock):
        attachment = ServiceRequestAttachment.objects.create(
            request=self.request,
            file=SimpleUploadedFile("clip.mp4", b"fake-video-bytes", content_type="video/mp4"),
            file_type="video",
        )

        schedule_video_optimization(attachment, "file")

        delay_mock.assert_called_once_with(
            attachment._meta.app_label,
            attachment._meta.model_name,
            attachment.pk,
            "file",
        )
        self.assertTrue(ServiceRequestAttachment.objects.filter(pk=attachment.pk).exists())