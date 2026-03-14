"""Placeholder service definitions for future media resolution."""


class MediaResolverService:
    """Future media resolver for the Aveli Media Control Plane.

    Planned responsibilities:
    - resolve `lesson_media` records to canonical `media_assets`
    - verify media state before playback metadata is exposed
    - generate signed playback URLs when policy allows it
    - provide deterministic media playback metadata to callers

    This placeholder is intentionally not wired into the existing runtime media
    pipeline yet.
    """

    pass
