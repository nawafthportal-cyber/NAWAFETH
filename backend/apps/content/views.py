from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .services import public_content_payload


class PublicSiteContentView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        return Response(public_content_payload())
