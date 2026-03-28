#!/usr/bin/env python3

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"
SEARCH_SCRIPT = ROOT / "tools" / "index" / "search_code.py"
ANALYZE_SCRIPT = ROOT / "tools" / "index" / "analyze_results.py"

if Path(sys.executable).resolve() != REPO_PYTHON.resolve():
    if not REPO_PYTHON.exists():
        raise SystemExit(f"Missing repo python interpreter: {REPO_PYTHON}")
    os.execv(str(REPO_PYTHON), [str(REPO_PYTHON), __file__, *sys.argv[1:]])

QUERY = " ".join(sys.argv[1:]).strip()

if not QUERY:
    print("ERROR: No query provided")
    sys.exit(1)

# ---------------------------------------------------------
# STEP 1: SEARCH
# ---------------------------------------------------------

search = subprocess.run(
    [str(REPO_PYTHON), str(SEARCH_SCRIPT), QUERY],
    capture_output=True,
    text=True,
    cwd=str(ROOT),
)

if search.returncode != 0:
    sys.stderr.write(search.stderr or search.stdout)
    sys.exit(search.returncode or 1)

# ---------------------------------------------------------
# STEP 2: ANALYSIS
# ---------------------------------------------------------

analysis = subprocess.run(
    [str(REPO_PYTHON), str(ANALYZE_SCRIPT)],
    input=search.stdout,
    capture_output=True,
    text=True,
    cwd=str(ROOT),
)

if analysis.returncode != 0:
    sys.stderr.write(analysis.stderr or analysis.stdout)
    sys.exit(analysis.returncode or 1)

raw_analysis = analysis.stdout.splitlines()

# ---------------------------------------------------------
# STEP 3: CLEAN CONTEXT
# ---------------------------------------------------------

clean_lines = []
skip_section = False

for line in raw_analysis:

    # ta bort OTHER helt
    if line.strip().startswith("--- OTHER ---"):
        skip_section = True
        continue

    if skip_section:
        if line.strip().startswith("---"):
            skip_section = False
        else:
            continue

    # ta bort "passage:"
    if "passage:" in line:
        line = line.replace("passage:", "").strip()

    # trimma SQL brus
    if "create policy" in line.lower():
        line = line[:120] + "..."

    clean_lines.append(line)

clean_context = "\n".join(clean_lines)

# ---------------------------------------------------------
# STEP 4: BUILD PROMPT
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

CONTEXT (verified retrieval + analysis):

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

print("\n================ CODEX PROMPT ================\n")
print(prompt)
