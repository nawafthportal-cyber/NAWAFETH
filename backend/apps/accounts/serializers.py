import re

from rest_framework import serializers
from .models import User


def _digits_only(value: str) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def _validate_phone_local05(value: str) -> str:
    digits = _digits_only(value)
    if not re.fullmatch(r"05\d{8}", digits):
        raise serializers.ValidationError("صيغة رقم الجوال يجب أن تكون 05XXXXXXXX")
    return digits


class OTPSendSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=20)

    def validate_phone(self, value: str) -> str:
        return _validate_phone_local05(value)

class OTPVerifySerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=20)
    code = serializers.CharField(max_length=4)

    def validate_phone(self, value: str) -> str:
        return _validate_phone_local05(value)


class BiometricEnrollSerializer(serializers.Serializer):
    """Issued by authenticated user to register a biometric device token."""
    pass  # no body needed; phone is taken from request.user


class BiometricLoginSerializer(serializers.Serializer):
    """Used to login via biometric: phone + device_token."""
    phone = serializers.CharField(max_length=20)
    device_token = serializers.CharField(max_length=128)

    def validate_phone(self, value: str) -> str:
        return _validate_phone_local05(value)


class CompleteRegistrationSerializer(serializers.Serializer):
    first_name = serializers.CharField(
        max_length=150,
        error_messages={
            "required": "الاسم الأول مطلوب",
            "blank": "الاسم الأول مطلوب",
        },
    )
    last_name = serializers.CharField(
        max_length=150,
        error_messages={
            "required": "الاسم الأخير مطلوب",
            "blank": "الاسم الأخير مطلوب",
        },
    )
    username = serializers.CharField(
        max_length=50,
        error_messages={
            "required": "اسم المستخدم مطلوب",
            "blank": "اسم المستخدم مطلوب",
        },
    )
    email = serializers.EmailField(
        error_messages={
            "required": "البريد الإلكتروني مطلوب",
            "blank": "البريد الإلكتروني مطلوب",
            "invalid": "البريد الإلكتروني غير صالح",
        }
    )
    password = serializers.CharField(
        min_length=8,
        max_length=128,
        write_only=True,
        error_messages={
            "required": "كلمة المرور مطلوبة",
            "blank": "كلمة المرور مطلوبة",
            "min_length": "كلمة المرور يجب أن تكون 8 أحرف على الأقل",
        },
    )
    password_confirm = serializers.CharField(
        min_length=8,
        max_length=128,
        write_only=True,
        error_messages={
            "required": "تأكيد كلمة المرور مطلوب",
            "blank": "تأكيد كلمة المرور مطلوب",
            "min_length": "تأكيد كلمة المرور يجب أن يكون 8 أحرف على الأقل",
        },
    )
    accept_terms = serializers.BooleanField(
        error_messages={
            "required": "يجب الموافقة على الشروط والأحكام",
            "invalid": "يجب الموافقة على الشروط والأحكام",
        }
    )
    # Optional for forward compatibility with mobile payloads.
    city = serializers.CharField(
        max_length=100,
        required=False,
        allow_blank=True,
        allow_null=True,
    )

    def validate_username(self, value: str) -> str:
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("اسم المستخدم مطلوب")
        if len(value) < 3:
            raise serializers.ValidationError("اسم المستخدم يجب أن يكون 3 أحرف على الأقل")
        if not re.match(r"^[A-Za-z0-9_.]+$", value):
            raise serializers.ValidationError("اسم المستخدم يقبل الحروف الإنجليزية والأرقام و (_) و (.) فقط")

        request = self.context.get("request")
        qs = User.objects.filter(username__iexact=value)
        if request is not None and getattr(request, "user", None) and request.user.is_authenticated:
            qs = qs.exclude(pk=request.user.pk)
        if qs.exists():
            raise serializers.ValidationError("اسم المستخدم محجوز، اختر اسماً آخر")

        return value

    def validate_first_name(self, value: str) -> str:
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("الاسم الأول مطلوب")
        # Arabic/English letters + spaces only
        if not re.match(r"^[A-Za-z\u0600-\u06FF ]+$", value):
            raise serializers.ValidationError("الاسم الأول يجب أن يحتوي على أحرف عربية/إنجليزية فقط")
        return value

    def validate_last_name(self, value: str) -> str:
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("الاسم الأخير مطلوب")
        if not re.match(r"^[A-Za-z\u0600-\u06FF ]+$", value):
            raise serializers.ValidationError("الاسم الأخير يجب أن يحتوي على أحرف عربية/إنجليزية فقط")
        return value

    def validate_accept_terms(self, value: bool) -> bool:
        if value is not True:
            raise serializers.ValidationError("يجب الموافقة على اتفاقية الاستخدام")
        return value

    def validate(self, attrs):
        password = (attrs.get("password") or "").strip()
        password_confirm = (attrs.get("password_confirm") or "").strip()
        if password != password_confirm:
            raise serializers.ValidationError({"password_confirm": "كلمة المرور وتأكيدها غير متطابقين"})
        return attrs

    def validate_city(self, value: str | None):
        if value is None:
            return None
        value = (value or "").strip()
        return value or None


