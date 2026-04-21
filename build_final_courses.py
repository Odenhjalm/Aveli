from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent
SOURCE_ROOT = REPO_ROOT / "courses"
TARGET_ROOT = REPO_ROOT / os.environ.get("FINAL_COURSES_TARGET", "final_courses")
REPORT_JSON = TARGET_ROOT / "mapping_report.json"
REPORT_MD = TARGET_ROOT / "summary_report.md"

COURSE_NAME_OVERRIDES = {
    "fargernas-frekvenser-och-berydelser-7yo9-hfurwg4wfc": "Färgernas frekvenser och betydelser",
    "fargernas-helande-magi-2wa9-hfrk4ecod4": "Änglahealerutbildning del 1 av 3",
    "intro-tecken-fran-anglar-90ii-hful0n5ako": "Änglarnas tecken och budskap",
    "lar-dig-anvanda-din-intuition-snabbt-och-enkelt-8q98-hf29ndy9nk": "Intuition i vardagen",
    "lar-dig-kommunicera-med-djur-eclp-hfq55r41dc": "Kommunicera med djur",
    "lar-dig-meditera-45av-hf35c8t6zk": "Meditationens grunder",
    "lar-dig-tyda-tarot-igsz-hf37892400": "Tarotens grunder",
    "manifestara-ditt-dromliv-luwv-hf31ggxy28": "Manifestera ditt drömliv",
    "nycklar-till-din-helande-kraft-inom-dig-5azq-hf38c8wor4": "Din inre helande kraft",
    "spirituell-coach-5zek-hfoej944ao": "Spirituell coachutbildning del 1 av 3",
    "symbolernas-inre-hemligheter-1013-hf35znznsg": "Symbolernas inre hemligheter",
    "tarologi-del-1-6y4q-hfgcxonx20": "Tarologiutbildning del 3 av 3",
    "tarologi-del-1-90ce-hfgizcvmuo": "Tarologiutbildning del 1 av 3",
    "tarologi-del-2-eq74-hfgo5j8bb4": "Tarologiutbildning del 2 av 3",
    "utbildning-anglahealer-del-2-6fkv-hfrlht3w40": "Änglahealerutbildning del 2 av 3",
    "utbildning-anglahealer-del-3-3s9x-hfrlor1wco": "Änglahealerutbildning del 3 av 3",
    "utbildning-sjalvlakande-orter-och-nutrition-ax8b-hfrn5g87js": "Självläkande örter och nutrition del 1 av 2",
    "utbildning-sjalvlakande-orter-och-nutrition-del-2-1v3d-hfrncjb1c8": "Självläkande örter och nutrition del 2 av 2",
    "utbildning-spirituell-coach-del-2-9on6-hfraa543ls": "Spirituell coachutbildning del 2 av 3",
    "utbildning-spirituell-coach-del-3-d44j-hfradfx7oo": "Spirituell coachutbildning del 3 av 3",
    "utbildning-spirituell-healer-del-1-j2yf-hfrc77pafk": "Spirituell healerutbildning del 1 av 3",
    "utbildning-spirituell-healer-del-2-vr4-hfrcat6j7s": "Spirituell healerutbildning del 2 av 3",
    "utbildning-spirituell-healer-del-3-g9yv-hfrcgq0s9k": "Spirituell healerutbildning del 3 av 3",
    "utbildning-spirituell-meditation-del-1-8m5g-hfrmdjn6yo": "Spirituell meditation del 1 av 3",
    "utbildning-spirituell-meditation-del-2-1274-hfrmnf8wug": "Spirituell meditation del 2 av 3",
    "utbildning-spirituell-meditation-del-3-l460-hfrms0fis0": "Spirituell meditation del 3 av 3",
    "utbildning-vit-magi-del-1-5lv5-hfrbkif44o": "Vit magi del 1 av 2",
    "utbildning-vit-magi-del-2-1hmt-hfrbnvvjjc": "Vit magi del 2 av 2",
    "vilken-frekvenspersonlighet-ar-du-nu-hmba-hf465nn9oo": "Din frekvenspersonlighet",
    "vilket-element-ar-du-ecnc-hf3a95cbi0": "Vilket element bär du",
    "vit-magi-kpao-hfqcvlo0bs": "Vit magins grunder",
}

