from __future__ import annotations

from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

from .special_offers_service import SpecialOfferDomainError

_CANVAS_WIDTH = 1600
_CANVAS_HEIGHT = 1600
_CANVAS_SIZE = (_CANVAS_WIDTH, _CANVAS_HEIGHT)
_CANVAS_BACKGROUND = (248, 247, 243)
_IMAGE_AREA_HEIGHT = 1360
_BOTTOM_BAND_HEIGHT = _CANVAS_HEIGHT - _IMAGE_AREA_HEIGHT
_GRID_MARGIN = 32
_GRID_GAP = 24
_LOGO_SCALE_RATIO = 0.25
_PRICE_FONT_SIZE = 96
_PRICE_STROKE_WIDTH = 4
_PRICE_FILL = (255, 255, 255, 255)
_PRICE_STROKE_FILL = (0, 0, 0, 255)
_PRICE_BAND_FILL = (10, 16, 22, 204)
_JPEG_QUALITY = 90
_JPEG_SUBSAMPLING = 0
_REPO_ROOT = Path(__file__).resolve().parents[3]
_LOGO_PATH = _REPO_ROOT / "backend" / "assets" / "loggo_clean.png"
_FONT_PATH = _REPO_ROOT / "frontend" / "fonts" / "NotoSans-Bold.ttf"

GRID_SPECS = {
    1: (1, 1),
    2: (2, 1),
    3: (2, 2),
    4: (2, 2),
    5: (3, 2),
}


async def compose_special_offer_image(
    *,
    source_bytes: list[bytes],
    price_amount_cents: int,
) -> bytes:
    normalized_source_bytes = _require_source_bytes(source_bytes)
    resolved_price_amount_cents = _require_price_amount(price_amount_cents)

    base_image = Image.new("RGB", _CANVAS_SIZE, _CANVAS_BACKGROUND)
    try:
        cell_boxes = _layout_boxes(len(normalized_source_bytes))
        for image_bytes, cell_box in zip(normalized_source_bytes, cell_boxes, strict=True):
            normalized_image = _normalize_source_image(
                image_bytes=image_bytes,
                target_size=(cell_box[2] - cell_box[0], cell_box[3] - cell_box[1]),
            )
            try:
                base_image.paste(normalized_image, cell_box[:2])
            finally:
                normalized_image.close()

        composed_image = _apply_overlays(
            base_image=base_image,
            price_amount_cents=resolved_price_amount_cents,
        )
        try:
            output = BytesIO()
            composed_image.save(
                output,
                format="JPEG",
                quality=_JPEG_QUALITY,
                subsampling=_JPEG_SUBSAMPLING,
                progressive=False,
                optimize=False,
            )
            return output.getvalue()
        finally:
            composed_image.close()
    finally:
        base_image.close()


def _require_source_bytes(source_bytes: list[bytes]) -> list[bytes]:
    if len(source_bytes) < 1 or len(source_bytes) > 5:
        raise SpecialOfferDomainError(
            "special_offer_invalid_course_count",
            status_code=400,
        )

    normalized_source_bytes: list[bytes] = []
    for item in source_bytes:
        if not isinstance(item, bytes) or not item:
            raise SpecialOfferDomainError(
                "special_offer_source_invalid_media",
                status_code=400,
            )
        normalized_source_bytes.append(item)
    return normalized_source_bytes


def _require_price_amount(price_amount_cents: int) -> int:
    if isinstance(price_amount_cents, bool) or not isinstance(price_amount_cents, int):
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    if price_amount_cents <= 0:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    return price_amount_cents


def _normalize_source_image(*, image_bytes: bytes, target_size: tuple[int, int]) -> Image.Image:
    try:
        with Image.open(BytesIO(image_bytes)) as raw_image:
            rgb_image = raw_image.convert("RGB")
            try:
                return ImageOps.fit(
                    rgb_image,
                    target_size,
                    method=Image.Resampling.LANCZOS,
                    centering=(0.5, 0.5),
                )
            finally:
                rgb_image.close()
    except OSError as exc:
        raise SpecialOfferDomainError(
            "special_offer_source_invalid_media",
            status_code=400,
        ) from exc


