#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


SLOT_RE = re.compile(r"^(?P<slot>\d{4})_(?P<label>.+)\.sql$")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fail(message: str) -> int:
    print(f"baseline-freeze: FAIL - {message}", file=sys.stderr)
    return 1


def _load_manifest(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(_fail(f"manifest missing: {path}")) from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(_fail(f"manifest is not valid JSON: {path} ({exc})")) from exc
    return data


def _scan_baseline_dir(baseline_dir: Path) -> list[dict]:
    if not baseline_dir.is_dir():
        raise SystemExit(_fail(f"baseline directory missing: {baseline_dir}"))

    entries: list[dict] = []
    bad_names: list[str] = []
    for path in sorted(baseline_dir.iterdir()):
        if path.is_dir():
            bad_names.append(path.name)
            continue
        match = SLOT_RE.match(path.name)
        if match is None:
            bad_names.append(path.name)
            continue
        entries.append(
            {
                "slot": int(match.group("slot")),
                "filename": path.name,
                "path": path,
                "sha256": _sha256(path),
            }
        )

    if bad_names:
        raise SystemExit(
            _fail(
                "unexpected non-slot entries in baseline directory: "
                + ", ".join(sorted(bad_names))
            )
        )
    return entries


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Verify that protected baseline slots remain immutable and that only "
            "append-only additions above the protected range are present."
        )
    )
    parser.add_argument(
        "--manifest",
        default="backend/supabase/baseline_slots.lock.json",
        help="Path to the checked-in lock manifest.",
    )
    parser.add_argument(
        "--baseline-dir",
        default="backend/supabase/baseline_slots",
        help="Directory containing baseline slot SQL files.",
    )
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    baseline_dir = Path(args.baseline_dir)
    manifest = _load_manifest(manifest_path)

    protected_min_slot = int(manifest.get("protected_min_slot", 1))
    protected_max_slot = int(manifest["protected_max_slot"])
    manifest_slots = list(manifest.get("slots") or [])
    expected_sequence = list(range(protected_min_slot, protected_max_slot + 1))

    actual_manifest_sequence = [int(item["slot"]) for item in manifest_slots]
    if actual_manifest_sequence != expected_sequence:
        return _fail(
            "manifest protected range is not contiguous: "
            f"expected {expected_sequence}, got {actual_manifest_sequence}"
        )

    manifest_by_slot = {int(item["slot"]): item for item in manifest_slots}
    manifest_filenames = {item["filename"] for item in manifest_slots}

    current_entries = _scan_baseline_dir(baseline_dir)
    current_slots = [int(item["slot"]) for item in current_entries]
    if current_slots != sorted(current_slots):
        return _fail("slot ordering is not ascending")
    if len(current_slots) != len(set(current_slots)):
        duplicates = sorted(
            {
                slot
                for slot in current_slots
                if current_slots.count(slot) > 1
            }
        )
        return _fail(f"duplicate slot numbers detected: {duplicates}")

    current_by_slot = {int(item["slot"]): item for item in current_entries}

    protected_entries = [item for item in current_entries if item["slot"] <= protected_max_slot]
    protected_slots = [int(item["slot"]) for item in protected_entries]
    if protected_slots != expected_sequence:
        return _fail(
            "protected slot range has gaps, renumbering, or unexpected additions: "
            f"expected {expected_sequence}, got {protected_slots}"
        )

    for slot in expected_sequence:
        manifest_entry = manifest_by_slot[slot]
        current_entry = current_by_slot.get(slot)
        if current_entry is None:
            return _fail(
                f"protected slot missing or moved out of baseline dir: "
                f"{manifest_entry['filename']}"
            )
        if current_entry["filename"] != manifest_entry["filename"]:
            return _fail(
                f"protected slot renamed: expected {manifest_entry['filename']}, "
                f"got {current_entry['filename']}"
            )
        if current_entry["sha256"] != manifest_entry["sha256"]:
            return _fail(
                f"protected slot content changed: {manifest_entry['filename']} "
                f"(expected {manifest_entry['sha256']}, got {current_entry['sha256']})"
            )

    unexpected_protected = sorted(
        item["filename"]
        for item in protected_entries
        if item["filename"] not in manifest_filenames
    )
    if unexpected_protected:
        return _fail(
            "unexpected protected-range files detected: " + ", ".join(unexpected_protected)
        )

    append_only_entries = [item for item in current_entries if item["slot"] > protected_max_slot]
    append_only_slots = [int(item["slot"]) for item in append_only_entries]
    if append_only_slots != sorted(append_only_slots):
        return _fail("append-only slot ordering is not ascending")

    append_only_count = len(append_only_entries)
    highest_slot = max(current_slots) if current_slots else protected_max_slot
    print(
        "baseline-freeze: PASS - protected slots "
        f"{protected_min_slot:04d}-{protected_max_slot:04d} unchanged; "
        f"append-only additions detected: {append_only_count}; highest slot: {highest_slot:04d}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