TITLE_REPLACEMENTS = {
    "Manifestara": "Manifestera",
    "  ": " ",
    "1av 3": "1 av 3",
    "Änglarnas besök?": "Änglarnas besök",
    "födslofärg": "födelsefärg",
    "Utbildning - ": "",
}

INLINE_REPLACEMENTS = {
    "dagrytme": "dagrytm",
    "sammarbetet": "samarbetet",
}

SECTION_TITLES = {
    "sammanfattning": "Sammanfattning",
    "övning": "Övning",
    "ovning": "Övning",
    "reflektion": "Reflektion",
    "reflektionsfrågor": "Reflektionsfrågor",
    "reflektionsfragor": "Reflektionsfrågor",
    "hemuppgift": "Hemuppgift",
    "meditation": "Meditation",
    "affirmation": "Affirmation",
    "ritual": "Ritual",
    "ritualer": "Ritualer",
    "mantra": "Mantra",
    "magi": "Magi",
}

FORBIDDEN_FOLDER_CHARS = '<>:"/\\|?*'
MARKDOWN_TOKEN_RE = re.compile(r"\[(MEDIA|MISSING MEDIA):\s*([^\]]+)\]")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
MARKDOWN_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+(.+?)\s*$")
LIST_MARKER_RE = re.compile(r"^\s*(?:[-+*•])\s+")
ORDERED_MARKER_RE = re.compile(r"^\s*(\d+)[.)]\s+(.+)$")
MULTISPACE_RE = re.compile(r"[ \t]{2,}")
WHITESPACE_BEFORE_PUNCT_RE = re.compile(r"\s+([,.;:!?])")
SPACE_AFTER_COLON_RE = re.compile(r":(?=\S)")
TRAILING_PUNCT_SPACING_RE = re.compile(r"([,.;:!?])([^\s”\"')\]])")
TIME_SPACING_RE = re.compile(r"\b(\d{1,2})\.\s+(\d{2})\b")
LETTER_DASH_RE = re.compile(r"([A-Za-zÅÄÖåäö])[–—]([A-Za-zÅÄÖåäö])")
LABEL_FIXES = (
    ("Frekvens:", "Frekvens"),
    ("Tillstånd:", "Tillstånd"),
    ("Symboliskt:", "Symboliskt"),
    ("Färg:", "Färg"),
    ("Mening:", "Mening"),
)


