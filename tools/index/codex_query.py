#!/usr/bin/env python3

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"
SEARCH_SCRIPT = ROOT / "tools" / "index" / "search_code.py"

if Path(sys.executable).resolve() != REPO_PYTHON.resolve():
    if not REPO_PYTHON.exists():
        raise SystemExit(f"FEL: repo-Python saknas vid {REPO_PYTHON}")
    os.execv(str(REPO_PYTHON), [str(REPO_PYTHON), __file__, *sys.argv[1:]])

QUERY = " ".join(sys.argv[1:]).strip()

if not QUERY:
    print("FEL: Ingen fråga angavs")
    sys.exit(1)

# ---------------------------------------------------------
# STEP 1: SEARCH
# ---------------------------------------------------------

search = subprocess.run(
    [str(REPO_PYTHON), str(SEARCH_SCRIPT), "--json", QUERY],
    capture_output=True,
    text=True,
    cwd=str(ROOT),
)

if search.returncode != 0:
    sys.stderr.write(search.stderr or search.stdout)
    sys.exit(search.returncode or 1)

evidence = json.loads(search.stdout)
if not isinstance(evidence, list):
    raise SystemExit("FEL: kanonisk evidence-lista forvantades fran search_code.py")

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

clean_context = "\n\n".join(evidence_blocks)

# ---------------------------------------------------------
# STEP 2: BUILD PROMPT
# ---------------------------------------------------------

prompt = f"""
LOAD: codex/AVELI_OPERATING_SYSTEM.md

Before any action, reply exactly:
AVELI OPERATING SYSTEM LOADED

If missing → STOP

---

TASK:

Explain HOW the system enforces:

"{QUERY}"

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
   → what rule defines access

2. ENTRYPOINT (ROUTE)
   → where request enters system

3. SERVICE LOGIC
   → how access is checked

4. DB ENFORCEMENT
   → how database guarantees it

5. EXECUTION FLOW
   → full chain from request → access decision

---

CONSTRAINTS:

- DO NOT invent logic
- DO NOT generalize
- ONLY use provided context
- If something is missing → say UNKNOWN

---

REASONING MODE:

- Prefer execution over description
- Prefer code over docs
- Prefer enforcement over intention

---

VERIFICATION:

- Must follow LAW → ROUTE → SERVICE → DB
- Must describe actual control flow
"""

print(prompt.strip() + "\n")
