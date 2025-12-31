#!/usr/bin/env python3
"""Validate backend/.env against the allowlisted contract."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT_DIR / "backend" / ".env"
REQUIRED_KEYS_FILE = ROOT_DIR / "ENV_REQUIRED_KEYS.txt"
BACKEND_DIR = ROOT_DIR / "backend"

ENV_CALL_RE = re.compile(
    r"\b(?:os\.getenv|os\.environ\.get|os\.environ\.setdefault|environ\.get|getenv)\(\s*[\"\']([A-Z0-9_]+)[\"\']"
)
ENV_INDEX_RE = re.compile(r"\b(?:os\.environ|environ)\[\s*[\"\']([A-Z0-9_]+)[\"\']\s*\]")
SETTINGS_RE = re.compile(r"\bsettings\.([a-zA-Z_][a-zA-Z0-9_]*)")
PREFIX_RE = re.compile(
    r"_slug_to_env_key\([\s\S]*?prefix\s*=\s*[\"\']([A-Z0-9_]+)[\"\']"
)


def _die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_required_keys() -> tuple[set[str], set[str]]:
    if not REQUIRED_KEYS_FILE.exists():
        _die(f"Missing {REQUIRED_KEYS_FILE}")
    required: set[str] = set()
    prefixes: set[str] = set()
    for raw_line in REQUIRED_KEYS_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.endswith("*"):
            prefixes.add(line[:-1])
        else:
            required.add(line)
    return required, prefixes


def parse_env_file() -> dict[str, str]:
    if not ENV_FILE.exists():
        _die("backend/.env missing – create it from backend/.env.example")
    env: dict[str, str] = {}
    for raw_line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value and value[0] == value[-1] and value[0] in ("\"", "'"):
            value = value[1:-1]
        env[key] = value
    return env


def scan_backend_env_usage() -> tuple[set[str], set[str]]:
    referenced: set[str] = set()
    prefixes: set[str] = set()
    for path in BACKEND_DIR.rglob("*.py"):
        if ".venv" in path.parts or "__pycache__" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        referenced.update(ENV_CALL_RE.findall(text))
        referenced.update(ENV_INDEX_RE.findall(text))
        referenced.update(name.upper() for name in SETTINGS_RE.findall(text))
        prefixes.update(PREFIX_RE.findall(text))
    prefix_keys = {f"{prefix}_" for prefix in prefixes}
    return referenced, prefix_keys


def matches_allowed_prefix(value: str, prefixes: set[str]) -> bool:
    return any(value.startswith(prefix) for prefix in prefixes)


def main() -> None:
    required_keys, allowed_prefixes = load_required_keys()
    env_values = parse_env_file()
    referenced_keys, referenced_prefixes = scan_backend_env_usage()

    missing_required = sorted(
        key for key in required_keys if not env_values.get(key, "").strip()
    )

    unknown_refs = sorted(
        key
        for key in referenced_keys
        if key not in required_keys and not matches_allowed_prefix(key, allowed_prefixes)
    )

    unknown_prefixes = sorted(
        prefix
        for prefix in referenced_prefixes
        if not matches_allowed_prefix(prefix, allowed_prefixes)
    )

    print("==> Env contract check")
    print(f"Required keys: {len(required_keys)}")
    print(f"Referenced keys: {len(referenced_keys)}")

    if missing_required:
        print("Missing required keys in backend/.env:")
        for key in missing_required:
            print(f"  - {key}")

    if unknown_refs:
        print("Code references env keys not in ENV_REQUIRED_KEYS.txt:")
        for key in unknown_refs:
            print(f"  - {key}")

    if unknown_prefixes:
        print("Code references env key prefixes not in ENV_REQUIRED_KEYS.txt:")
        for prefix in unknown_prefixes:
            print(f"  - {prefix}*")

    if missing_required or unknown_refs or unknown_prefixes:
        raise SystemExit(1)

    print("Env contract check: PASS")


if __name__ == "__main__":
    main()
