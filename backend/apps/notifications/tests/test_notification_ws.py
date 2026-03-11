import asyncio

import pytest
from channels.db import database_sync_to_async
from channels.testing import WebsocketCommunicator

from config.asgi import application
from apps.accounts.models import User
from apps.notifications.services import create_notification


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_notification_ws_requires_authenticated_user():
    communicator = WebsocketCommunicator(application, "/ws/notifications/")
    connected, _ = await communicator.connect()
    assert connected is False
    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_notification_ws_broadcasts_created_notifications(mocker):
    user = await database_sync_to_async(User.objects.create_user)(phone="0530000001")

    from apps.messaging import jwt_auth

    mocker.patch.object(jwt_auth, "get_user_for_token", return_value=user)

    communicator = WebsocketCommunicator(application, "/ws/notifications/?token=fake")
    connected, _ = await communicator.connect()
    assert connected is True

    hello = await communicator.receive_json_from()
    assert hello["type"] == "connected"

    await database_sync_to_async(create_notification)(
        user=user,
        title="إشعار جديد",
        body="تم إنشاء عنصر جديد",
        kind="info",
        audience_mode="client",
    )

    event = await asyncio.wait_for(communicator.receive_json_from(), timeout=2)
    assert event["type"] == "notification.created"
    assert event["notification"]["title"] == "إشعار جديد"
    assert event["notification"]["audience_mode"] == "client"
    assert event["notification"]["is_read"] is False

    await communicator.disconnect()
