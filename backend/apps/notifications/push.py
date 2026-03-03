import json
import logging
import os
from typing import Optional

from django.conf import settings
from django.utils import timezone

from .models import DeviceToken, Notification


logger = logging.getLogger(__name__)
_firebase_init_done = False


def _firebase_enabled() -> bool:
    return bool(getattr(settings, "FIREBASE_PUSH_ENABLED", False))


def _init_firebase() -> bool:
    global _firebase_init_done
    if _firebase_init_done:
        return True
    if not _firebase_enabled():
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials
    except Exception as exc:
        logger.warning("firebase_admin import failed: %s", exc)
        return False

    if firebase_admin._apps:
        _firebase_init_done = True
        return True

    creds_path = (getattr(settings, "FIREBASE_CREDENTIALS_PATH", "") or "").strip()
    creds_json = (getattr(settings, "FIREBASE_CREDENTIALS_JSON", "") or "").strip()
    project_id = (getattr(settings, "FIREBASE_PROJECT_ID", "") or "").strip() or None

    try:
        if creds_json:
            cred_data = json.loads(creds_json)
            cred = credentials.Certificate(cred_data)
            firebase_admin.initialize_app(cred, {"projectId": project_id} if project_id else None)
        elif creds_path and os.path.exists(creds_path):
            cred = credentials.Certificate(creds_path)
            firebase_admin.initialize_app(cred, {"projectId": project_id} if project_id else None)
        else:
            cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred, {"projectId": project_id} if project_id else None)
    except Exception as exc:
        logger.warning("Firebase initialization failed: %s", exc)
        return False

    _firebase_init_done = True
    return True


def send_push_for_notification(notification: Notification) -> int:
    if not _init_firebase():
        return 0

    try:
        from firebase_admin import messaging
    except Exception as exc:
        logger.warning("firebase_admin.messaging import failed: %s", exc)
        return 0

    user = notification.user
    tokens_qs = DeviceToken.objects.filter(user=user, is_active=True).only("id", "token", "platform")
    tokens = list(tokens_qs)
    if not tokens:
        return 0

    sound_name = (getattr(settings, "FIREBASE_PUSH_SOUND", "default") or "default").strip() or "default"
    sent = 0

    for dt in tokens:
        token = (dt.token or "").strip()
        if not token:
            continue

        android_cfg = messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="nawafeth_messages",
                sound=sound_name,
            ),
        )
        apns_cfg = messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(sound=sound_name),
            )
        )

        data_payload = {
            "notification_id": str(notification.id),
            "kind": str(notification.kind or "info"),
            "url": str(notification.url or ""),
            "audience_mode": str(notification.audience_mode or "shared"),
        }

        msg = messaging.Message(
            token=token,
            notification=messaging.Notification(
                title=notification.title,
                body=notification.body,
            ),
            data=data_payload,
            android=android_cfg,
            apns=apns_cfg,
        )

        try:
            messaging.send(msg)
            sent += 1
            DeviceToken.objects.filter(id=dt.id).update(last_seen_at=timezone.now())
        except Exception as exc:
            err = str(exc)
            if "registration-token-not-registered" in err or "invalid-argument" in err:
                DeviceToken.objects.filter(id=dt.id).update(is_active=False)
            logger.warning("Push send failed for token %s: %s", dt.id, exc)

    return sent
