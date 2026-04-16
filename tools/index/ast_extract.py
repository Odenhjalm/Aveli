import ast
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]

QUERY_SOURCE_ACCESS_FORBIDDEN = "SOURCE ACCESS FORBIDDEN IN QUERY MODE"
OFFLINE_EVIDENCE_REQUIRED = "CANONICAL OFFLINE EVIDENCE REQUIRED FOR AST EXTRACTION"
CANONICAL_EVIDENCE_FIELDS = {"file", "layer", "snippet", "source_type", "score"}
CANONICAL_SOURCE_TYPES = {"chunk", "ast", "context"}


def normalize_repo_relative_path(file_path: str) -> str:
    path = Path(file_path)
    if path.is_absolute() or ".." in path.parts:
        raise RuntimeError("FEL: evidence file maste vara repo-relativ och normaliserad")
    normalized = Path(path.as_posix()).as_posix().lstrip("./")
    if not normalized or "\\" in normalized:
        raise RuntimeError("FEL: evidence file maste anvanda repo-relativ forward slash")
    return normalized


def validate_canonical_evidence(
    evidence: dict[str, Any] | None,
    file_path: str,
    snippet: str,
) -> dict[str, Any]:
    if not isinstance(evidence, dict):
        raise RuntimeError(OFFLINE_EVIDENCE_REQUIRED)
    if set(evidence) != CANONICAL_EVIDENCE_FIELDS:
        raise RuntimeError("FEL: canonical evidence har fel faltuppsattning")

    normalized_file = normalize_repo_relative_path(file_path)
    evidence_file = normalize_repo_relative_path(str(evidence["file"]))
    if evidence_file != normalized_file:
        raise RuntimeError("FEL: evidence file matchar inte begart file_path")
    if str(evidence["snippet"]) != snippet:
        raise RuntimeError("FEL: evidence snippet matchar inte begard snippet")
    if str(evidence["source_type"]) not in CANONICAL_SOURCE_TYPES:
        raise RuntimeError("FEL: evidence source_type ar inte kanonisk")
    if not isinstance(evidence["score"], (int, float)):
        raise RuntimeError("FEL: evidence score maste vara numerisk")
    if not snippet:
        raise RuntimeError("FEL: evidence snippet far inte vara tom")
    return evidence


def validate_manifest_binding(
    evidence: dict[str, Any],
    index_manifest: dict[str, Any] | None,
    chunk_records: list[dict[str, Any]] | None,
) -> str:
    if not isinstance(index_manifest, dict):
        raise RuntimeError(OFFLINE_EVIDENCE_REQUIRED)
    corpus = index_manifest.get("corpus")
    if not isinstance(corpus, dict):
        raise RuntimeError("FEL: index_manifest corpus saknas")
    files = corpus.get("files")
    if not isinstance(files, list):
        raise RuntimeError("FEL: index_manifest corpus.files saknas")

    evidence_file = normalize_repo_relative_path(str(evidence["file"]))
    normalized_files = [normalize_repo_relative_path(str(entry)) for entry in files]
    if evidence_file not in normalized_files:
        raise RuntimeError("FEL: evidence file saknas i index_manifest corpus.files")

    if not isinstance(chunk_records, list) or not chunk_records:
        raise RuntimeError(OFFLINE_EVIDENCE_REQUIRED)

    snippet = str(evidence["snippet"])
    for record in chunk_records:
        if normalize_repo_relative_path(str(record.get("file", ""))) != evidence_file:
            continue
        canonical_chunk_text = record.get("text")
        if not isinstance(canonical_chunk_text, str):
            continue
        if snippet in canonical_chunk_text:
            return evidence_file

    raise RuntimeError("FEL: evidence snippet saknas i canonical chunk artifact")


def read_manifest_bound_source(normalized_file: str) -> str:
    source_path = (ROOT / normalized_file).resolve()
    root = ROOT.resolve()
    try:
        source_path.relative_to(root)
    except ValueError as exc:
        raise RuntimeError("FEL: evidence file ligger utanfor repo-root") from exc
    if not source_path.exists() or not source_path.is_file():
        raise RuntimeError("FEL: evidence source file saknas")
    try:
        return source_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError("FEL: evidence source file maste vara UTF-8") from exc


def extract_functions(
    file_path: str,
    snippet: str,
    *,
    mode: str = "query",
    evidence: dict[str, Any] | None = None,
    index_manifest: dict[str, Any] | None = None,
    chunk_records: list[dict[str, Any]] | None = None,
) -> str:
    if mode != "audit":
        raise RuntimeError(QUERY_SOURCE_ACCESS_FORBIDDEN)

    canonical_evidence = validate_canonical_evidence(evidence, file_path, snippet)
    normalized_file = validate_manifest_binding(
        canonical_evidence,
        index_manifest,
        chunk_records,
    )
    source = read_manifest_bound_source(normalized_file)
    if snippet not in source:
        raise RuntimeError("FEL: evidence snippet kan inte harledas fran source file")

    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        raise RuntimeError("FEL: AST-extraktion kraver parsbar source") from exc

    matches: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        func_source = ast.get_source_segment(source, node)
        if isinstance(func_source, str) and snippet in func_source:
            matches.append(func_source)

    if not matches:
        raise RuntimeError("FEL: canonical snippet kunde inte harledas till AST-funktion")

    unique: list[str] = []
    seen: set[str] = set()
    for item in matches:
        if item in seen:
            continue
        seen.add(item)
        unique.append(item)

    return "\n\n".join(unique)
