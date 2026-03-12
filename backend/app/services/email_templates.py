from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

_TEMPLATES_DIR = Path(__file__).resolve().parents[1] / "email_templates"


@lru_cache(maxsize=1)
def _get_environment() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(_TEMPLATES_DIR)),
        autoescape=select_autoescape(("html", "xml")),
    )


def render_template(name: str, **data: object) -> str:
    return _get_environment().get_template(name).render(**data)
