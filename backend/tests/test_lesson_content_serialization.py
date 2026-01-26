import json

import pytest

from app.utils.lesson_content import serialize_audio_embeds


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("# Title\n\nBody text.", "# Title\n\nBody text."),
        ("", ""),
        (
            'Already has <audio controls src="https://cdn/audio.mp3"></audio>',
            'Already has <audio controls src="https://cdn/audio.mp3"></audio>',
        ),
    ],
)
def test_serialize_audio_embeds_no_op(raw, expected):
    assert serialize_audio_embeds(raw) == expected


def test_serialize_audio_embeds_from_quill_document():
    document = json.dumps(
        [
            {"insert": "Intro\n"},
            {"insert": {"audio": "https://cdn.example.com/audio.mp3"}},
            {"insert": "\n"},
        ]
    )

    normalized = serialize_audio_embeds(document)

    assert "Intro" in normalized
    assert '<audio controls src="https://cdn.example.com/audio.mp3"></audio>' in normalized


def test_serialize_audio_embeds_inline_payload_with_attributes():
    snippet = (
        'Meditation start.\n'
        '{"insert":{"audio":{"source":"https://media.local/file.mp3","download_url":""}},'
        '"attributes":{"align":"center"}}\n'
        "Outro."
    )

    normalized = serialize_audio_embeds(snippet)

    assert '<audio controls src="https://media.local/file.mp3"></audio>' in normalized
    assert "Meditation start." in normalized
    assert "Outro." in normalized
