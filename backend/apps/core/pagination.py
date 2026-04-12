from __future__ import annotations

from django.conf import settings
from rest_framework.pagination import LimitOffsetPagination
from rest_framework.response import Response


class DefaultLimitOffsetPagination(LimitOffsetPagination):
    """API-wide bounded pagination without changing list response shape."""

    default_limit = 50
    max_limit = 100
    limit_query_param = "limit"
    offset_query_param = "offset"

    def paginate_queryset(self, queryset, request, view=None):
        self.default_limit = max(1, int(getattr(settings, "API_DEFAULT_LIMIT", 50) or 50))
        self.max_limit = max(self.default_limit, int(getattr(settings, "API_MAX_LIMIT", 100) or 100))
        return super().paginate_queryset(queryset, request, view=view)

    def get_paginated_response(self, data):
        response = Response(data)
        response["X-Total-Count"] = str(self.count)
        response["X-Limit"] = str(self.limit)
        response["X-Offset"] = str(self.offset)
        response["X-Has-More"] = "1" if (self.offset + self.limit) < self.count else "0"
        return response
