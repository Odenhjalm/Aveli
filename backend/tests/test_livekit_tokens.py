import datetime
import json
from uuid import UUID

from jose import jwt

from app.config import settings
from app.services.livekit_tokens import build_token


def _setup_livekit_settings():
    settings.livekit_api_key = "lk_test_key"
    settings.livekit_api_secret = "lk_test_secret"


def test_build_token_host_includes_metadata():
    _setup_livekit_settings()
    now = datetime.datetime.now(datetime.timezone.utc)

    token = build_token(
        seminar_id=UUID("11111111-1111-4111-8111-111111111111"),
        session_id=UUID("22222222-2222-4222-8222-222222222222"),
        user_id=UUID("33333333-3333-4333-8333-333333333333"),
        identity="33333333-3333-4333-8333-333333333333-host",
        display_name="Aveli Host",
        avatar_url="https://cdn.wisdom.dev/avatar.png",
        role="host",
        room_name="seminar-room",
        can_create_room=True,
        can_publish=True,
        can_publish_data=True,
        can_subscribe=True,
        ttl_minutes=10,
        extra_metadata={"custom": "value"},
    )

    payload = jwt.decode(token, settings.livekit_api_secret, algorithms=["HS256"])
    assert payload["identity"] == "33333333-3333-4333-8333-333333333333-host"
    assert payload["iss"] == "lk_test_key"

    video = payload["video"]
    assert video["roomCreate"] is True
    assert video["canPublish"] is True
    assert video["canPublishData"] is True
    assert video["canSubscribe"] is True

    metadata = json.loads(payload["metadata"])
    assert metadata["seminar_id"] == "11111111-1111-4111-8111-111111111111"
    assert metadata["session_id"] == "22222222-2222-4222-8222-222222222222"
    assert metadata["user_id"] == "33333333-3333-4333-8333-333333333333"
    assert metadata["role"] == "host"
    assert metadata["display_name"] == "Aveli Host"
    assert metadata["avatar_url"] == "https://cdn.wisdom.dev/avatar.png"
    assert metadata["custom"] == "value"

    # Legacy grants structure remains for backwards compatibility.
    legacy_video = payload["grants"]["video"]
    legacy_metadata = payload["grants"]["metadata"]
    assert legacy_video == video
    assert legacy_metadata == metadata

    exp = datetime.datetime.fromtimestamp(payload["exp"], datetime.timezone.utc)
    nbf = datetime.datetime.fromtimestamp(payload["nbf"], datetime.timezone.utc)
    assert exp > now
    assert exp > nbf


def test_build_token_participant_limited_publish():
    _setup_livekit_settings()

    token = build_token(
        seminar_id=UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
        session_id=UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
        user_id=UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
        identity="cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        display_name="Participant",
        avatar_url=None,
        role="participant",
        room_name="seminar-room",
        can_create_room=False,
        can_publish=False,
        can_publish_data=False,
        can_subscribe=True,
        ttl_minutes=5,
        extra_metadata=None,
    )

    payload = jwt.decode(token, settings.livekit_api_secret, algorithms=["HS256"])
    video = payload["video"]
    metadata = json.loads(payload["metadata"])
    assert video["roomJoin"] is True
    assert video.get("roomCreate") is None
    assert video["canPublish"] is False
    assert video["canPublishData"] is False
    assert video["canSubscribe"] is True
    assert metadata["role"] == "participant"
    assert metadata["session_id"] == "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    assert "avatar_url" not in metadata

    assert payload["grants"]["video"] == video
    assert payload["grants"]["metadata"] == metadata
