import json
import sys
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"
INDEX_MANIFEST = ROOT / ".repo_index" / "index_manifest.json"


def require_canonical_interpreter() -> None:
    if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
        raise SystemExit(
            "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
            f"{CANONICAL_SEARCH_PYTHON}"
        )


def load_index_manifest(path: Path = INDEX_MANIFEST) -> dict:
    if not path.exists():
        raise SystemExit(f"FEL: indexmanifest saknas vid {path}")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise SystemExit(f"FEL: indexmanifest maste vara JSON-objekt vid {path}")
    return manifest


def is_result_marker(line: str) -> bool:
    return line.startswith("[SIMILARITET") or line.startswith("[SIMILARITY")


def parse_file_marker(line: str) -> str | None:
    if line.startswith("FIL:") or line.startswith("FILE:"):
        return line.split(":", 1)[1].strip()
    return None


def parse_results_text(text: str) -> list[dict]:
    results = []
    current: dict = {}

    for line in text.splitlines():
        if is_result_marker(line):
            if "file" in current:
                results.append(current)
            current = {"content": []}
            continue

        file_path = parse_file_marker(line)
        if file_path is not None:
            current["file"] = file_path
            continue

        if line.startswith("-" * 10):
            continue

        if current:
            current.setdefault("content", []).append(line)

    if "file" in current:
        results.append(current)
    return results


def classify(path: str, index_manifest: dict) -> str:
    lowered = path.lower()
    classification_policy = index_manifest.get("classification_policy")
    if not isinstance(classification_policy, dict):
        raise SystemExit("FEL: classification_policy saknas i indexmanifestet")

    for rule in classification_policy.get("precedence", []):
        rule_type = rule.get("type")
        value = str(rule.get("value", "")).lower()
        layer = str(rule.get("layer", "")).upper()

        if rule_type == "path_substring" and value in lowered:
            return layer
        if rule_type == "path_suffix" and lowered.endswith(value):
            return layer

    return str(classification_policy.get("default_layer", "OTHER")).upper()


def clean_block(text: str) -> str:
    return text.rstrip()


def group_results(results: list[dict], index_manifest: dict) -> dict[str, list[dict]]:
    grouped = defaultdict(list)
    for result in results:
        file_path = result.get("file")
        if not file_path:
            continue
        grouped[classify(file_path, index_manifest)].append(result)
    return grouped


def render_block(title: str, grouped: dict[str, list[dict]]) -> str:
    if not grouped.get(title):
        return ""

    lines = [f"{title}:", ""]
    for result in grouped[title]:
        lines.append(f"- {result['file']}")
        lines.append("")
        lines.append(clean_block("\n".join(result.get("content", []))))
        lines.append("")
        lines.append("")
    return "\n".join(lines)


def render_analysis(results: list[dict], index_manifest: dict) -> str:
    grouped = group_results(results, index_manifest)
    lines = ["", "================ ANALYSIS ================", ""]

    for title in ("LAW", "ROUTE", "SERVICE", "DB"):
        block = render_block(title, grouped)
        if block:
            lines.append(block)

    lines.extend(["", "================ EXECUTION FLOW ================", ""])
    flow = []
    if grouped.get("LAW"):
        flow.append("SYSTEM LAW")
    if grouped.get("ROUTE"):
        flow.append("ENTRYPOINT")
    if grouped.get("SERVICE"):
        flow.append("SERVICE LOGIC")
    if grouped.get("DB"):
        flow.append("DB ENFORCEMENT")
    lines.append(" -> ".join(flow))
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    require_canonical_interpreter()
    index_manifest = load_index_manifest()
    results = parse_results_text(sys.stdin.read())
    sys.stdout.write(render_analysis(results, index_manifest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
