import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"
INDEX_MANIFEST = ROOT / ".repo_index" / "index_manifest.json"

if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
    raise SystemExit(
        "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
        f"{CANONICAL_SEARCH_PYTHON}"
    )

if not INDEX_MANIFEST.exists():
    raise SystemExit(f"FEL: indexmanifest saknas vid {INDEX_MANIFEST}")

index_manifest = json.loads(INDEX_MANIFEST.read_text(encoding="utf-8"))

lines = sys.stdin.read().splitlines()

results = []
current = {}

for line in lines:

    if line.startswith("[SIMILARITY"):
        if "file" in current:
            results.append(current)
        current = {}

    elif line.startswith("FILE:"):
        current["file"] = line.replace("FILE:", "").strip()

    elif line.startswith("-" * 10):
        continue

    else:
        current.setdefault("content", []).append(line)

if "file" in current:
    results.append(current)

# ---------------------------------------------------------
# CLASSIFY
# ---------------------------------------------------------

def classify(path):
    lowered = path.lower()
    classification_rules = index_manifest.get("classification_rules", {})

    for rule in classification_rules.get("precedence", []):
        rule_type = rule.get("type")
        value = str(rule.get("value", "")).lower()
        layer = str(rule.get("layer", "")).upper()

        if rule_type == "path_substring" and value in lowered:
            return layer
        if rule_type == "path_suffix" and lowered.endswith(value):
            return layer

    return str(classification_rules.get("default_layer", "OTHER")).upper()

grouped = defaultdict(list)

for r in results:
    file_path = r.get("file")
    if not file_path:
        continue

    grouped[classify(file_path)].append(r)

# ---------------------------------------------------------
# CLEAN CONTENT
# ---------------------------------------------------------

def clean_block(text):
    return text.rstrip()

# ---------------------------------------------------------
# OUTPUT
# ---------------------------------------------------------

print("\n================ ANALYSIS ================\n")

def print_block(title):

    if not grouped.get(title):
        return

    print(f"{title}:\n")

    for r in grouped[title]:
        print(f"- {r['file']}\n")

        content = "\n".join(r.get("content", []))
        content = clean_block(content)

        print(content)
        print("\n")

print_block("LAW")
print_block("ROUTE")
print_block("SERVICE")
print_block("DB")

# ---------------------------------------------------------
# EXECUTION FLOW
# ---------------------------------------------------------

print("\n================ EXECUTION FLOW ================\n")

flow = []

if grouped.get("LAW"):
    flow.append("SYSTEM LAW")

if grouped.get("ROUTE"):
    flow.append("ENTRYPOINT")

if grouped.get("SERVICE"):
    flow.append("SERVICE LOGIC")

if grouped.get("DB"):
    flow.append("DB ENFORCEMENT")

print(" → ".join(flow))
print()
