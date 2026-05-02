from __future__ import annotations

from rest_framework import serializers

from apps.core.i18n import localized_model_field

from .models import AccessPermission, Dashboard, UserAccessProfile


class DashboardSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    def get_name(self, obj):
        return localized_model_field(obj, "name", request=self.context.get("request"))

    class Meta:
        model = Dashboard
        fields = ["code", "name", "name_ar", "name_en", "is_active", "sort_order"]


class AccessPermissionSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()
    description_ar = serializers.CharField(source="description", read_only=True)
    description = serializers.SerializerMethodField()

    def get_name(self, obj):
        return localized_model_field(obj, "name", request=self.context.get("request"))

    def get_description(self, obj):
        request = self.context.get("request")
        localized = localized_model_field(obj, "description", request=request)
        if localized:
            return localized
        return getattr(obj, "description", "") or ""

    class Meta:
        model = AccessPermission
        fields = [
            "code",
            "dashboard_code",
            "name",
            "name_ar",
            "name_en",
            "description",
            "description_ar",
            "description_en",
            "is_active",
            "sort_order",
        ]


class MyAccessSerializer(serializers.ModelSerializer):
    dashboards = serializers.SerializerMethodField()
    permissions = serializers.SerializerMethodField()
    permissions_detail = serializers.SerializerMethodField()
    readonly = serializers.SerializerMethodField()
    expired = serializers.SerializerMethodField()
    revoked = serializers.SerializerMethodField()

    class Meta:
        model = UserAccessProfile
        fields = [
            "level",
            "dashboards",
            "permissions",
            "permissions_detail",
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

    def get_permissions_detail(self, obj: UserAccessProfile):
        if obj.level in ("admin", "power"):
            qs = AccessPermission.objects.filter(is_active=True).order_by("sort_order", "id")
        else:
            qs = obj.granted_permissions.filter(is_active=True).order_by("sort_order", "id")
        return AccessPermissionSerializer(qs, many=True, context=self.context).data

    def get_readonly(self, obj: UserAccessProfile):
        return obj.is_readonly()

    def get_expired(self, obj: UserAccessProfile):
        return obj.is_expired()

    def get_revoked(self, obj: UserAccessProfile):
        return obj.is_revoked()
