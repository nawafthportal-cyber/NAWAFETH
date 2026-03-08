from rest_framework import serializers

from .models import ExcellenceBadgeType


class ExcellenceBadgeTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExcellenceBadgeType
        fields = (
            "code",
            "name_ar",
            "icon",
            "color",
            "description",
            "review_cycle_days",
        )
