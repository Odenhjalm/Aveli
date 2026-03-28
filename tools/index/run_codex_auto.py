#!/usr/bin/env python3

import os
import sys
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"
CODEX_QUERY_SCRIPT = ROOT / "tools" / "index" / "codex_query.py"
VALIDATE_SCRIPT = ROOT / "tools" / "index" / "validate_codex.py"

if Path(sys.executable).resolve() != REPO_PYTHON.resolve():
    if not REPO_PYTHON.exists():
        raise SystemExit(f"Missing repo python interpreter: {REPO_PYTHON}")
    os.execv(str(REPO_PYTHON), [str(REPO_PYTHON), __file__, *sys.argv[1:]])

from openai import OpenAI

# ---------------------------------------------------------
# CONFIG
# ---------------------------------------------------------

MODEL = "gpt-5"  # eller annan codex-modell
MAX_RETRIES = 2

def load_env_value(key: str) -> str | None:
    candidates = (
        ROOT / ".env",
        ROOT / ".env.local",
        ROOT / "backend" / ".env",
        ROOT / "backend" / ".env.local",
    )
    for path in candidates:
        if not path.exists():
            continue
        for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):].strip()
            if "=" not in line:
                continue
            env_key, value = line.split("=", 1)
            if env_key.strip() != key:
                continue
            value = value.strip()
            if value and value[0] == value[-1] and value[0] in ("'", "\""):
                value = value[1:-1]
            if value:
                os.environ.setdefault(key, value)
                return value
    return None


api_key = os.getenv("OPENAI_API_KEY") or load_env_value("OPENAI_API_KEY")
if not api_key:
    print("ERROR: OPENAI_API_KEY is required")
    sys.exit(1)

client = OpenAI(api_key=api_key)

QUERY = " ".join(sys.argv[1:]).strip()

if not QUERY:
    print("ERROR: No query provided")
    sys.exit(1)

# ---------------------------------------------------------
# STEP 1: BUILD PROMPT
# ---------------------------------------------------------

prompt_proc = subprocess.run(
    [str(REPO_PYTHON), str(CODEX_QUERY_SCRIPT), QUERY],
    capture_output=True,
    text=True,
    cwd=str(ROOT),
)

if prompt_proc.returncode != 0:
    sys.stderr.write(prompt_proc.stderr or prompt_proc.stdout)
    sys.exit(prompt_proc.returncode or 1)

prompt = prompt_proc.stdout

print("\n================ PROMPT =================\n")
print(prompt[:800] + "\n...")

# ---------------------------------------------------------
# LOOP
# ---------------------------------------------------------

for attempt in range(1, MAX_RETRIES + 1):

    print(f"\n================ CODEX RUN {attempt} =================\n")

    try:
        response = client.responses.create(
            model=MODEL,
            input=prompt,
        )

        output = response.output_text

    except Exception as e:
        print("ERROR calling Codex:", e)
        sys.exit(1)

    print("\n================ RESPONSE =================\n")
    print(output[:1500] + "\n...")

    # -----------------------------------------------------
    # VALIDATION
    # -----------------------------------------------------

    validation = subprocess.run(
        [str(REPO_PYTHON), str(VALIDATE_SCRIPT)],
        input=output,
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )

    if validation.returncode != 0:
        sys.stderr.write(validation.stderr or validation.stdout)
        sys.exit(validation.returncode or 1)

    print("\n================ VALIDATION =================\n")
    print(validation.stdout)

    if "PASS" in validation.stdout:
        print("\n✅ SUCCESS")
        break

    else:
        print("\n❌ FAILED → retrying...\n")

        # gör prompt hårdare vid retry
        prompt += "\n\nIMPORTANT: Your previous answer FAILED validation. Fix missing structure.\n"

else:
    print("\n🚨 MAX RETRIES REACHED")
