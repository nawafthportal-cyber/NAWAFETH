from __future__ import annotations

from datetime import datetime, timedelta

from celery import shared_task
from django.utils import timezone

from .services import rebuild_daily_analytics, rebuild_daily_analytics_range


@shared_task(name="analytics.rebuild_daily_stats")
def rebuild_daily_stats_task(day: str | None = None, *, days_back: int = 1):
    if day:
        target_day = datetime.fromisoformat(day).date()
        return rebuild_daily_analytics(target_day)
    target_day = timezone.localdate() - timedelta(days=max(1, int(days_back or 1)))
    return rebuild_daily_analytics(target_day)


@shared_task(name="analytics.rebuild_daily_stats_range")
def rebuild_daily_stats_range_task(start_day: str, end_day: str | None = None):
    start_date = datetime.fromisoformat(start_day).date()
    end_date = datetime.fromisoformat(end_day).date() if end_day else start_date
    return rebuild_daily_analytics_range(start_day=start_date, end_day=end_date)
