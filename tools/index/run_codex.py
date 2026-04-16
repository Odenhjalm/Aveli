import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"
CODEX_QUERY_SCRIPT = ROOT / "tools" / "index" / "codex_query.py"
VALIDATE_SCRIPT = ROOT / "tools" / "index" / "validate_codex.py"

if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
        f"{CANONICAL_SEARCH_PYTHON}"
    )

QUERY = " ".join(sys.argv[1:]).strip()

if not QUERY:
    print("FEL: Ingen fråga angavs")
    sys.exit(1)

# ---------------------------------------------------------
# STEP 1: BUILD PROMPT
# ---------------------------------------------------------

prompt_proc = subprocess.run(
    [str(CANONICAL_SEARCH_PYTHON), str(CODEX_QUERY_SCRIPT), QUERY],
    capture_output=True,
    text=True,
    cwd=str(ROOT),
)

if prompt_proc.returncode != 0:
    sys.stderr.write(prompt_proc.stderr or prompt_proc.stdout)
    sys.exit(prompt_proc.returncode or 1)

prompt = prompt_proc.stdout

print("\n================ PROMPT GENERERAD ================\n")
print(prompt)

# ---------------------------------------------------------
# STEP 2: WAIT FOR CODEX RESPONSE
# ---------------------------------------------------------

print("\n================ KLISTRA IN CODEX-SVAR ================\n")
print("(Avsluta med CTRL+D)\n")

response = sys.stdin.read()

if not response.strip():
    print("FEL: Inget svar angavs")
    sys.exit(1)

# ---------------------------------------------------------
# STEP 3: VALIDATE RESPONSE
# ---------------------------------------------------------

validation = subprocess.run(
    [str(CANONICAL_SEARCH_PYTHON), str(VALIDATE_SCRIPT)],
    input=response,
    capture_output=True,
    text=True,
    cwd=str(ROOT),
)

if validation.returncode != 0:
    sys.stderr.write(validation.stderr or validation.stdout)
    sys.exit(validation.returncode or 1)

print("\n================ VALIDERING ================\n")
print(validation.stdout)

if "UNDERKÄND" in validation.stdout:
    print("\nSVAR UNDERKÄNDES I VALIDERING")
else:
    print("\nSVAR GODKÄNDES")
