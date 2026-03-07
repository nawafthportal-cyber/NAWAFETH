from __future__ import annotations

from apps.subscriptions.capabilities import storage_upload_limit_mb_for_user
from apps.extras.services import user_has_active_extra


def user_max_upload_mb(user) -> int:
    """
    حدود مبدئية:
    - Basic: 10MB
    - Pioneer: 20MB
    - Professional: 100MB
    - Extra Uploads: 100MB
    """
    if not user or not getattr(user, "is_authenticated", False):
        return 10

    base_limit = storage_upload_limit_mb_for_user(user)

    # Extra uploads (اشتراك أو add-on)
    if user_has_active_extra(user, "uploads_"):
        return max(base_limit, 100)

    return base_limit
