from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from apps.core.admin_mixins import HiddenFromAdminIndexMixin

from .models import BiometricToken, OTP, User, Wallet

@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ("-id",)
    list_display = ("id", "phone", "role_state", "is_active", "is_staff", "created_at")
    list_filter = ("role_state", "is_active", "is_staff")
    search_fields = ("phone", "email", "username")

    fieldsets = (
        (None, {"fields": ("phone", "password")}),
        ("معلومات الحساب", {"fields": ("email", "username", "role_state")}),
        ("الملف الشخصي", {"fields": ("first_name", "last_name", "city", "profile_image", "cover_image", "terms_accepted_at")}),
        ("الصلاحيات", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("التواريخ", {"fields": ("last_login", "created_at")}),
    )

    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("phone", "password1", "password2", "email", "username", "role_state", "is_staff", "is_superuser"),
        }),
    )


@admin.register(Wallet)
class WalletAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "balance", "created_at")
    search_fields = ("user__phone", "user__username", "user__email")
    ordering = ("-id",)
    readonly_fields = ("created_at",)
    list_select_related = ("user",)


@admin.register(OTP)
class OTPAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "phone", "masked_code", "is_used", "attempts", "expires_at", "created_at", "ip_address")
    list_filter = ("is_used",)
    search_fields = ("phone", "ip_address")
    ordering = ("-id",)
    readonly_fields = ("phone", "masked_code", "is_used", "attempts", "expires_at", "created_at", "ip_address")
    fields = ("phone", "masked_code", "is_used", "attempts", "expires_at", "created_at", "ip_address")

    @admin.display(description="OTP")
    def masked_code(self, obj):
        code = str(getattr(obj, "code", "") or "")
        if not code:
            return "-"
        if len(code) <= 2:
            return "*" * len(code)
        return f"{code[:2]}{'*' * (len(code) - 2)}"

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(BiometricToken)
class BiometricTokenAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "phone", "masked_token", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("phone", "user__phone", "user__username")
    ordering = ("-id",)
    readonly_fields = ("user", "phone", "masked_token", "created_at")
    fields = ("user", "phone", "is_active", "masked_token", "created_at")
    list_select_related = ("user",)
    exclude = ("token",)

    @admin.display(description="Token")
    def masked_token(self, obj):
        token = str(getattr(obj, "token", "") or "")
        if not token:
            return "-"
        if len(token) <= 8:
            return "*" * len(token)
        return f"{token[:4]}...{token[-4:]}"

    def has_add_permission(self, request):
        return False
