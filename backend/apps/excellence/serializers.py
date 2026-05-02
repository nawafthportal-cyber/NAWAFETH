from rest_framework import serializers

from apps.core.i18n import localized_model_field

from .models import ExcellenceBadgeType


class ExcellenceBadgeTypeSerializer(serializers.ModelSerializer):
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
        model = ExcellenceBadgeType
        fields = (
            "code",
            "name",
            "name_ar",
            "name_en",
            "icon",
            "color",
            "description",
            "description_ar",
            "description_en",
            "review_cycle_days",
        )
