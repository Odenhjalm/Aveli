from uuid import UUID

import pytest

from app.services.livekit_tokens import LiveKitTokenConfigError, build_token


def test_build_token_is_forbidden_while_livekit_is_paused() -> None:
    with pytest.raises(LiveKitTokenConfigError, match="pausat"):
        build_token(
            seminar_id=UUID("11111111-1111-4111-8111-111111111111"),
            session_id=UUID("22222222-2222-4222-8222-222222222222"),
            user_id=UUID("33333333-3333-4333-8333-333333333333"),
            identity="33333333-3333-4333-8333-333333333333-host",
            display_name="Aveli Host",
            avatar_url="https://cdn.wisdom.dev/avatar.png",
            role="host",
            room_name="seminar-room",
        )
