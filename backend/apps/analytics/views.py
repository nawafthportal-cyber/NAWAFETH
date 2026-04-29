from __future__ import annotations

from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.backoffice.policies import AnalyticsExportPolicy
from apps.core.feature_flags import analytics_events_enabled, analytics_kpi_surfaces_enabled

from .permissions import IsBackofficeAnalytics
from .filters import parse_dates
from .serializers import AnalyticsEventIngestSerializer, AnalyticsEventSerializer
from .services import (
    extras_kpis,
    kpis_summary,
    promo_kpis,
    provider_kpis,
    revenue_daily,
    revenue_monthly,
    requests_breakdown,
    subscription_kpis,
)
from .export import export_paid_invoices_csv
from .tracking import track_event


class AnalyticsEventIngestView(APIView):
	permission_classes = [AllowAny]

	def post(self, request):
		if not analytics_events_enabled():
			return Response({"detail": "غير موجود"}, status=status.HTTP_404_NOT_FOUND)
		batch_payload = request.data.get("events") if isinstance(request.data, dict) else None
		if isinstance(batch_payload, list):
			serializer = AnalyticsEventIngestSerializer(data=batch_payload, many=True)
			serializer.is_valid(raise_exception=True)
			accepted = 0
			deduped = 0
			for item in serializer.validated_data:
				event = track_event(
					event_name=item["event_name"],
					channel=item.get("channel"),
					surface=item.get("surface", ""),
					source_app=item.get("source_app", ""),
					object_type=item.get("object_type", ""),
					object_id=item.get("object_id", ""),
					actor=request.user if getattr(request.user, "is_authenticated", False) else None,
					session_id=item.get("session_id", ""),
					dedupe_key=item.get("dedupe_key", ""),
					occurred_at=item.get("occurred_at"),
					payload=item.get("payload") or {},
					version=item.get("version", 1),
				)
				accepted += 1
				if event is None and item.get("dedupe_key"):
					deduped += 1
			return Response(
				{
					"accepted": True,
					"count": accepted,
					"deduped": deduped,
				},
				status=status.HTTP_202_ACCEPTED,
			)

		serializer = AnalyticsEventIngestSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		event = track_event(
			event_name=serializer.validated_data["event_name"],
			channel=serializer.validated_data.get("channel"),
			surface=serializer.validated_data.get("surface", ""),
			source_app=serializer.validated_data.get("source_app", ""),
			object_type=serializer.validated_data.get("object_type", ""),
			object_id=serializer.validated_data.get("object_id", ""),
			actor=request.user if getattr(request.user, "is_authenticated", False) else None,
			session_id=serializer.validated_data.get("session_id", ""),
			dedupe_key=serializer.validated_data.get("dedupe_key", ""),
			occurred_at=serializer.validated_data.get("occurred_at"),
			payload=serializer.validated_data.get("payload") or {},
			version=serializer.validated_data.get("version", 1),
		)
		if event is None and serializer.validated_data.get("dedupe_key"):
			return Response({"accepted": True, "deduped": True}, status=status.HTTP_202_ACCEPTED)
		return Response(
			{
				"accepted": True,
				"event": AnalyticsEventSerializer(event).data if event else None,
			},
			status=status.HTTP_202_ACCEPTED,
		)


class DashboardKPIsView(APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		start_date, end_date = parse_dates(request.query_params)
		data = kpis_summary(start_date=start_date, end_date=end_date)
		return Response(data, status=status.HTTP_200_OK)


class RevenueDailyView(APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		start_date, end_date = parse_dates(request.query_params)
		data = revenue_daily(start_date=start_date, end_date=end_date)
		return Response(data, status=status.HTTP_200_OK)


class RevenueMonthlyView(APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		start_date, end_date = parse_dates(request.query_params)
		data = revenue_monthly(start_date=start_date, end_date=end_date)
		return Response(data, status=status.HTTP_200_OK)


class RequestsBreakdownView(APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		start_date, end_date = parse_dates(request.query_params)
		data = requests_breakdown(start_date=start_date, end_date=end_date)
		return Response(data, status=status.HTTP_200_OK)


class ExportPaidInvoicesCSVView(APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		policy = AnalyticsExportPolicy.evaluate_and_log(
			request.user,
			request=request,
			reference_type="analytics.export",
			reference_id="paid_invoices_csv",
			extra={"surface": "api.analytics.export_paid_invoices_csv"},
		)
		if not policy.allowed:
			return Response({"detail": "غير مصرح", "reason": policy.reason}, status=status.HTTP_403_FORBIDDEN)
		return export_paid_invoices_csv()


class _AnalyticsKPISurfacesMixin:
	def _ensure_enabled(self):
		if not analytics_kpi_surfaces_enabled():
			return Response({"detail": "غير موجود"}, status=status.HTTP_404_NOT_FOUND)
		return None

	def _params(self, request):
		start_date, end_date = parse_dates(request.query_params)
		limit_raw = request.query_params.get("limit")
		try:
			limit = max(1, min(50, int(limit_raw or 10)))
		except (TypeError, ValueError):
			limit = 10
		return start_date, end_date, limit


class ProviderKPIsView(_AnalyticsKPISurfacesMixin, APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		blocked = self._ensure_enabled()
		if blocked:
			return blocked
		start_date, end_date, limit = self._params(request)
		provider_id = request.query_params.get("provider_id")
		data = provider_kpis(
			start_date=start_date,
			end_date=end_date,
			provider_id=provider_id,
			limit=limit,
		)
		return Response(data, status=status.HTTP_200_OK)


class PromoKPIsView(_AnalyticsKPISurfacesMixin, APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		blocked = self._ensure_enabled()
		if blocked:
			return blocked
		start_date, end_date, limit = self._params(request)
		data = promo_kpis(
			start_date=start_date,
			end_date=end_date,
			campaign_kind=(request.query_params.get("campaign_kind") or "").strip(),
			limit=limit,
		)
		return Response(data, status=status.HTTP_200_OK)


class SubscriptionKPIsView(_AnalyticsKPISurfacesMixin, APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		blocked = self._ensure_enabled()
		if blocked:
			return blocked
		start_date, end_date, limit = self._params(request)
		data = subscription_kpis(start_date=start_date, end_date=end_date, limit=limit)
		return Response(data, status=status.HTTP_200_OK)


class ExtrasKPIsView(_AnalyticsKPISurfacesMixin, APIView):
	permission_classes = [IsBackofficeAnalytics]

	def get(self, request):
		blocked = self._ensure_enabled()
		if blocked:
			return blocked
		start_date, end_date, limit = self._params(request)
		data = extras_kpis(start_date=start_date, end_date=end_date, limit=limit)
		return Response(data, status=status.HTTP_200_OK)
