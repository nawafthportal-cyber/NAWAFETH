from django.db import migrations
from django.db.models import Count


CURRENT_STATUSES = ("active", "grace")
TIER_PRIORITY = {
    "basic": 0,
    "pioneer": 1,
    "professional": 2,
}


def _plan_tier(plan) -> str:
    tier = (getattr(plan, "tier", "") or "").strip().lower()
    code = (getattr(plan, "code", "") or "").strip().lower()
    title = (getattr(plan, "title", "") or "").strip().lower()
    features = {str(item or "").strip().lower() for item in (getattr(plan, "features", None) or [])}

    if tier in {"pro", "professional"} or code in {"pro", "professional"} or "احتراف" in title or "professional" in title:
        return "professional"
    if tier in {"riyadi", "pioneer", "leading"} or code in {"riyadi", "pioneer", "leading"} or "رياد" in title or "pioneer" in title:
        return "pioneer"
    if "advanced_analytics" in features or "verify_blue" in features:
        return "professional"
    if "priority_support" in features or "promo_ads" in features:
        return "pioneer"
    return "basic"


def _subscription_sort_timestamp(sub) -> float:
    marker = getattr(sub, "start_at", None) or getattr(sub, "created_at", None)
    if not marker:
        return 0.0
    try:
        return float(marker.timestamp())
    except Exception:
        return 0.0


def _subscription_priority(sub) -> tuple[int, int, float, int, int]:
    tier = _plan_tier(getattr(sub, "plan", None))
    is_paid = tier != "basic"
    status_priority = 2 if getattr(sub, "status", "") == "active" else 1
    return (
        1 if is_paid else 0,
        status_priority,
        _subscription_sort_timestamp(sub),
        TIER_PRIORITY.get(tier, 0),
        int(getattr(sub, "id", 0) or 0),
    )


def normalize_current_subscription_rows(apps, schema_editor):
    Subscription = apps.get_model("subscriptions", "Subscription")

    duplicate_user_ids = list(
        Subscription.objects.filter(status__in=CURRENT_STATUSES)
        .values("user_id")
        .annotate(current_count=Count("id"))
        .filter(current_count__gt=1)
        .values_list("user_id", flat=True)
    )
    if not duplicate_user_ids:
        return

    for user_id in duplicate_user_ids:
        current_rows = list(
            Subscription.objects.filter(user_id=user_id, status__in=CURRENT_STATUSES)
            .select_related("plan")
            .order_by("id")
        )
        if len(current_rows) < 2:
            continue
        effective = max(current_rows, key=_subscription_priority)
        for sub in current_rows:
            if sub.id == effective.id:
                continue
            sub.status = "cancelled"
            sub.save(update_fields=["status", "updated_at"])


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0003_make_basic_plan_free"),
    ]

    operations = [
        migrations.RunPython(normalize_current_subscription_rows, migrations.RunPython.noop),
    ]