class MeUpdateSerializer(serializers.Serializer):
    """Update the authenticated user's basic fields (no password change here)."""

    phone = serializers.CharField(max_length=20, required=False)
    email = serializers.EmailField(required=False, allow_blank=True, allow_null=True)
    username = serializers.CharField(max_length=50, required=False, allow_blank=True, allow_null=True)
    first_name = serializers.CharField(max_length=50, required=False, allow_blank=True, allow_null=True)
    last_name = serializers.CharField(max_length=50, required=False, allow_blank=True, allow_null=True)
    city = serializers.CharField(max_length=100, required=False, allow_blank=True, allow_null=True)
    profile_image = serializers.FileField(required=False, allow_null=True)
    cover_image = serializers.FileField(required=False, allow_null=True)

    def validate_phone(self, value: str) -> str:
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("رقم الجوال مطلوب")
        return _validate_phone_local05(value)

    def validate_username(self, value: str | None):
        if value is None:
            return None
        value = (value or "").strip()
        return value or None

    def validate_first_name(self, value: str | None):
        if value is None:
            return None
        value = (value or "").strip()
        return value or None

    def validate_last_name(self, value: str | None):
        if value is None:
            return None
        value = (value or "").strip()
        return value or None

    def validate_city(self, value: str | None):
        if value is None:
            return None
        value = (value or "").strip()
        return value or None


class WalletSerializer(serializers.Serializer):
    id = serializers.IntegerField(read_only=True)
    balance = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    created_at = serializers.DateTimeField(read_only=True)


class ChangeUsernameSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=50)

    def validate_username(self, value: str) -> str:
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("اسم المستخدم مطلوب")
        if len(value) < 3:
            raise serializers.ValidationError("اسم المستخدم يجب أن يكون 3 أحرف على الأقل")
        if not re.match(r"^[A-Za-z0-9_.]+$", value):
            raise serializers.ValidationError("اسم المستخدم يقبل الحروف الإنجليزية والأرقام و (_) و (.) فقط")

        request = self.context.get("request")
        qs = User.objects.filter(username__iexact=value)
        if request is not None and getattr(request, "user", None) and request.user.is_authenticated:
            qs = qs.exclude(pk=request.user.pk)
        if qs.exists():
            raise serializers.ValidationError("اسم المستخدم محجوز، اختر اسماً آخر")
        return value


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(required=True, write_only=True)
    new_password = serializers.CharField(required=True, min_length=8, max_length=128, write_only=True)
    new_password_confirm = serializers.CharField(required=True, min_length=8, max_length=128, write_only=True)

    def validate(self, attrs):
        new_password = (attrs.get("new_password") or "").strip()
        new_password_confirm = (attrs.get("new_password_confirm") or "").strip()
        if new_password != new_password_confirm:
            raise serializers.ValidationError({"new_password_confirm": "كلمة المرور وتأكيدها غير متطابقين"})
        return attrs
