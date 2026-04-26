import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"
SEARCH_SCRIPT = ROOT / "tools" / "index" / "search_code.py"


def require_canonical_interpreter() -> None:
    if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
        raise SystemExit(
            "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
            f"{CANONICAL_SEARCH_PYTHON}"
        )


def configure_utf8_stdio(stdout=None, stderr=None) -> None:
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    os.environ.setdefault("PYTHONUTF8", "1")
    stdout = sys.stdout if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    for stream in (stdout, stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8")


def run_search(query: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(CANONICAL_SEARCH_PYTHON), str(SEARCH_SCRIPT), "--json", query],
        capture_output=True,
        text=True,
        encoding="utf-8",
        cwd=str(ROOT),
    )


def load_evidence(search_stdout: str) -> list[dict]:
    evidence = json.loads(search_stdout)
    if not isinstance(evidence, list):
        raise SystemExit("FEL: kanonisk evidence-lista forvantades fran search_code.py")
    return evidence


def build_evidence_context(evidence: list[dict]) -> str:
    evidence_blocks = []
    for index, entry in enumerate(evidence, start=1):
        evidence_blocks.append(
            "\n".join(
                [
                    f"EVIDENCE {index}",
                    f"FILE: {entry['file']}",
                    f"LAYER: {entry['layer']}",
                    f"SOURCE_TYPE: {entry['source_type']}",
                    f"SCORE: {entry['score']}",
                    "SNIPPET:",
                    str(entry["snippet"]),
                ]
            )
        )
    return "\n\n".join(evidence_blocks)


def build_prompt(query: str, evidence: list[dict]) -> str:
    clean_context = build_evidence_context(evidence)
    return f"""
LOAD: codex/AVELI_OPERATING_SYSTEM.md

Before any action, reply exactly:
AVELI OPERATING SYSTEM LOADED

If missing -> STOP

---

TASK:

Explain HOW the system enforces:

"{query}"

---

IMPORTANT:

This is NOT a conceptual explanation.

This is a SYSTEM EXECUTION explanation.

---

CONTEXT (canonical evidence objects):

{clean_context}

---

EXPECTED OUTPUT STRUCTURE:

1. SYSTEM LAW
   -> what rule defines access

2. ENTRYPOINT (ROUTE)
   -> where request enters system

3. SERVICE LOGIC
   -> how access is checked

4. DB ENFORCEMENT
   -> how database guarantees it

5. EXECUTION FLOW
   -> full chain from request -> access decision

---

CONSTRAINTS:

- DO NOT invent logic
- DO NOT generalize
- ONLY use provided context
- If something is missing -> say UNKNOWN

---

REASONING MODE:

- Prefer execution over description
- Prefer code over docs
- Prefer enforcement over intention

---

VERIFICATION:

- Must follow LAW -> ROUTE -> SERVICE -> DB
- Must describe actual control flow
""".strip() + "\n"


def main(argv: list[str] | None = None) -> int:
    require_canonical_interpreter()
    configure_utf8_stdio()

    args = sys.argv[1:] if argv is None else argv
    query = " ".join(args).strip()
    if not query:
        print("FEL: Ingen fraga angavs")
        return 1

    search = run_search(query)
    if search.returncode != 0:
        sys.stderr.write(search.stderr or search.stdout)
        return search.returncode or 1

    evidence = load_evidence(search.stdout)
    sys.stdout.write(build_prompt(query, evidence))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