def _layout_boxes(source_count: int) -> list[tuple[int, int, int, int]]:
    grid_spec = GRID_SPECS.get(source_count)
    if grid_spec is None:
        raise SpecialOfferDomainError(
            "special_offer_invalid_course_count",
            status_code=400,
        )

    columns, rows = grid_spec
    usable_left = _GRID_MARGIN
    usable_top = _GRID_MARGIN
    usable_right = _CANVAS_WIDTH - _GRID_MARGIN
    usable_bottom = _IMAGE_AREA_HEIGHT - _GRID_MARGIN
    usable_width = usable_right - usable_left
    usable_height = usable_bottom - usable_top
    cell_width = (usable_width - (_GRID_GAP * (columns - 1))) // columns
    cell_height = (usable_height - (_GRID_GAP * (rows - 1))) // rows

    boxes: list[tuple[int, int, int, int]] = []
    for index in range(source_count):
        column = index % columns
        row = index // columns
        left = usable_left + column * (cell_width + _GRID_GAP)
        top = usable_top + row * (cell_height + _GRID_GAP)
        boxes.append((left, top, left + cell_width, top + cell_height))
    return boxes


def _apply_overlays(*, base_image: Image.Image, price_amount_cents: int) -> Image.Image:
    base_rgba = base_image.convert("RGBA")
    overlay = Image.new("RGBA", base_rgba.size, (0, 0, 0, 0))
    try:
        draw = ImageDraw.Draw(overlay, "RGBA")
        band_top = _IMAGE_AREA_HEIGHT
        draw.rectangle(
            (0, band_top, _CANVAS_WIDTH, _CANVAS_HEIGHT),
            fill=_PRICE_BAND_FILL,
        )
        _paste_logo(overlay)
        _draw_price(draw=draw, price_amount_cents=price_amount_cents)
        composed = Image.alpha_composite(base_rgba, overlay)
        return composed.convert("RGB")
    finally:
        overlay.close()
        base_rgba.close()


def _paste_logo(overlay: Image.Image) -> None:
    logo = _load_logo()
    try:
        max_width = int(_CANVAS_WIDTH * _LOGO_SCALE_RATIO)
        max_height = int(_IMAGE_AREA_HEIGHT * _LOGO_SCALE_RATIO)
        logo.thumbnail((max_width, max_height), Image.Resampling.LANCZOS)
        left = (_CANVAS_WIDTH - logo.width) // 2
        top = (_IMAGE_AREA_HEIGHT - logo.height) // 2
        overlay.paste(logo, (left, top), logo)
    finally:
        logo.close()


def _load_logo() -> Image.Image:
    if not _LOGO_PATH.is_file():
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    try:
        with Image.open(_LOGO_PATH) as raw_logo:
            if str(raw_logo.format or "").upper() != "PNG":
                raise SpecialOfferDomainError(
                    "special_offer_domain_unavailable",
                    status_code=503,
                )
            if "A" not in raw_logo.getbands():
                raise SpecialOfferDomainError(
                    "special_offer_domain_unavailable",
                    status_code=503,
                )
            return raw_logo.convert("RGBA")
    except OSError as exc:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        ) from exc


def _draw_price(*, draw: ImageDraw.ImageDraw, price_amount_cents: int) -> None:
    font = _load_price_font()
    price_text = _format_price(price_amount_cents)
    text_bbox = draw.textbbox(
        (0, 0),
        price_text,
        font=font,
        stroke_width=_PRICE_STROKE_WIDTH,
    )
    text_width = text_bbox[2] - text_bbox[0]
    text_height = text_bbox[3] - text_bbox[1]
    text_x = ((_CANVAS_WIDTH - text_width) // 2) - text_bbox[0]
    text_y = _IMAGE_AREA_HEIGHT + ((_BOTTOM_BAND_HEIGHT - text_height) // 2) - text_bbox[1]
    draw.text(
        (text_x, text_y),
        price_text,
        font=font,
        fill=_PRICE_FILL,
        stroke_width=_PRICE_STROKE_WIDTH,
        stroke_fill=_PRICE_STROKE_FILL,
    )


def _load_price_font() -> ImageFont.FreeTypeFont:
    if not _FONT_PATH.is_file():
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        )
    try:
        return ImageFont.truetype(str(_FONT_PATH), _PRICE_FONT_SIZE)
    except OSError as exc:
        raise SpecialOfferDomainError(
            "special_offer_domain_unavailable",
            status_code=503,
        ) from exc


def _format_price(price_amount_cents: int) -> str:
    whole_units, fractional_units = divmod(price_amount_cents, 100)
    if fractional_units == 0:
        return f"{whole_units} kr"
    return f"{whole_units},{fractional_units:02d} kr"


__all__ = [
    "compose_special_offer_image",
]
