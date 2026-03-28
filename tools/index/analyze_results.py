#!/usr/bin/env python3

import os
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_PYTHON = ROOT / ".venv" / "bin" / "python"

if Path(sys.executable).resolve() != REPO_PYTHON.resolve():
    if not REPO_PYTHON.exists():
        raise SystemExit(f"Missing repo python interpreter: {REPO_PYTHON}")
    os.execv(str(REPO_PYTHON), [str(REPO_PYTHON), __file__, *sys.argv[1:]])

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
    p = path.lower()

    if "decisions" in p:
        return "LAW"
    if "routes" in p:
        return "ROUTE"
    if "services" in p:
        return "SERVICE"
    if ".sql" in p:
        return "DB"
    if "repositories" in p:
        return "REPO"

    return "OTHER"

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
    lines = text.split("\n")

    cleaned = []
    for l in lines:
        l = l.strip()

        if not l:
            continue

        if l.startswith("import "):
            continue

        cleaned.append(l)

    return "\n".join(cleaned[:40])  # 🔥 max 40 rader per block

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
