from __future__ import annotations

from django import forms
from django.core.exceptions import ValidationError

from apps.uploads.validators import (
    DOCUMENT_EXTENSIONS,
    DOCUMENT_MIME_TYPES,
    IMAGE_EXTENSIONS,
    IMAGE_MIME_TYPES,
    validate_secure_upload,
)


class PortalLoginForm(forms.Form):
    username = forms.CharField(label="اسم المستخدم", max_length=150)
    password = forms.CharField(label="كلمة المرور", widget=forms.PasswordInput)


class PortalOTPForm(forms.Form):
    code = forms.CharField(label="رمز التحقق", max_length=4)

    def clean_code(self):
        code = (self.cleaned_data.get("code") or "").strip()
        if not (len(code) == 4 and code.isdigit()):
            raise forms.ValidationError("الكود يجب أن يكون 4 أرقام")
        return code


class BulkMessageForm(forms.Form):
    body = forms.CharField(label="نص الرسالة", widget=forms.Textarea, max_length=2000)
    attachment = forms.FileField(label="مرفق", required=False)
    send_at = forms.DateTimeField(
        label="وقت الإرسال",
        required=False,
        input_formats=["%Y-%m-%dT%H:%M"],
    )

    def clean_attachment(self):
        attachment = self.cleaned_data.get("attachment")
        if attachment is None:
            return attachment
        try:
            validate_secure_upload(
                attachment,
                allowed_extensions=IMAGE_EXTENSIONS | DOCUMENT_EXTENSIONS,
                allowed_mime_types=IMAGE_MIME_TYPES | DOCUMENT_MIME_TYPES,
                max_size_mb=25,
                rename=True,
                rename_prefix="extras_portal_msg",
            )
        except ValidationError as exc:
            raise forms.ValidationError(str(exc))
        return attachment


class FinanceSettingsForm(forms.Form):
    bank_name = forms.CharField(label="اسم البنك", required=False, max_length=120)
    account_name = forms.CharField(label="اسم الحساب", required=False, max_length=120)
    iban = forms.CharField(label="IBAN", required=False, max_length=34)
    qr_image = forms.FileField(label="QR", required=False)

    def clean_qr_image(self):
        qr_image = self.cleaned_data.get("qr_image")
        if qr_image is None:
            return qr_image
        try:
            validate_secure_upload(
                qr_image,
                allowed_extensions=IMAGE_EXTENSIONS,
                allowed_mime_types=IMAGE_MIME_TYPES,
                max_size_mb=10,
                rename=True,
                rename_prefix="extras_portal_qr",
            )
        except ValidationError as exc:
            raise forms.ValidationError(str(exc))
        return qr_image
