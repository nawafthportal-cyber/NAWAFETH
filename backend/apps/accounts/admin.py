from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
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
        ("الصلاحيات", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("التواريخ", {"fields": ("last_login", "created_at")}),
    )

    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("phone", "password1", "password2", "role_state", "is_staff", "is_superuser"),
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
class OTPAdmin(admin.ModelAdmin):
    list_display = ("id", "phone", "code", "is_used", "attempts", "expires_at", "created_at", "ip_address")
    list_filter = ("is_used",)
    search_fields = ("phone", "code", "ip_address")
    ordering = ("-id",)
    readonly_fields = ("created_at",)


@admin.register(BiometricToken)
class BiometricTokenAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "phone", "token", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("phone", "token", "user__phone", "user__username")
    ordering = ("-id",)
    readonly_fields = ("created_at",)
    list_select_related = ("user",)
