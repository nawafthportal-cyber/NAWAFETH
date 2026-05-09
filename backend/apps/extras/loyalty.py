from __future__ import annotations

from typing import Any

from django.db.models import Sum

from apps.extras_portal.models import LoyaltyMembership


LOYALTY_LEVELS: tuple[dict[str, Any], ...] = (
    {"key": "member", "label": "عضو", "min_points": 0},
    {"key": "silver", "label": "فضي", "min_points": 100},
    {"key": "gold", "label": "ذهبي", "min_points": 300},
    {"key": "elite", "label": "نخبة", "min_points": 700},
)

LOYALTY_REWARDS: tuple[dict[str, Any], ...] = (
    {"key": "discount_5", "title": "خصم 5%", "points": 50, "description": "مناسب للطلبات الصغيرة والمتكررة."},
    {"key": "discount_10", "title": "خصم 10%", "points": 120, "description": "مكافأة أقوى للعميل النشط."},
    {"key": "priority", "title": "أولوية حجز", "points": 200, "description": "تمييز العميل في ترتيب المواعيد."},
    {"key": "vip_followup", "title": "متابعة VIP", "points": 350, "description": "متابعة خاصة بعد إتمام الخدمة."},
)


def loyalty_level_for_points(points: int) -> dict[str, Any]:
    points = max(0, int(points or 0))
    current = LOYALTY_LEVELS[0]
    next_level = None

    for idx, level in enumerate(LOYALTY_LEVELS):
        if points >= int(level["min_points"]):
            current = level
            next_level = LOYALTY_LEVELS[idx + 1] if idx + 1 < len(LOYALTY_LEVELS) else None

    if next_level:
        floor = int(current["min_points"])
        target = int(next_level["min_points"])
        span = max(target - floor, 1)
        progress = min(100, max(0, round(((points - floor) / span) * 100)))
        points_to_next = max(target - points, 0)
    else:
        progress = 100
        points_to_next = 0

    return {
        "key": current["key"],
        "label": current["label"],
        "min_points": current["min_points"],
        "next_label": next_level["label"] if next_level else "",
        "next_min_points": next_level["min_points"] if next_level else None,
        "points_to_next": points_to_next,
        "progress_percent": progress,
    }


def loyalty_rewards_for_points(points: int) -> list[dict[str, Any]]:
    points = max(0, int(points or 0))
    return [
        {
            **reward,
            "available": points >= int(reward["points"]),
            "points_remaining": max(int(reward["points"]) - points, 0),
        }
        for reward in LOYALTY_REWARDS
    ]


def provider_display_name(provider) -> str:
    display_name = str(getattr(provider, "display_name", "") or "").strip()
    if display_name:
        return display_name
    user = getattr(provider, "user", None)
    full_name = " ".join(
        part
        for part in [
            str(getattr(user, "first_name", "") or "").strip(),
            str(getattr(user, "last_name", "") or "").strip(),
        ]
        if part
    )
    return full_name or str(getattr(user, "username", "") or "").strip() or "مزود خدمة"


def provider_image_url(provider, request=None) -> str:
    for field_name in ("profile_image", "cover_image"):
        field = getattr(provider, field_name, None)
        if not field:
            continue
        try:
            url = field.url
        except Exception:
            url = ""
        if not url:
            continue
        return request.build_absolute_uri(url) if request is not None else url
    return ""


def loyalty_membership_payload(membership: LoyaltyMembership, *, request=None) -> dict[str, Any]:
    provider = membership.program.provider
    balance = int(membership.points_balance or 0)
    return {
        "provider_id": provider.id,
        "provider_name": provider_display_name(provider),
        "provider_city": str(getattr(provider, "city", "") or "").strip(),
        "provider_image": provider_image_url(provider, request=request),
        "program_id": membership.program_id,
        "program_name": str(membership.program.name or "برنامج الولاء").strip(),
        "points_balance": balance,
        "total_earned": int(membership.total_earned or 0),
        "total_redeemed": int(membership.total_redeemed or 0),
        "level": loyalty_level_for_points(balance),
        "rewards": loyalty_rewards_for_points(balance),
        "joined_at": membership.joined_at,
        "updated_at": membership.updated_at,
    }


def loyalty_wallet_for_user(user, *, request=None, limit: int | None = None) -> dict[str, Any]:
    if not user or not getattr(user, "is_authenticated", False):
        return {
            "summary": {
                "memberships_count": 0,
                "total_balance": 0,
                "total_earned": 0,
                "best_level": loyalty_level_for_points(0),
            },
            "memberships": [],
        }

    memberships_qs = (
        LoyaltyMembership.objects.filter(user=user, program__is_active=True)
        .select_related("program", "program__provider", "program__provider__user")
        .order_by("-points_balance", "-updated_at", "-id")
    )
    aggregate = memberships_qs.aggregate(total_balance=Sum("points_balance"), total_earned=Sum("total_earned"))
    if limit is not None:
        memberships_qs = memberships_qs[: max(0, int(limit))]

    memberships = [loyalty_membership_payload(row, request=request) for row in memberships_qs]
    best_balance = max([item["points_balance"] for item in memberships], default=0)
    return {
        "summary": {
            "memberships_count": len(memberships),
            "total_balance": int(aggregate["total_balance"] or 0),
            "total_earned": int(aggregate["total_earned"] or 0),
            "best_level": loyalty_level_for_points(best_balance),
        },
        "memberships": memberships,
    }