@dataclass
class MediaCopyResult:
    copied_name: str
    media_type: str
    sha256: str
    byte_size: int
    source_relpath: str
    target_relpath: str
    duplicate_group_size: int


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_space(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("\ufeff", "").replace("\u00a0", " ")
    text = WHITESPACE_BEFORE_PUNCT_RE.sub(r"\1", text)
    text = SPACE_AFTER_COLON_RE.sub(": ", text)
    text = TRAILING_PUNCT_SPACING_RE.sub(r"\1 \2", text)
    text = TIME_SPACING_RE.sub(r"\1.\2", text)
    text = LETTER_DASH_RE.sub(r"\1 – \2", text)
    text = MULTISPACE_RE.sub(" ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def sentence_case(text: str) -> str:
    value = normalize_space(text)
    if not value:
        return value
    return value[0].upper() + value[1:]


def normalize_title(text: str) -> str:
    value = normalize_space(text)
    for source, target in TITLE_REPLACEMENTS.items():
        value = value.replace(source, target)
    value = value.strip(" .")
    if value.endswith("?"):
        value = value[:-1]
    return sentence_case(value)


def strip_numeric_prefix(text: str) -> str:
    return re.sub(r"^\d+[.)]?\s*", "", text).strip()


def slug_like_to_title(source: str) -> str:
    parts = source.split("-")
    if len(parts) >= 2 and len(parts[-1]) >= 8 and len(parts[-2]) <= 5:
        parts = parts[:-2]
    elif parts and len(parts[-1]) >= 8:
        parts = parts[:-1]
    replacements = {
        "angla": "ängla",
        "anglar": "änglar",
        "farger": "färger",
        "berydelser": "betydelser",
        "lar": "lär",
        "anvanda": "använda",
        "sjal": "själ",
        "sjalv": "själv",
        "sjalvlakande": "självläkande",
        "dromliv": "drömliv",
        "fargsprak": "färgspråk",
        "fodslofarg": "födelsefärg",
        "fran": "från",
        "orter": "örter",
        "manifestara": "manifestera",
        "ar": "är",
    }
    words = [replacements.get(part, part) for part in parts]
    return normalize_title(" ".join(words))


def sanitize_folder_name(text: str, max_length: int) -> str:
    value = unicodedata.normalize("NFC", normalize_space(text))
    for char in FORBIDDEN_FOLDER_CHARS:
        value = value.replace(char, "")
    value = value.replace("?", "").replace("!", "")
    value = value.replace(":", " -")
    value = re.sub(r"\s+", " ", value).strip(" .")
    if len(value) > max_length:
        value = value[:max_length].rstrip(" .")
    return value or "Untitled"


def ensure_unique_name(base_name: str, used_names: set[str], max_length: int) -> str:
    candidate = sanitize_folder_name(base_name, max_length=max_length)
    if candidate not in used_names:
        used_names.add(candidate)
        return candidate
    index = 2
    while True:
        suffix = f" {index}"
        trimmed = sanitize_folder_name(candidate, max_length=max_length - len(suffix))
        test_value = f"{trimmed}{suffix}"
        if test_value not in used_names:
            used_names.add(test_value)
            return test_value
        index += 1


def strip_inline_markdown(text: str) -> str:
    text = text.replace("\\*", "*").replace("\\_", "_").replace("\\(", "(").replace("\\)", ")")
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)
    text = re.sub(r"\[[^\]]*\]\(<[^>]+>\)", "", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", text)
    text = re.sub(r"\*\*\*(.+?)\*\*\*", r"\1", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"__(.+?)__", r"\1", text)
    text = re.sub(r"(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)", r"\1", text)
    text = re.sub(r"(?<!_)_(?!\s)(.+?)(?<!\s)_(?!_)", r"\1", text)
    return text.replace("**", "").replace("__", "").replace("_", "").replace("*", "")


def is_probable_heading(line: str) -> bool:
    lowered = line.lower().strip(" :")
    if lowered in SECTION_TITLES:
        return True
    if re.match(r"^(beta|alfa|theta|delta|gamma)\b\s*[–\-(]", lowered):
        return True
    letters = [char for char in line if char.isalpha()]
    if letters:
        uppercase_ratio = sum(1 for char in letters if char.isupper()) / len(letters)
        if uppercase_ratio > 0.7 and len(line) <= 80:
            return True
    if len(line) <= 70 and line.endswith(":"):
        return True
    if len(line) <= 80 and line == line.title() and line.count(" ") <= 8:
        return True
    return False


def polish_heading(line: str) -> str:
    value = normalize_space(strip_numeric_prefix(line))
    letters = [char for char in value if char.isalpha()]
    if letters:
        uppercase_ratio = sum(1 for char in letters if char.isupper()) / len(letters)
        if uppercase_ratio > 0.7:
            value = value.lower()
    value = normalize_title(value)
    value = re.sub(
        r"^(BETA|ALFA|THETA|DELTA|GAMMA)\s*[–-]?\s*",
        lambda match: match.group(1).title() + " – ",
        value,
        flags=re.I,
    )
    if any(value.startswith(prefix) for prefix in ("Beta –", "Alfa –", "Theta –", "Delta –", "Gamma –")):
        value = re.sub(r" –([A-Za-zÅÄÖåäö])", r" – \1", value)
        value = re.sub(
            r"^(Beta|Alfa|Theta|Delta|Gamma) – ([A-ZÅÄÖ])",
            lambda match: f"{match.group(1)} – {match.group(2).lower()}",
            value,
        )
        if "(" in value and ")" not in value:
            value += ")"
    return normalize_space(value)


def split_compound_label_line(line: str) -> list[str]:
    value = normalize_space(strip_inline_markdown(line))
    if not value:
        return []
    value = re.sub(r"(Frekvens:\s*.*?)(?=Tillstånd:)", r"\1\n", value)
    value = re.sub(r"(Tillstånd:\s*.*?)(?=Symboliskt:|Färg:|Mening:)", r"\1\n", value)
    value = re.sub(r"(?<!\n)(Symboliskt:)", r"\n\1", value)
    value = re.sub(r"(?<!\n)(Färg:)", r"\n\1", value)
    value = re.sub(r"(?<!\n)(Mening:)", r"\n\1", value)
    chunks = [normalize_space(chunk) for chunk in value.split("\n") if normalize_space(chunk)]
    result: list[str] = []
    for chunk in chunks:
        for raw_label, clean_label in LABEL_FIXES:
            if chunk.startswith(raw_label):
                rest = normalize_space(chunk[len(raw_label):])
                if clean_label == "Tillstånd" and rest:
                    rest = rest[:1].lower() + rest[1:]
                chunk = f"{clean_label}: {rest}" if rest else clean_label
                break
        result.append(chunk)
    return result


def clean_body_text(text: str) -> str:
    text = HTML_COMMENT_RE.sub("", text)

    def replace_token(match: re.Match[str]) -> str:
        return f"\n@@MEDIAREF|{match.group(2).strip()}@@\n"

    text = MARKDOWN_TOKEN_RE.sub(replace_token, text)
    output_lines: list[str] = []
    previous_blank = True

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            if output_lines and output_lines[-1] != "":
                output_lines.append("")
            previous_blank = True
            continue

        heading_match = MARKDOWN_HEADING_RE.match(line)
        if heading_match:
            heading = polish_heading(strip_inline_markdown(heading_match.group(1)).rstrip(":"))
            if output_lines and output_lines[-1] != "":
                output_lines.append("")
            output_lines.extend([heading, ""])
            previous_blank = False
            continue
        if re.match(r"^\s*#{1,6}\s*$", line):
            continue

        ordered_match = ORDERED_MARKER_RE.match(line)
        if ordered_match:
            number = ordered_match.group(1)
            remainder = normalize_space(strip_inline_markdown(ordered_match.group(2)))
            if output_lines and output_lines[-1] != "":
                output_lines.append("")
            output_lines.extend([f"Steg {number}", "", remainder, ""])
            previous_blank = False
            continue

        line = LIST_MARKER_RE.sub("", line)
        line = normalize_space(strip_inline_markdown(line))
        if not line:
            continue

        if line.startswith("@@MEDIAREF|") and line.endswith("@@"):
            if output_lines and output_lines[-1] != "":
                output_lines.append("")
            output_lines.extend([line, ""])
            previous_blank = False
            continue

        for chunk in split_compound_label_line(line):
            normalized = normalize_space(chunk)
            if not normalized:
                continue
            if normalized in {"_", "*"}:
                continue
            if is_probable_heading(normalized) and previous_blank:
                output_lines.extend([polish_heading(normalized.rstrip(":")), ""])
            else:
                output_lines.append(normalized)
            previous_blank = False

    while output_lines and output_lines[-1] == "":
        output_lines.pop()

    result = "\n".join(output_lines)
    for source, target in INLINE_REPLACEMENTS.items():
        result = result.replace(source, target)
    return re.sub(r"\n{3,}", "\n\n", normalize_space(result)).strip() + "\n"


def media_type_label(media_type: str) -> str:
    return {
        "image": "Bildfil",
        "audio": "Ljudfil",
        "video": "Videofil",
        "document": "Dokument",
    }.get(media_type, "Mediafil")


def infer_media_type(suffix: str) -> str:
    ext = suffix.lower().lstrip(".")
    if ext in {"jpg", "jpeg", "png", "gif", "webp", "bmp"}:
        return "image"
    if ext in {"mp3", "wav", "m4a", "aac", "ogg"}:
        return "audio"
    if ext in {"mp4", "mov", "webm"}:
        return "video"
    if ext in {"pdf", "doc", "docx", "txt"}:
        return "document"
    return "media"


def dedupe_media_by_legacy_id(media_files: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for entry in media_files:
        legacy_id = str(entry.get("legacy_media_id") or "")
        if legacy_id:
            grouped[legacy_id].append(entry)
    return grouped


def copy_media_files(
    lesson_dir: Path,
    lesson_record: dict[str, Any],
    course_folder_name: str,
) -> tuple[list[dict[str, Any]], dict[str, list[MediaCopyResult]], list[dict[str, Any]]]:
    media_groups = dedupe_media_by_legacy_id(lesson_record.get("media_files") or [])
    copied_results: dict[str, list[MediaCopyResult]] = defaultdict(list)
    media_inventory: list[dict[str, Any]] = []
    duplicate_groups: list[dict[str, Any]] = []

    for legacy_id, entries in sorted(media_groups.items()):
        hash_groups = Counter(str(entry.get("sha256") or "") for entry in entries if entry.get("sha256"))
        for sha_value, count in hash_groups.items():
            if count > 1:
                duplicate_groups.append(
                    {
                        "legacy_media_id": legacy_id,
                        "sha256": sha_value,
                        "file_count": count,
                        "filenames": sorted(Path(str(entry["course_media_path"])).name for entry in entries if entry.get("sha256") == sha_value),
                    }
                )

        for entry in sorted(entries, key=lambda item: str(item.get("course_media_path") or "")):
            source_relpath = Path(str(entry["course_media_path"]))
            source_path = REPO_ROOT / source_relpath
            if not source_path.is_file():
                raise FileNotFoundError(f"Missing source media file: {source_path}")
            target_path = lesson_dir / source_path.name
            shutil.copy2(source_path, target_path)
            source_hash = str(entry.get("sha256") or sha256_file(source_path))
            target_hash = sha256_file(target_path)
            if source_hash != target_hash:
                raise RuntimeError(f"Hash mismatch after copy: {source_path} -> {target_path}")
            media_type = infer_media_type(target_path.suffix)
            copy_result = MediaCopyResult(
                copied_name=target_path.name,
                media_type=media_type,
                sha256=target_hash,
                byte_size=int(entry.get("byte_size") or target_path.stat().st_size),
                source_relpath=source_relpath.as_posix(),
                target_relpath=(Path("final_courses") / course_folder_name / lesson_dir.name / target_path.name).as_posix(),
                duplicate_group_size=hash_groups.get(source_hash, 1),
            )
            copied_results[legacy_id].append(copy_result)
            media_inventory.append(
                {
                    "legacy_media_id": legacy_id,
                    "filename": copy_result.copied_name,
                    "media_type": media_type,
                    "sha256": copy_result.sha256,
                    "byte_size": copy_result.byte_size,
                    "source_path": copy_result.source_relpath,
                    "target_path": copy_result.target_relpath,
                }
            )

    return media_inventory, copied_results, duplicate_groups


def replace_media_placeholders(
    content: str,
    copied_media: dict[str, list[MediaCopyResult]],
    missing_media: list[dict[str, Any]],
) -> str:
    lines: list[str] = []
    for raw_line in content.splitlines():
        if "@@MEDIAREF|" in raw_line:
            raw_line = re.sub(r"@@MEDIAREF\|[^@]+@@", "", raw_line)
        if raw_line.startswith("@@MEDIAREF|") and raw_line.endswith("@@"):
            continue
        lines.append(raw_line.rstrip())
    collapsed: list[str] = []
    for line in lines:
        if line == "" and collapsed and collapsed[-1] == "":
            continue
        collapsed.append(line)
    lines = collapsed
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines).strip() + "\n"


def append_media_section(
    content: str,
    copied_media: dict[str, list[MediaCopyResult]],
    missing_media: list[dict[str, Any]],
) -> str:
    section_lines: list[str] = []
    all_copied = [item for items in copied_media.values() for item in items]
    if all_copied:
        section_lines.extend(["Mediereferenser", ""])
        for item in all_copied:
            section_lines.append(f"{media_type_label(item.media_type)}: {item.copied_name}")
        section_lines.append("")
    if missing_media:
        section_lines.extend(["Saknade mediareferenser", ""])
        for entry in missing_media:
            section_lines.append(
                f"Saknad media: {entry.get('token_type', 'media')} ({entry.get('media_id', 'okänd')}, status: {entry.get('status', 'UNKNOWN')})"
            )
        section_lines.append("")
    if not section_lines:
        return content
    return content.rstrip() + "\n\n" + "\n".join(section_lines).rstrip() + "\n"


def build_course_name(course_folder: str, course_payload: dict[str, Any]) -> str:
    if course_folder in COURSE_NAME_OVERRIDES:
        return COURSE_NAME_OVERRIDES[course_folder]
    title = normalize_title(str(course_payload.get("title") or ""))
    return title or slug_like_to_title(course_folder)


def build_lesson_name(lesson_payload: dict[str, Any], lesson_folder: str) -> str:
    title = normalize_title(str(lesson_payload.get("title") or ""))
    if title:
        return title
    parts = lesson_folder.split("-", 2)
    if len(parts) == 3:
        return slug_like_to_title(parts[2])
    return slug_like_to_title(lesson_folder)


def build_summary_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Final courses summary",
        "",
        f"Generated at: {report['generated_at']}",
        "",
        f"Courses transformed: {report['counts']['courses']}",
        f"Lessons transformed: {report['counts']['lessons']}",
        f"Media files copied: {report['counts']['media_files_copied']}",
        f"Lessons with missing media in source: {report['counts']['lessons_with_missing_media']}",
        "",
        "Course folder mapping",
        "",
    ]
    for course in report["courses"]:
        lines.append(f"{course['original_folder']} -> {course['new_folder']}")
    lines.extend(["", "Lesson folder mapping", ""])
    for course in report["courses"]:
        lines.append(course["new_folder"])
        for lesson in course["lessons"]:
            lines.append(f"{lesson['original_folder']} -> {lesson['new_folder']}")
        lines.append("")
    lines.extend(["Media conflicts and duplicate files", ""])
    found_issue = False
    for course in report["courses"]:
        for lesson in course["lessons"]:
            if lesson["duplicate_media_groups"] or lesson["missing_media"]:
                found_issue = True
                lines.append(f"{course['new_folder']} / {lesson['new_folder']}")
                for duplicate in lesson["duplicate_media_groups"]:
                    lines.append(
                        f"duplicate-content-files: {duplicate['legacy_media_id']} -> {', '.join(duplicate['filenames'])}"
                    )
                for missing in lesson["missing_media"]:
                    lines.append(
                        f"missing-media: {missing['token_type']} {missing['media_id']} ({missing['status']})"
                    )
                lines.append("")
    if not found_issue:
        lines.extend(["No duplicate-content groups or media conflicts were found.", ""])
    if report.get("orphans"):
        lines.extend(
            [
                "Orphan media",
                "",
                f"{report['orphans']['original_folder']} -> {report['orphans']['new_folder']} ({report['orphans']['file_count']} files)",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    if not SOURCE_ROOT.is_dir():
        raise SystemExit(f"Missing source folder: {SOURCE_ROOT}")
    if TARGET_ROOT.exists():
        raise SystemExit(f"Target folder already exists: {TARGET_ROOT}")

    TARGET_ROOT.mkdir(parents=True, exist_ok=False)
    materialization_summary = read_json(SOURCE_ROOT / "materialization_summary.json")
    report: dict[str, Any] = {
        "schema": "aveli.final_courses.mapping.v1",
        "generated_at": iso_now(),
        "source_root": "courses",
        "target_root": "final_courses",
        "source_materialization_summary": "courses/materialization_summary.json",
        "counts": {
            "courses": 0,
            "lessons": 0,
            "media_files_copied": 0,
            "lessons_with_missing_media": 0,
        },
        "courses": [],
        "orphans": None,
    }

    course_limit_env = os.environ.get("FINAL_COURSES_LIMIT")
    course_limit = int(course_limit_env) if course_limit_env else None
    course_filter = os.environ.get("FINAL_COURSES_FILTER")
    source_courses = sorted(
        path
        for path in SOURCE_ROOT.iterdir()
        if path.is_dir() and path.name != "_orphans" and (not course_filter or course_filter in path.name)
    )
    if course_limit is not None:
        source_courses = source_courses[:course_limit]

    used_course_names: set[str] = set()
    for course_dir in source_courses:
        course_payload = read_json(course_dir / "course.json")
        new_course_name = ensure_unique_name(build_course_name(course_dir.name, course_payload), used_course_names, max_length=90)
        target_course_dir = TARGET_ROOT / new_course_name
        target_course_dir.mkdir(parents=True, exist_ok=False)

        lesson_reports: list[dict[str, Any]] = []
        course_manifest_lessons: list[dict[str, Any]] = []
        used_lesson_names: set[str] = set()
        lessons = sorted(course_payload.get("lessons") or [], key=lambda item: int(item.get("position") or 0))

        for lesson_payload in lessons:
            position = int(lesson_payload["position"])
            lesson_name = build_lesson_name(lesson_payload, str(lesson_payload["slug"]))
            new_lesson_folder = ensure_unique_name(f"lesson-{position:03d}-{lesson_name}", used_lesson_names, max_length=110)
            target_lesson_dir = target_course_dir / new_lesson_folder
            target_lesson_dir.mkdir(parents=True, exist_ok=False)

            source_lesson_path = REPO_ROOT / str(lesson_payload["path"])
            cleaned = clean_body_text(source_lesson_path.read_text(encoding="utf-8"))
            media_inventory, copied_media, duplicate_media_groups = copy_media_files(target_lesson_dir, lesson_payload, new_course_name)
            cleaned = replace_media_placeholders(cleaned, copied_media, lesson_payload.get("missing_media") or [])
            cleaned = append_media_section(cleaned, copied_media, lesson_payload.get("missing_media") or [])
            if any(token in cleaned for token in ("**", "__", "<!--", "[MEDIA:", "[MISSING MEDIA:", "!audio(", "!image(", "!video(")):
                raise RuntimeError(f"Markdown token remained in {source_lesson_path}")
            if re.search(r"(^|\n)\s*#{1,6}\s", cleaned):
                raise RuntimeError(f"Markdown heading remained in {source_lesson_path}")
            (target_lesson_dir / "content.md").write_text(cleaned, encoding="utf-8")

            report["counts"]["lessons"] += 1
            report["counts"]["media_files_copied"] += len(media_inventory)
            if lesson_payload.get("missing_media"):
                report["counts"]["lessons_with_missing_media"] += 1

            lesson_report = {
                "lesson_id": lesson_payload["lesson_id"],
                "position": position,
                "original_folder": lesson_payload["slug"],
                "new_folder": new_lesson_folder,
                "original_title": lesson_payload["title"],
                "new_title": lesson_name,
                "original_content_path": Path(str(lesson_payload["path"])).as_posix(),
                "new_content_path": Path("final_courses", new_course_name, new_lesson_folder, "content.md").as_posix(),
                "media_files_copied": media_inventory,
                "missing_media": lesson_payload.get("missing_media") or [],
                "duplicate_media_groups": duplicate_media_groups,
            }
            lesson_reports.append(lesson_report)
            course_manifest_lessons.append(
                {
                    "lesson_id": lesson_payload["lesson_id"],
                    "position": position,
                    "original_folder": lesson_payload["slug"],
                    "new_folder": new_lesson_folder,
                    "title": lesson_name,
                    "content_file": f"{new_lesson_folder}/content.md",
                    "media_files": media_inventory,
                    "missing_media": lesson_payload.get("missing_media") or [],
                }
            )

        write_json(
            target_course_dir / "course.json",
            {
                "schema": "aveli.final_courses.course_manifest.v1",
                "generated_at": report["generated_at"],
                "source_course_folder": course_dir.name,
                "source_course_json": f"courses/{course_dir.name}/course.json",
                "course": {
                    "id": course_payload["course_id"],
                    "original_folder": course_dir.name,
                    "new_folder": new_course_name,
                    "original_title": course_payload["title"],
                    "new_title": build_course_name(course_dir.name, course_payload),
                    "slug": course_payload["slug"],
                    "source_slug": course_payload.get("source_slug"),
                    "lesson_count": course_payload["lesson_count"],
                    "media_file_count": course_payload["media_file_count"],
                    "missing_media_count": course_payload["missing_media_count"],
                    "clean_state": course_payload["clean_state"],
                    "unrecoverable_count": course_payload.get("unrecoverable_count", 0),
                    "unresolved_non_deterministic_count": course_payload.get("unresolved_non_deterministic_count", 0),
                },
                "lessons": course_manifest_lessons,
            },
        )

        report["counts"]["courses"] += 1
        report["courses"].append(
            {
                "course_id": course_payload["course_id"],
                "original_folder": course_dir.name,
                "new_folder": new_course_name,
                "original_title": course_payload["title"],
                "new_title": build_course_name(course_dir.name, course_payload),
                "slug": course_payload["slug"],
                "clean_state": course_payload["clean_state"],
                "missing_media_count": course_payload["missing_media_count"],
                "lessons": lesson_reports,
            }
        )

    orphans_dir = SOURCE_ROOT / "_orphans"
    if orphans_dir.is_dir():
        target_orphans = TARGET_ROOT / "_orphans"
        shutil.copytree(orphans_dir, target_orphans)
        report["orphans"] = {
            "original_folder": "courses/_orphans",
            "new_folder": "final_courses/_orphans",
            "file_count": len([path for path in target_orphans.iterdir() if path.is_file()]),
        }

    write_json(REPORT_JSON, report)
    REPORT_MD.write_text(build_summary_markdown(report), encoding="utf-8")
    write_json(
        TARGET_ROOT / "final_courses.json",
        {
            "schema": "aveli.final_courses.index.v1",
            "generated_at": report["generated_at"],
            "source_materialization_summary": materialization_summary.get("generated_at"),
            "course_count": report["counts"]["courses"],
            "lesson_count": report["counts"]["lessons"],
            "media_files_copied": report["counts"]["media_files_copied"],
            "mapping_report": "mapping_report.json",
            "summary_report": "summary_report.md",
            "courses": [
                {
                    "course_id": course["course_id"],
                    "folder": course["new_folder"],
                    "title": course["new_title"],
                    "lesson_count": len(course["lessons"]),
                }
                for course in report["courses"]
            ],
        },
    )


if __name__ == "__main__":
    main()
