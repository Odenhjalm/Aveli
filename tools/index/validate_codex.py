import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"

if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
        f"{CANONICAL_SEARCH_PYTHON}"
    )

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
