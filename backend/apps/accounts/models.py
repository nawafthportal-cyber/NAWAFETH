from django.db import models
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.utils import timezone
from decimal import Decimal

class UserRole(models.TextChoices):
    VISITOR = "visitor", "زائر"
    PHONE_ONLY = "phone_only", "عميل (رقم فقط)"
    CLIENT = "client", "عميل"
    PROVIDER = "provider", "مقدم خدمة"
    STAFF = "staff", "موظف"

class UserManager(BaseUserManager):
    def create_user(self, phone: str, password: str | None = None, **extra_fields):
        if not phone:
            raise ValueError("رقم الجوال مطلوب")
        phone = phone.strip()
        user = self.model(phone=phone, **extra_fields)
        user.set_password(password) if password else user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, phone: str, password: str, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("role_state", UserRole.STAFF)

        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True")

        return self.create_user(phone=phone, password=password, **extra_fields)

class User(AbstractBaseUser, PermissionsMixin):
    # NOTE: kept nullable temporarily to allow migrating existing rows created
    # before the phone field existed. You can make it non-nullable later.
    phone = models.CharField(max_length=20, unique=True, null=True, blank=True)
    email = models.EmailField(blank=True, null=True)
    username = models.CharField(max_length=50, blank=True, null=True)

    first_name = models.CharField(max_length=50, blank=True, null=True)
    last_name = models.CharField(max_length=50, blank=True, null=True)
    city = models.CharField(max_length=100, blank=True, null=True)
    profile_image = models.FileField(upload_to="accounts/profile/%Y/%m/", null=True, blank=True)
    cover_image = models.FileField(upload_to="accounts/cover/%Y/%m/", null=True, blank=True)

    role_state = models.CharField(max_length=20, choices=UserRole.choices, default=UserRole.VISITOR)

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    created_at = models.DateTimeField(default=timezone.now)

    # Level-3 completion (client full registration)
    terms_accepted_at = models.DateTimeField(null=True, blank=True)

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = []

    objects = UserManager()

    def __str__(self):
        return self.phone or f"User {self.pk}"


class Wallet(models.Model):
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="wallet",
    )
    balance = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    created_at = models.DateTimeField(default=timezone.now)

    def __str__(self):
        return f"Wallet({self.user_id})"


class OTP(models.Model):
    phone = models.CharField(max_length=20)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    code = models.CharField(max_length=6)
    expires_at = models.DateTimeField()
    attempts = models.PositiveIntegerField(default=0)
    is_used = models.BooleanField(default=False)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        indexes = [
            models.Index(fields=["phone"]),
			models.Index(fields=["phone", "created_at"]),
			models.Index(fields=["ip_address", "created_at"]),
        ]
