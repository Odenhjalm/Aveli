import app.db as db


def test_configure_windows_asyncio_policy_switches_to_selector_on_windows(
    monkeypatch,
) -> None:
    class FakeSelectorPolicy:
        pass

    class FakeProactorPolicy:
        pass

    recorded: list[object] = []

    monkeypatch.setattr(db.sys, "platform", "win32")
    monkeypatch.setattr(
        db.asyncio,
        "WindowsSelectorEventLoopPolicy",
        FakeSelectorPolicy,
        raising=False,
    )
    monkeypatch.setattr(
        db.asyncio,
        "get_event_loop_policy",
        lambda: FakeProactorPolicy(),
    )
    monkeypatch.setattr(
        db.asyncio,
        "set_event_loop_policy",
        lambda policy: recorded.append(policy),
    )

    db.configure_windows_asyncio_policy()

    assert len(recorded) == 1
    assert isinstance(recorded[0], FakeSelectorPolicy)


def test_configure_windows_asyncio_policy_is_noop_when_selector_already_set(
    monkeypatch,
) -> None:
    class FakeSelectorPolicy:
        pass

    recorded: list[object] = []

    monkeypatch.setattr(db.sys, "platform", "win32")
    monkeypatch.setattr(
        db.asyncio,
        "WindowsSelectorEventLoopPolicy",
        FakeSelectorPolicy,
        raising=False,
    )
    monkeypatch.setattr(
        db.asyncio,
        "get_event_loop_policy",
        lambda: FakeSelectorPolicy(),
    )
    monkeypatch.setattr(
        db.asyncio,
        "set_event_loop_policy",
        lambda policy: recorded.append(policy),
    )

    db.configure_windows_asyncio_policy()

    assert recorded == []
