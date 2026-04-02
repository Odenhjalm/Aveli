#!/usr/bin/env python3

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"

if Path(sys.executable).resolve() != REPO_PYTHON.resolve():
    if not REPO_PYTHON.exists():
        raise SystemExit(f"FEL: repo-Python saknas vid {REPO_PYTHON}")
    os.execv(str(REPO_PYTHON), [str(REPO_PYTHON), __file__, *sys.argv[1:]])

text = sys.stdin.read().lower()

# ---------------------------------------------------------
# RULES
# ---------------------------------------------------------

required_sections = [
    "system law",
    "entrypoint",
    "service",
    "db",
    "execution flow",
]

missing = []

for section in required_sections:
    if section not in text:
        missing.append(section)

# ---------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------

print("Valideringsrapport:\n")

if missing:
    print("UNDERKÄND")
    print("\nSaknade sektioner:")
    for m in missing:
        print("-", m)
else:
    print("GODKÄND")

# ---------------------------------------------------------
# STRUCTURE CHECK
# ---------------------------------------------------------

if "execution flow" in text:
    if "→" not in text and "->" not in text:
        print("\nVARNING: Ingen explicit exekveringskedja upptäcktes")
