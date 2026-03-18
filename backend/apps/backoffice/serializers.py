from __future__ import annotations

from rest_framework import serializers

from .models import AccessPermission, Dashboard, UserAccessProfile


class DashboardSerializer(serializers.ModelSerializer):
    class Meta:
        model = Dashboard
        fields = ["code", "name_ar", "is_active", "sort_order"]


class MyAccessSerializer(serializers.ModelSerializer):
    dashboards = serializers.SerializerMethodField()
    permissions = serializers.SerializerMethodField()
    readonly = serializers.SerializerMethodField()
    expired = serializers.SerializerMethodField()
    revoked = serializers.SerializerMethodField()

    class Meta:
        model = UserAccessProfile
        fields = [
            "level",
            "dashboards",
            "permissions",
            "readonly",
            "expired",
            "revoked",
            "expires_at",
            "revoked_at",
        ]

    def get_dashboards(self, obj: UserAccessProfile):
        if obj.level in ("admin", "power"):
            qs = Dashboard.objects.filter(is_active=True).order_by("sort_order", "id")
        elif obj.level == "client":
            qs = Dashboard.objects.filter(
                code__in=UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS,
                is_active=True,
            ).order_by("sort_order", "id")
        else:
            qs = obj.allowed_dashboards.filter(is_active=True).order_by("sort_order", "id")
        return DashboardSerializer(qs, many=True).data

    def get_permissions(self, obj: UserAccessProfile):
        if obj.level in ("admin", "power"):
            qs = AccessPermission.objects.filter(is_active=True).order_by("sort_order", "id")
        else:
            qs = obj.granted_permissions.filter(is_active=True).order_by("sort_order", "id")
        return list(qs.values_list("code", flat=True))

    def get_readonly(self, obj: UserAccessProfile):
        return obj.is_readonly()

    def get_expired(self, obj: UserAccessProfile):
        return obj.is_expired()

    def get_revoked(self, obj: UserAccessProfile):
        return obj.is_revoked()
