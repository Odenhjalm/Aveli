from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


CANONICAL_INTERPRETER_RELATIVE = ".repo_index/.search_venv/Scripts/python.exe"
D01_RESULT_DIR_RELATIVE = "actual_truth/DETERMINED_TASKS/retrieval_index_environment_dependencies"
D01_RESULT_PREFIX = "D01_environment_dependency_result_"
D01_RESULT_BUILD_ID_ENV = "AVELI_ENVIRONMENT_DEPENDENCY_BUILD_ID"
D01_RESULT_ARTIFACT_ENV = "AVELI_ENVIRONMENT_DEPENDENCY_RESULT_ARTIFACT"
D01_APPROVAL_PHRASE = "APPROVE AVELI OFFLINE DEPENDENCY PREPARATION"

DIRECT_REQUIRED_PACKAGES = ("chromadb", "numpy", "sentence-transformers", "tqdm")
DIRECT_IMPORTS = {
    "chromadb": "chromadb",
    "numpy": "numpy",
    "sentence-transformers": "sentence_transformers",
    "tqdm": "tqdm",
}
BOOTSTRAP_PACKAGE_NAMES = {"pip", "setuptools", "wheel"}

REQUIRED_APPROVAL_FIELDS = {
    "artifact_type",
    "approval_state",
    "approval_phrase",
    "approval_scope",
    "repo_root",
    "build_id",
    "target_interpreter_path",
    "e01_result",
    "b01_blocked_result",
    "package_set",
    "package_versions",
    "package_hashes",
    "package_source_policy",
    "network_policy",
    "fallback_policy",
    "verification_policy",
    "forbidden_targets",
}

REQUIRED_RESULT_FIELDS = {
    "artifact_type",
    "controller_scope",
    "task_id",
    "mode",
    "status",
    "build_id",
    "approval_artifact",
    "repo_root",
    "target_interpreter_path",
    "e01_result",
    "b01_blocked_result",
    "started_at_utc",
    "completed_at_utc",
    "dependency_preparation_attempted",
    "package_source_verification",
    "package_hash_verification",
    "installed_package_verification",
    "import_readiness_verification",
    "network_verification",
    "fallback_verification",
    "forbidden_side_effect_check",
    "failure",
}


class DependencyAuthorityError(RuntimeError):
    pass


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_json_object(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def package_name(name: object) -> str:
    if not isinstance(name, str) or not name.strip():
        raise DependencyAuthorityError("FEL: paketnamn maste vara en icke-tom strang")
    return name.strip().lower().replace("_", "-")


def display_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def path_key(path: Path) -> str:
    return os.path.normcase(str(path.resolve())).replace("\\", "/").rstrip("/")


def validate_build_id(raw_build_id: object) -> str:
    if not isinstance(raw_build_id, str):
        raise DependencyAuthorityError("FEL: build_id maste vara sha256-hex")
    build_id = raw_build_id.strip()
    if len(build_id) != 64 or any(char not in "0123456789abcdef" for char in build_id):
        raise DependencyAuthorityError("FEL: build_id maste vara 64 tecken lowercase sha256-hex")
    return build_id


def validate_sha256(value: object, field_name: str) -> str:
    if not isinstance(value, str):
        raise DependencyAuthorityError(f"FEL: {field_name} maste vara sha256-hex")
    digest = value.strip()
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise DependencyAuthorityError(f"FEL: {field_name} maste vara 64 tecken lowercase sha256-hex")
    if digest == "0" * 64:
        raise DependencyAuthorityError(f"FEL: {field_name} far inte vara placeholderhash")
    return digest


def validate_version(value: object, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise DependencyAuthorityError(f"FEL: {field_name} maste vara en exakt version")
    version = value.strip()
    if any(token in version for token in ("<", ">", "=", "~", "*", ",")):
        raise DependencyAuthorityError(f"FEL: {field_name} far inte vara flytande")
    if version.lower() == "latest" or version.lower().endswith(".x"):
        raise DependencyAuthorityError(f"FEL: {field_name} far inte vara flytande")
    if any(char.isspace() for char in version):
        raise DependencyAuthorityError(f"FEL: {field_name} far inte innehalla whitespace")
    return version


def require_object(container: dict, field_name: str, owner: str) -> dict:
    value = container.get(field_name)
    if not isinstance(value, dict):
        raise DependencyAuthorityError(f"FEL: {owner}.{field_name} maste vara ett JSON-objekt")
    return value


def require_string(container: dict, field_name: str, owner: str) -> str:
    value = container.get(field_name)
    if not isinstance(value, str) or not value.strip():
        raise DependencyAuthorityError(f"FEL: {owner}.{field_name} maste vara en icke-tom strang")
    return value.strip()


def require_bool(container: dict, field_name: str, owner: str) -> bool:
    value = container.get(field_name)
    if not isinstance(value, bool):
        raise DependencyAuthorityError(f"FEL: {owner}.{field_name} maste vara boolean")
    return value


def require_list(container: dict, field_name: str, owner: str) -> list:
    value = container.get(field_name)
    if not isinstance(value, list):
        raise DependencyAuthorityError(f"FEL: {owner}.{field_name} maste vara en lista")
    return value


def load_json_object(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise DependencyAuthorityError(f"FEL: ogiltig JSON i {path}") from exc
    if not isinstance(data, dict):
        raise DependencyAuthorityError(f"FEL: JSON-objekt forvantas i {path}")
    return data


def normalize_repo_relative_path(path_text: str, field_name: str) -> str:
    if not isinstance(path_text, str) or not path_text.strip():
        raise DependencyAuthorityError(f"FEL: {field_name} maste vara en icke-tom sokvag")
    if "\\" in path_text:
        raise DependencyAuthorityError(f"FEL: {field_name} maste anvanda forward slash")
    path = Path(path_text)
    if path.is_absolute() or ".." in path.parts:
        raise DependencyAuthorityError(f"FEL: {field_name} maste vara repo-relativ utan parent traversal")
    normalized = path.as_posix()
    if normalized.startswith("./"):
        normalized = normalized[2:]
    if normalized != path_text:
        raise DependencyAuthorityError(f"FEL: {field_name} maste vara normaliserad")
    return normalized


def resolve_repo_relative_path(root: Path, path_text: str, field_name: str) -> Path:
    normalized = normalize_repo_relative_path(path_text, field_name)
    resolved = (root / normalized).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError as exc:
        raise DependencyAuthorityError(f"FEL: {field_name} pekar utanfor repo-root") from exc
    return resolved


def resolve_local_path(root: Path, path_text: str, field_name: str) -> Path:
    if not isinstance(path_text, str) or not path_text.strip():
        raise DependencyAuthorityError(f"FEL: {field_name} maste vara en icke-tom sokvag")
    path = Path(path_text)
    if path.is_absolute():
        return path.resolve()
    return resolve_repo_relative_path(root, path_text, field_name)


def compute_file_hash(path: Path) -> str:
    if not path.exists() or not path.is_file():
        raise DependencyAuthorityError(f"FEL: fil saknas vid {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compute_directory_hash(path: Path) -> str:
    if not path.exists() or not path.is_dir():
        raise DependencyAuthorityError(f"FEL: katalog saknas vid {path}")
    digest = hashlib.sha256()
    digest.update(b"AVELI_DIRECTORY_HASH_V1\n")
    files = [child for child in path.rglob("*") if child.is_file()]
    files.sort(key=lambda child: child.relative_to(path).as_posix().encode("utf-8"))
    for file_path in files:
        relative = file_path.relative_to(path).as_posix().encode("utf-8")
        content_hash = compute_file_hash(file_path).encode("ascii")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(content_hash)
        digest.update(b"\n")
    return digest.hexdigest()


def d01_result_path(root: Path, build_id: str) -> Path:
    return root / D01_RESULT_DIR_RELATIVE / f"{D01_RESULT_PREFIX}{build_id}.json"


def canonical_interpreter_path(root: Path) -> Path:
    return root / CANONICAL_INTERPRETER_RELATIVE


def assert_canonical_interpreter(root: Path) -> None:
    expected = canonical_interpreter_path(root).resolve()
    if Path(sys.executable).resolve() != expected:
        raise DependencyAuthorityError(
            "FEL: D01 maste koras med kanonisk Windows-tolk: " + str(expected)
        )


def snapshot_path(path: Path) -> dict:
    if not path.exists():
        return {"exists": False, "kind": None, "hash": None}
    if path.is_file():
        return {"exists": True, "kind": "file", "hash": compute_file_hash(path)}
    if path.is_dir():
        return {"exists": True, "kind": "dir", "hash": compute_directory_hash(path)}
    return {"exists": True, "kind": "other", "hash": None}


def forbidden_paths(root: Path, build_id: str) -> dict[str, Path]:
    staging = root / ".repo_index" / "_staging" / build_id
    return {
        "active_index_manifest_created": root / ".repo_index" / "index_manifest.json",
        "active_chunk_manifest_created": root / ".repo_index" / "chunk_manifest.jsonl",
        "active_lexical_index_created": root / ".repo_index" / "lexical_index",
        "active_chroma_db_created": root / ".repo_index" / "chroma_db",
        "staging_index_manifest_created": staging / "index_manifest.json",
        "staging_chunk_manifest_created": staging / "chunk_manifest.jsonl",
        "staging_lexical_index_created": staging / "lexical_index",
        "staging_chroma_db_created": staging / "chroma_db",
        "model_artifacts_created": root / ".repo_index" / "models",
        "model_cache_created": root / ".repo_index" / "model_cache",
    }


def snapshot_forbidden_targets(root: Path, build_id: str) -> dict[str, dict]:
    return {key: snapshot_path(path) for key, path in forbidden_paths(root, build_id).items()}


def compare_forbidden_snapshots(before: dict[str, dict], after: dict[str, dict]) -> dict:
    changed = {
        key: before_state != after.get(key, {"exists": False, "kind": None, "hash": None})
        for key, before_state in before.items()
    }
    model_touched = bool(changed.pop("model_artifacts_created", False) or changed.pop("model_cache_created", False))
    changed["model_artifacts_created"] = model_touched
    changed.update(
        {
            "index_build_executed": False,
            "retrieval_query_executed": False,
            "model_loaded": False,
            "cuda_executed": False,
            "promotion_executed": False,
        }
    )
    return changed


def default_forbidden_side_effect_check() -> dict:
    return {
        "active_index_manifest_created": False,
        "active_chunk_manifest_created": False,
        "active_lexical_index_created": False,
        "active_chroma_db_created": False,
        "staging_index_manifest_created": False,
        "staging_chunk_manifest_created": False,
        "staging_lexical_index_created": False,
        "staging_chroma_db_created": False,
        "model_artifacts_created": False,
        "index_build_executed": False,
        "retrieval_query_executed": False,
        "model_loaded": False,
        "cuda_executed": False,
        "promotion_executed": False,
    }


def flatten_forbidden_targets(value: object) -> set[str]:
    if isinstance(value, str):
        return {value.rstrip("/")}
    if isinstance(value, list):
        return set().union(*(flatten_forbidden_targets(item) for item in value))
    if isinstance(value, dict):
        return set().union(*(flatten_forbidden_targets(item) for item in value.values()))
    return set()


def validate_forbidden_targets(approval: dict, build_id: str) -> None:
    declared = flatten_forbidden_targets(approval.get("forbidden_targets"))
    required = {
        ".repo_index/index_manifest.json",
        ".repo_index/chunk_manifest.jsonl",
        ".repo_index/lexical_index",
        ".repo_index/chroma_db",
        ".repo_index/models",
        ".repo_index/model_cache",
        ".repo_index/_staging/<build_id>/index_manifest.json",
        ".repo_index/_staging/<build_id>/chunk_manifest.jsonl",
        ".repo_index/_staging/<build_id>/lexical_index",
        ".repo_index/_staging/<build_id>/chroma_db",
        f".repo_index/_staging/{build_id}/index_manifest.json",
        f".repo_index/_staging/{build_id}/chunk_manifest.jsonl",
        f".repo_index/_staging/{build_id}/lexical_index",
        f".repo_index/_staging/{build_id}/chroma_db",
    }
    missing = sorted(
        target
        for target in required
        if target not in declared and target.replace(build_id, "<build_id>") not in declared
    )
    if missing:
        raise DependencyAuthorityError("FEL: D01-approval saknar forbjudna targets: " + ", ".join(missing))


def validate_false_fields(policy: dict, owner: str, fields: list[str]) -> None:
    for field in fields:
        if require_bool(policy, field, owner) is not False:
            raise DependencyAuthorityError(f"FEL: {owner}.{field} maste vara false")


def validate_network_policy(policy: dict) -> None:
    if require_string(policy, "mode", "network_policy") != "offline":
        raise DependencyAuthorityError("FEL: network_policy.mode maste vara offline")
    validate_false_fields(
        policy,
        "network_policy",
        [
            "downloads_allowed",
            "dependency_download_allowed",
            "model_download_allowed",
            "telemetry_allowed",
            "package_index_allowed",
        ],
    )


def validate_fallback_policy(policy: dict) -> None:
    validate_false_fields(
        policy,
        "fallback_policy",
        [
            "fallbacks_allowed",
            "fallback_package_source_allowed",
            "fallback_interpreter_allowed",
            "fallback_network_allowed",
            "fallback_version_allowed",
            "fallback_hash_allowed",
            "system_site_packages_allowed",
        ],
    )


def validate_e01_result(root: Path, path_text: str, build_id: str) -> tuple[Path, dict]:
    path = resolve_repo_relative_path(root, path_text, "e01_result")
    if not path.exists() or not path.is_file():
        raise DependencyAuthorityError("FEL: E01-resultat saknas for D01")
    result = load_json_object(path)
    if result.get("artifact_type") != "environment_bootstrap_result":
        raise DependencyAuthorityError("FEL: E01-resultat har fel artifact_type")
    if result.get("status") != "PASS":
        raise DependencyAuthorityError("FEL: E01-resultat ar inte PASS")
    if result.get("build_id") != build_id:
        raise DependencyAuthorityError("FEL: E01 build_id matchar inte D01")
    if result.get("target_interpreter_path") != CANONICAL_INTERPRETER_RELATIVE:
        raise DependencyAuthorityError("FEL: E01 target_interpreter_path matchar inte")
    return path, result


def validate_b01_dependency_blocker(root: Path, path_text: str, build_id: str) -> tuple[Path, dict]:
    path = resolve_repo_relative_path(root, path_text, "b01_blocked_result")
    if not path.exists() or not path.is_file():
        raise DependencyAuthorityError("FEL: B01-blockeringsresultat saknas for D01")
    result = load_json_object(path)
    if result.get("artifact_type") != "build_execution_result":
        raise DependencyAuthorityError("FEL: B01-resultat har fel artifact_type")
    if result.get("status") != "BLOCKED":
        raise DependencyAuthorityError("FEL: B01-resultat ar inte BLOCKED")
    if result.get("build_id") != build_id:
        raise DependencyAuthorityError("FEL: B01 build_id matchar inte D01")
    checkpoints = require_object(result, "verification_checkpoints", "B01-resultat")
    dependency_validation = require_object(checkpoints, "dependency_validation", "B01-resultat.verification_checkpoints")
    if dependency_validation.get("failure_class") != "BLOCKED":
        raise DependencyAuthorityError("FEL: B01 ar inte blockerat av dependency readiness")
    if dependency_validation.get("status") not in {"FAIL", "BLOCKED"}:
        raise DependencyAuthorityError("FEL: B01 dependency_validation har ogiltig status")
    stop_reason = str(require_object(result, "failure", "B01-resultat").get("stop_reason", "")).lower()
    if "dependenc" not in stop_reason and "beroend" not in stop_reason:
        raise DependencyAuthorityError("FEL: B01 stop_reason ar inte dependency readiness")
    return path, result


def validate_package_sets(approval: dict) -> tuple[set[str], dict[str, str], dict[str, str]]:
    package_set = require_object(approval, "package_set", "approval")
    direct_required = {package_name(item) for item in require_list(package_set, "direct_required", "approval.package_set")}
    transitive_allowed = {package_name(item) for item in require_list(package_set, "transitive_allowed", "approval.package_set")}
    required_direct = {package_name(item) for item in DIRECT_REQUIRED_PACKAGES}
    missing_direct = sorted(required_direct - direct_required)
    if missing_direct:
        raise DependencyAuthorityError("FEL: D01-approval saknar direktpaket: " + ", ".join(missing_direct))
    approved_names = direct_required | transitive_allowed
    if not transitive_allowed:
        raise DependencyAuthorityError("FEL: D01-approval saknar transitive_allowed")

    raw_versions = require_object(approval, "package_versions", "approval")
    versions = {
        package_name(name): validate_version(version, f"package_versions.{name}")
        for name, version in raw_versions.items()
    }
    if set(versions) != approved_names:
        raise DependencyAuthorityError("FEL: package_versions matchar inte godkand paketclosure")

    raw_hashes = require_object(approval, "package_hashes", "approval")
    hashes = {
        str(filename): validate_sha256(digest, f"package_hashes.{filename}")
        for filename, digest in raw_hashes.items()
    }
    if not hashes:
        raise DependencyAuthorityError("FEL: package_hashes far inte vara tom")
    if any(not filename.endswith(".whl") for filename in hashes):
        raise DependencyAuthorityError("FEL: D01 tillater endast wheelartefakter utan source build")
    return approved_names, versions, hashes


def validate_package_source_policy(root: Path, policy: dict) -> tuple[Path, Path]:
    if require_string(policy, "source_type", "package_source_policy") != "offline_wheelhouse":
        raise DependencyAuthorityError("FEL: package_source_policy.source_type maste vara offline_wheelhouse")
    wheelhouse = resolve_local_path(
        root,
        require_string(policy, "offline_wheelhouse_path", "package_source_policy"),
        "package_source_policy.offline_wheelhouse_path",
    )
    if not wheelhouse.exists() or not wheelhouse.is_dir():
        raise DependencyAuthorityError("FEL: offline wheelhouse saknas")
    try:
        wheelhouse.relative_to((root / ".repo_index").resolve())
        raise DependencyAuthorityError("FEL: offline wheelhouse far inte ligga under .repo_index")
    except ValueError:
        pass
    lock_text = policy.get("requirements_lock_path")
    if not isinstance(lock_text, str) or not lock_text.strip():
        raise DependencyAuthorityError("FEL: package_source_policy.requirements_lock_path kraver konkret lock")
    lock_path = resolve_repo_relative_path(root, lock_text.strip(), "package_source_policy.requirements_lock_path")
    if not lock_path.exists() or not lock_path.is_file():
        raise DependencyAuthorityError("FEL: dependency lock saknas")
    if require_bool(policy, "index_urls_allowed", "package_source_policy"):
        raise DependencyAuthorityError("FEL: package indexes far inte vara tillatna")
    if require_bool(policy, "find_links_only", "package_source_policy") is not True:
        raise DependencyAuthorityError("FEL: find_links_only maste vara true")
    if require_bool(policy, "require_hashes", "package_source_policy") is not True:
        raise DependencyAuthorityError("FEL: require_hashes maste vara true")
    if require_bool(policy, "allow_source_builds", "package_source_policy"):
        raise DependencyAuthorityError("FEL: source builds far inte vara tillatna")
    if require_bool(policy, "allow_editable_installs", "package_source_policy"):
        raise DependencyAuthorityError("FEL: editable installs far inte vara tillatna")
    return wheelhouse, lock_path


def validate_dependency_lock(
    root: Path,
    lock_path: Path,
    build_id: str,
    wheelhouse: Path,
    approved_names: set[str],
    versions: dict[str, str],
    hashes: dict[str, str],
) -> tuple[dict, list[dict]]:
    lock = load_json_object(lock_path)
    if lock.get("artifact_type") != "offline_dependency_lock":
        raise DependencyAuthorityError("FEL: dependency lock har fel artifact_type")
    if lock.get("approval_state") != "LOCKED_FOR_SINGLE_WHEELHOUSE_MATERIALIZATION":
        raise DependencyAuthorityError("FEL: dependency lock ar inte executable")
    execution_policy = require_object(lock, "execution_policy", "dependency_lock")
    if execution_policy.get("example_not_executable") is not False:
        raise DependencyAuthorityError("FEL: dependency lock ar example-only")
    if execution_policy.get("must_stop_if_used") is not False:
        raise DependencyAuthorityError("FEL: dependency lock forbjuder anvandning")
    if lock.get("build_id") != build_id:
        raise DependencyAuthorityError("FEL: dependency lock build_id matchar inte D01")
    if path_key(Path(str(lock.get("repo_root", "")))) != path_key(root):
        raise DependencyAuthorityError("FEL: dependency lock repo_root matchar inte aktiv repo-root")
    lock_wheelhouse = resolve_local_path(root, require_string(lock, "wheelhouse_root", "dependency_lock"), "dependency_lock.wheelhouse_root")
    if path_key(lock_wheelhouse) != path_key(wheelhouse):
        raise DependencyAuthorityError("FEL: dependency lock wheelhouse_root matchar inte D01")
    lock_versions = {
        package_name(name): validate_version(version, f"dependency_lock.package_versions.{name}")
        for name, version in require_object(lock, "package_versions", "dependency_lock").items()
    }
    if lock_versions != versions:
        raise DependencyAuthorityError("FEL: dependency lock package_versions matchar inte approval")
    lock_hashes = {
        str(filename): validate_sha256(digest, f"dependency_lock.wheel_hashes.{filename}")
        for filename, digest in require_object(lock, "wheel_hashes", "dependency_lock").items()
    }
    if lock_hashes != hashes:
        raise DependencyAuthorityError("FEL: dependency lock wheel_hashes matchar inte D01 package_hashes")
    closure = require_object(lock, "closure", "dependency_lock")
    if closure.get("complete") is not True:
        raise DependencyAuthorityError("FEL: dependency closure ar inte komplett")
    if closure.get("full_transitive_closure_declared") is not True:
        raise DependencyAuthorityError("FEL: full transitive closure saknas")
    if closure.get("runtime_resolution_allowed") is not False:
        raise DependencyAuthorityError("FEL: runtime dependency resolution far inte vara tillaten")

    verified_wheels = []
    seen_files: set[str] = set()
    seen_packages: set[str] = set()
    for index, wheel in enumerate(require_list(lock, "wheels", "dependency_lock")):
        if not isinstance(wheel, dict):
            raise DependencyAuthorityError("FEL: wheelpost maste vara objekt")
        owner = f"dependency_lock.wheels[{index}]"
        name = package_name(require_string(wheel, "package_name", owner))
        version = validate_version(require_string(wheel, "version", owner), f"{owner}.version")
        filename = require_string(wheel, "filename", owner)
        sha256 = validate_sha256(require_string(wheel, "sha256", owner), f"{owner}.sha256")
        if name not in approved_names:
            raise DependencyAuthorityError(f"FEL: wheel {name} ar inte godkand")
        if versions[name] != version:
            raise DependencyAuthorityError(f"FEL: wheelversion matchar inte approval for {name}")
        if hashes.get(filename) != sha256:
            raise DependencyAuthorityError(f"FEL: wheelhash matchar inte approval for {filename}")
        if require_string(wheel, "direct_or_transitive", owner) not in {"direct", "transitive"}:
            raise DependencyAuthorityError(f"FEL: {owner}.direct_or_transitive ar ogiltig")
        if not require_list(wheel, "required_by", owner):
            raise DependencyAuthorityError(f"FEL: {owner}.required_by far inte vara tom")
        relative = normalize_repo_relative_path(
            require_string(wheel, "wheelhouse_relative_path", owner),
            f"{owner}.wheelhouse_relative_path",
        )
        if not relative.startswith("wheels/"):
            raise DependencyAuthorityError(f"FEL: {owner}.wheelhouse_relative_path maste ligga under wheels/")
        wheel_path = (wheelhouse / relative).resolve()
        try:
            wheel_path.relative_to(wheelhouse.resolve())
        except ValueError as exc:
            raise DependencyAuthorityError(f"FEL: wheel path pekar utanfor wheelhouse: {filename}") from exc
        if not wheel_path.exists() or not wheel_path.is_file():
            raise DependencyAuthorityError(f"FEL: godkand wheel saknas: {display_path(root, wheel_path)}")
        if compute_file_hash(wheel_path) != sha256:
            raise DependencyAuthorityError(f"FEL: wheelhash matchar inte filen: {filename}")
        seen_files.add(filename)
        seen_packages.add(name)
        verified_wheels.append(
            {"package_name": name, "version": version, "filename": filename, "path": wheel_path}
        )
    if seen_files != set(hashes):
        raise DependencyAuthorityError("FEL: lockets wheels matchar inte D01 package_hashes")
    if seen_packages != approved_names:
        raise DependencyAuthorityError("FEL: lockets paketset matchar inte godkand closure")
    return lock, verified_wheels


def validate_verification_policy(policy: dict) -> None:
    if policy.get("target_path_must_match") != CANONICAL_INTERPRETER_RELATIVE:
        raise DependencyAuthorityError("FEL: verification_policy target_path_must_match ar fel")
    required_true = [
        "target_interpreter_must_exist",
        "e01_result_must_be_pass",
        "b01_result_must_be_dependency_blocked",
        "all_package_artifact_hashes_must_match",
        "installed_versions_must_match",
        "network_must_not_be_used",
        "fallback_must_not_be_used",
        "active_index_artifacts_must_not_be_created",
        "staging_build_artifacts_must_not_be_created",
        "models_must_not_be_loaded_or_downloaded",
    ]
    for field in required_true:
        if policy.get(field) is not True:
            raise DependencyAuthorityError(f"FEL: verification_policy.{field} maste vara true")
    direct_imports = {package_name(item) for item in policy.get("direct_imports_must_succeed", [])}
    if {package_name(item) for item in DIRECT_REQUIRED_PACKAGES} - direct_imports:
        raise DependencyAuthorityError("FEL: verification_policy saknar obligatoriska direktimporter")


def validate_dependency_approval(root: Path, approval_path: Path) -> dict:
    approval = load_json_object(approval_path)
    missing = sorted(REQUIRED_APPROVAL_FIELDS - set(approval))
    if missing:
        raise DependencyAuthorityError("FEL: D01-approval saknar falt: " + ", ".join(missing))
    execution_policy = approval.get("execution_policy")
    if isinstance(execution_policy, dict) and execution_policy.get("example_not_executable"):
        raise DependencyAuthorityError("FEL: D01-approval ar example-only")
    if approval.get("artifact_type") != "environment_dependency_approval":
        raise DependencyAuthorityError("FEL: D01-approval har fel artifact_type")
    if approval.get("approval_state") != "APPROVED_FOR_SINGLE_DEPENDENCY_PREPARATION":
        raise DependencyAuthorityError("FEL: D01-approval ar inte executable")
    if approval.get("approval_phrase") != D01_APPROVAL_PHRASE:
        raise DependencyAuthorityError("FEL: D01 approval_phrase matchar inte exakt")
    scope = require_object(approval, "approval_scope", "approval")
    expected_scope = {
        "controller_scope": "retrieval_index_environment_dependencies",
        "task_id": "D01",
        "mode": "environment_dependencies",
        "expires_after_use": True,
    }
    for field, expected in expected_scope.items():
        if scope.get(field) != expected:
            raise DependencyAuthorityError(f"FEL: approval_scope.{field} matchar inte D01")
    if path_key(Path(str(approval.get("repo_root", "")))) != path_key(root):
        raise DependencyAuthorityError("FEL: D01-approval repo_root matchar inte aktiv repo-root")
    build_id = validate_build_id(approval.get("build_id"))
    if approval.get("target_interpreter_path") != CANONICAL_INTERPRETER_RELATIVE:
        raise DependencyAuthorityError("FEL: D01 target_interpreter_path matchar inte kanonisk tolk")
    if not canonical_interpreter_path(root).exists():
        raise DependencyAuthorityError("FEL: kanonisk tolk saknas for D01")

    e01_path, e01_result = validate_e01_result(root, require_string(approval, "e01_result", "approval"), build_id)
    b01_path, b01_result = validate_b01_dependency_blocker(root, require_string(approval, "b01_blocked_result", "approval"), build_id)
    approved_names, versions, hashes = validate_package_sets(approval)
    source_policy = require_object(approval, "package_source_policy", "approval")
    wheelhouse, lock_path = validate_package_source_policy(root, source_policy)
    dependency_lock, verified_wheels = validate_dependency_lock(
        root,
        lock_path,
        build_id,
        wheelhouse,
        approved_names,
        versions,
        hashes,
    )
    validate_network_policy(require_object(approval, "network_policy", "approval"))
    validate_fallback_policy(require_object(approval, "fallback_policy", "approval"))
    validate_verification_policy(require_object(approval, "verification_policy", "approval"))
    validate_forbidden_targets(approval, build_id)
    return {
        "approval": approval,
        "approval_path": approval_path,
        "build_id": build_id,
        "e01_path": e01_path,
        "e01_result": e01_result,
        "b01_path": b01_path,
        "b01_result": b01_result,
        "approved_names": approved_names,
        "package_versions": versions,
        "package_hashes": hashes,
        "source_policy": source_policy,
        "wheelhouse": wheelhouse,
        "lock_path": lock_path,
        "dependency_lock": dependency_lock,
        "verified_wheels": verified_wheels,
    }


def isolated_python_environment() -> dict[str, str]:
    env = dict(os.environ)
    for key in ["PYTHONPATH", "PYTHONHOME", "PIP_INDEX_URL", "PIP_EXTRA_INDEX_URL"]:
        env.pop(key, None)
    env.update(
        {
            "PYTHONNOUSERSITE": "1",
            "PIP_NO_INDEX": "1",
            "PIP_DISABLE_PIP_VERSION_CHECK": "1",
            "PIP_NO_CACHE_DIR": "1",
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "CUDA_VISIBLE_DEVICES": "",
        }
    )
    return env


def install_approved_wheels(root: Path, context: dict) -> None:
    interpreter = canonical_interpreter_path(root)
    wheel_paths = [
        str(wheel["path"])
        for wheel in sorted(context["verified_wheels"], key=lambda item: (item["package_name"], item["filename"]))
    ]
    if not wheel_paths:
        raise DependencyAuthorityError("FEL: inga godkanda wheels finns for D01-installation")
    pip_check = subprocess.run(
        [str(interpreter), "-m", "pip", "--version"],
        cwd=str(root),
        env=isolated_python_environment(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    if pip_check.returncode != 0:
        raise DependencyAuthorityError("FEL: kanonisk tolk saknar godkand pip-yta for D01")
    completed = subprocess.run(
        [
            str(interpreter),
            "-m",
            "pip",
            "install",
            "--no-index",
            "--no-deps",
            "--force-reinstall",
            "--find-links",
            str(context["wheelhouse"] / "wheels"),
            *wheel_paths,
        ],
        cwd=str(root),
        env=isolated_python_environment(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=1800,
    )
    if completed.returncode != 0:
        raise DependencyAuthorityError("FEL: offline D01-installation misslyckades")


def collect_interpreter_state(root: Path) -> dict:
    interpreter = canonical_interpreter_path(root)
    direct_imports_json = json.dumps(DIRECT_IMPORTS, sort_keys=True)
    script = f"""
import importlib
import importlib.metadata as metadata
import json
import sys

def norm(name):
    return str(name).strip().lower().replace("_", "-")

direct_imports = {direct_imports_json}
distributions = {{}}
for dist in metadata.distributions():
    name = dist.metadata.get("Name")
    if name:
        distributions[norm(name)] = {{
            "name": name,
            "version": dist.version,
            "location": str(dist.locate_file("")),
        }}

imports = {{}}
failed_imports = []
for package_name, module_name in direct_imports.items():
    try:
        importlib.import_module(module_name)
        imports[package_name] = True
    except Exception as exc:
        imports[package_name] = False
        failed_imports.append({{"package": package_name, "error": type(exc).__name__}})

print(json.dumps({{
    "executable": sys.executable,
    "prefix": sys.prefix,
    "base_prefix": sys.base_prefix,
    "distributions": distributions,
    "direct_imports": imports,
    "failed_imports": failed_imports,
}}, sort_keys=True))
"""
    completed = subprocess.run(
        [str(interpreter), "-I", "-c", script],
        cwd=str(root),
        env=isolated_python_environment(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    if completed.returncode != 0:
        raise DependencyAuthorityError("FEL: kanonisk tolk kunde inte verifiera installerade paket")
    data = json.loads(completed.stdout)
    if not isinstance(data, dict):
        raise DependencyAuthorityError("FEL: interpreter state maste vara objekt")
    return data


def installed_package_verification(root: Path, context: dict, state: dict) -> dict:
    distributions = state.get("distributions")
    if not isinstance(distributions, dict):
        raise DependencyAuthorityError("FEL: interpreter state saknar distributions")
    expected = dict(sorted(context["package_versions"].items()))
    actual = {
        name: str(distributions[name]["version"])
        for name in sorted(expected)
        if name in distributions
    }
    missing = sorted(set(expected) - set(actual))
    mismatches = [
        {"package_name": name, "expected": expected[name], "actual": actual.get(name)}
        for name in sorted(set(expected) & set(actual))
        if actual.get(name) != expected[name]
    ]
    unapproved = sorted(set(distributions) - (set(expected) | BOOTSTRAP_PACKAGE_NAMES))
    target_root = (root / ".repo_index" / ".search_venv").resolve()
    system_site = False
    for dist in distributions.values():
        try:
            Path(str(dist.get("location", ""))).resolve().relative_to(target_root)
        except ValueError:
            system_site = True
            break
    status = "PASS" if not missing and not mismatches and not unapproved and not system_site else "BLOCKED"
    return {
        "status": status,
        "package_versions_expected": expected,
        "package_versions_actual": actual,
        "missing_packages": missing,
        "version_mismatches": mismatches,
        "unapproved_packages_present": bool(unapproved),
        "unapproved_packages": unapproved,
        "system_site_packages_used": system_site,
        "failure_class": None if status == "PASS" else "BLOCKED",
    }


def import_readiness_verification(state: dict) -> dict:
    direct_imports = state.get("direct_imports")
    if not isinstance(direct_imports, dict):
        direct_imports = {package: False for package in DIRECT_IMPORTS}
    direct_imports = {package: bool(direct_imports.get(package)) for package in DIRECT_IMPORTS}
    failed = [package for package, passed in direct_imports.items() if not passed]
    status = "PASS" if not failed else "BLOCKED"
    return {
        "status": status,
        "direct_imports": direct_imports,
        "failed_imports": [] if not failed else state.get("failed_imports", failed),
        "target_interpreter_invoked": True,
        "model_loaded": False,
        "cuda_executed": False,
        "failure_class": None if status == "PASS" else "BLOCKED",
    }


def package_source_verification(root: Path, context: dict) -> dict:
    policy = context["source_policy"]
    return {
        "status": "PASS",
        "source_type": "offline_wheelhouse",
        "offline_wheelhouse_path": display_path(root, context["wheelhouse"]),
        "requirements_lock_path": display_path(root, context["lock_path"]),
        "wheelhouse_exists": True,
        "index_urls_allowed": policy["index_urls_allowed"],
        "find_links_only": policy["find_links_only"],
        "require_hashes": policy["require_hashes"],
        "allow_source_builds": policy["allow_source_builds"],
        "allow_editable_installs": policy["allow_editable_installs"],
        "failure_class": None,
    }


def package_hash_verification(context: dict) -> dict:
    return {
        "status": "PASS",
        "approved_artifact_count": len(context["package_hashes"]),
        "checked_artifact_count": len(context["verified_wheels"]),
        "missing_artifact_hashes": [],
        "mismatched_artifact_hashes": [],
        "unapproved_artifacts": [],
        "all_hashes_lowercase_sha256": True,
        "failure_class": None,
    }


def network_verification(policy: dict | None, *, status: str = "PASS") -> dict:
    return {
        "status": status,
        "network_policy": policy.get("mode", "UNKNOWN") if isinstance(policy, dict) else "UNKNOWN",
        "downloads_attempted": False,
        "dependency_download_attempted": False,
        "model_download_attempted": False,
        "telemetry_attempted": False,
        "package_index_attempted": False,
        "failure_class": None if status == "PASS" else "BLOCKED",
    }


def fallback_verification(policy: dict | None, *, status: str = "PASS") -> dict:
    return {
        "status": status,
        "fallbacks_allowed": policy.get("fallbacks_allowed") if isinstance(policy, dict) else None,
        "fallback_package_source_used": False,
        "fallback_interpreter_used": False,
        "fallback_network_used": False,
        "fallback_version_used": False,
        "fallback_hash_used": False,
        "system_site_packages_used": False,
        "failure_class": None if status == "PASS" else "BLOCKED",
    }


def default_blocked_sections() -> dict:
    return {
        "package_source_verification": {
            "status": "BLOCKED",
            "source_type": None,
            "offline_wheelhouse_path": None,
            "requirements_lock_path": None,
            "wheelhouse_exists": False,
            "index_urls_allowed": None,
            "find_links_only": None,
            "require_hashes": None,
            "allow_source_builds": None,
            "allow_editable_installs": None,
            "failure_class": "BLOCKED",
        },
        "package_hash_verification": {
            "status": "BLOCKED",
            "approved_artifact_count": 0,
            "checked_artifact_count": 0,
            "missing_artifact_hashes": [],
            "mismatched_artifact_hashes": [],
            "unapproved_artifacts": [],
            "all_hashes_lowercase_sha256": False,
            "failure_class": "BLOCKED",
        },
        "installed_package_verification": {
            "status": "BLOCKED",
            "package_versions_expected": {},
            "package_versions_actual": {},
            "missing_packages": [],
            "version_mismatches": [],
            "unapproved_packages_present": False,
            "unapproved_packages": [],
            "system_site_packages_used": False,
            "failure_class": "BLOCKED",
        },
        "import_readiness_verification": {
            "status": "BLOCKED",
            "direct_imports": {package: False for package in DIRECT_IMPORTS},
            "failed_imports": list(DIRECT_IMPORTS),
            "target_interpreter_invoked": False,
            "model_loaded": False,
            "cuda_executed": False,
            "failure_class": "BLOCKED",
        },
        "network_verification": network_verification(None, status="BLOCKED"),
        "fallback_verification": fallback_verification(None, status="BLOCKED"),
        "forbidden_side_effect_check": default_forbidden_side_effect_check(),
    }


def build_failure(
    stop_reason: str,
    authority_file: str,
    affected_path: str,
    *,
    dependency_environment_touched: bool,
    active_index_touched: bool,
    staging_artifacts_created: bool,
) -> dict:
    return {
        "failure_class": "BLOCKED",
        "stop_reason": stop_reason,
        "authority_file": authority_file,
        "affected_path": affected_path,
        "dependency_environment_touched": dependency_environment_touched,
        "active_index_touched": active_index_touched,
        "staging_artifacts_created": staging_artifacts_created,
        "next_allowed_action": (
            "Provide a concrete executable D01 approval bound to a PASS W01 offline "
            "wheelhouse result, then rerun D01."
        ),
    }


def base_result(
    root: Path,
    build_id: str,
    started_at: str,
    completed_at: str,
    *,
    approval_artifact: str | None,
    e01_result: str | None,
    b01_blocked_result: str | None,
    dependency_preparation_attempted: bool,
) -> dict:
    result = {
        "artifact_type": "environment_dependency_result",
        "controller_scope": "retrieval_index_environment_dependencies",
        "task_id": "D01",
        "mode": "environment_dependencies",
        "status": "BLOCKED",
        "build_id": build_id,
        "approval_artifact": approval_artifact,
        "repo_root": root.as_posix(),
        "target_interpreter_path": CANONICAL_INTERPRETER_RELATIVE,
        "interpreter_identity": {
            "executable": canonical_interpreter_path(root).as_posix(),
            "invoked_executable": sys.executable,
            "canonical_interpreter_matches": Path(sys.executable).resolve()
            == canonical_interpreter_path(root).resolve(),
        },
        "e01_result": e01_result,
        "b01_blocked_result": b01_blocked_result,
        "started_at_utc": started_at,
        "completed_at_utc": completed_at,
        "dependency_preparation_attempted": dependency_preparation_attempted,
        "failure": None,
    }
    result.update(default_blocked_sections())
    return result


def side_effect_summary(side_effects: dict) -> tuple[bool, bool]:
    active_touched = bool(
        side_effects.get("active_index_manifest_created")
        or side_effects.get("active_chunk_manifest_created")
        or side_effects.get("active_lexical_index_created")
        or side_effects.get("active_chroma_db_created")
    )
    staging_created = bool(
        side_effects.get("staging_index_manifest_created")
        or side_effects.get("staging_chunk_manifest_created")
        or side_effects.get("staging_lexical_index_created")
        or side_effects.get("staging_chroma_db_created")
    )
    return active_touched, staging_created


def execute_d01_dependency_preparation(root: Path, approval_path: Path) -> dict:
    started_at = utc_now_iso()
    build_id = "0" * 64
    e01_path_text = None
    b01_path_text = None
    attempted = False
    before = None
    try:
        assert_canonical_interpreter(root)
        rough = load_json_object(approval_path)
        build_id = validate_build_id(rough.get("build_id"))
        e01_path_text = rough.get("e01_result") if isinstance(rough.get("e01_result"), str) else None
        b01_path_text = rough.get("b01_blocked_result") if isinstance(rough.get("b01_blocked_result"), str) else None
        before = snapshot_forbidden_targets(root, build_id)
        context = validate_dependency_approval(root, approval_path)
        install_approved_wheels(root, context)
        attempted = True
        state = collect_interpreter_state(root)
        installed = installed_package_verification(root, context, state)
        imports = import_readiness_verification(state)
        side_effects = compare_forbidden_snapshots(before, snapshot_forbidden_targets(root, build_id))
        completed_at = utc_now_iso()
        result = base_result(
            root,
            build_id,
            started_at,
            completed_at,
            approval_artifact=display_path(root, approval_path),
            e01_result=display_path(root, context["e01_path"]),
            b01_blocked_result=display_path(root, context["b01_path"]),
            dependency_preparation_attempted=attempted,
        )
        result["interpreter_identity"].update(
            {
                "reported_executable": state.get("executable"),
                "reported_prefix": state.get("prefix"),
                "reported_base_prefix": state.get("base_prefix"),
            }
        )
        result["package_source_verification"] = package_source_verification(root, context)
        result["package_hash_verification"] = package_hash_verification(context)
        result["installed_package_verification"] = installed
        result["import_readiness_verification"] = imports
        result["network_verification"] = network_verification(context["approval"]["network_policy"])
        result["fallback_verification"] = fallback_verification(context["approval"]["fallback_policy"])
        result["forbidden_side_effect_check"] = side_effects
        sections = [
            result["package_source_verification"],
            result["package_hash_verification"],
            installed,
            imports,
            result["network_verification"],
            result["fallback_verification"],
        ]
        if all(section["status"] == "PASS" for section in sections) and not any(side_effects.values()):
            result["status"] = "PASS"
            result["failure"] = None
        else:
            active_touched, staging_created = side_effect_summary(side_effects)
            result["failure"] = build_failure(
                "D01-kontroller kunde inte verifiera dependency readiness som PASS.",
                "actual_truth/contracts/retrieval/environment_dependency_result_contract.md",
                CANONICAL_INTERPRETER_RELATIVE,
                dependency_environment_touched=attempted,
                active_index_touched=active_touched,
                staging_artifacts_created=staging_created,
            )
        return result
    except Exception as exc:
        if before is not None:
            side_effects = compare_forbidden_snapshots(before, snapshot_forbidden_targets(root, build_id))
        else:
            side_effects = default_forbidden_side_effect_check()
        active_touched, staging_created = side_effect_summary(side_effects)
        result = base_result(
            root,
            build_id,
            started_at,
            utc_now_iso(),
            approval_artifact=display_path(root, approval_path),
            e01_result=e01_path_text,
            b01_blocked_result=b01_path_text,
            dependency_preparation_attempted=attempted,
        )
        result["forbidden_side_effect_check"] = side_effects
        result["failure"] = build_failure(
            str(exc),
            "actual_truth/contracts/retrieval/environment_dependency_contract.md",
            display_path(root, approval_path),
            dependency_environment_touched=attempted,
            active_index_touched=active_touched,
            staging_artifacts_created=staging_created,
        )
        return result


def write_d01_result(root: Path, result: dict) -> Path:
    build_id = validate_build_id(result.get("build_id"))
    path = d01_result_path(root, build_id)
    write_json_object(path, result)
    return path


def validate_d01_pass_result(root: Path, result_path: Path, *, expected_build_id: str | None = None) -> dict:
    if not result_path.exists() or not result_path.is_file():
        raise DependencyAuthorityError(f"FEL: D01-resultat saknas vid {display_path(root, result_path)}")
    result = load_json_object(result_path)
    missing = sorted(REQUIRED_RESULT_FIELDS - set(result))
    if missing:
        raise DependencyAuthorityError("FEL: D01-resultat saknar falt: " + ", ".join(missing))
    if result.get("artifact_type") != "environment_dependency_result":
        raise DependencyAuthorityError("FEL: D01-resultat har fel artifact_type")
    if result.get("controller_scope") != "retrieval_index_environment_dependencies":
        raise DependencyAuthorityError("FEL: D01-resultat har fel controller_scope")
    if result.get("task_id") != "D01" or result.get("mode") != "environment_dependencies":
        raise DependencyAuthorityError("FEL: D01-resultat har fel task eller mode")
    build_id = validate_build_id(result.get("build_id"))
    if expected_build_id is not None and build_id != expected_build_id:
        raise DependencyAuthorityError("FEL: D01-resultat build_id matchar inte forvantad build")
    if result_path.resolve() != d01_result_path(root, build_id).resolve():
        raise DependencyAuthorityError("FEL: D01-resultat ligger inte pa kanonisk resultatsokvag")
    if result.get("status") != "PASS":
        raise DependencyAuthorityError("FEL: D01-resultat ar inte PASS")
    if result.get("failure") is not None:
        raise DependencyAuthorityError("FEL: D01 PASS far inte innehalla failure")
    if path_key(Path(str(result.get("repo_root", "")))) != path_key(root):
        raise DependencyAuthorityError("FEL: D01-resultat repo_root matchar inte aktiv repo-root")
    if result.get("target_interpreter_path") != CANONICAL_INTERPRETER_RELATIVE:
        raise DependencyAuthorityError("FEL: D01 target_interpreter_path matchar inte")
    if result.get("dependency_preparation_attempted") is not True:
        raise DependencyAuthorityError("FEL: D01 PASS kraver dependency_preparation_attempted=true")

    identity = require_object(result, "interpreter_identity", "D01-resultat")
    if identity.get("canonical_interpreter_matches") is not True:
        raise DependencyAuthorityError("FEL: D01-resultat saknar kanonisk interpreteridentitet")
    if Path(str(identity.get("reported_executable", ""))).resolve() != canonical_interpreter_path(root).resolve():
        raise DependencyAuthorityError("FEL: D01-resultat producerades inte av kanonisk interpreter")

    source = require_object(result, "package_source_verification", "D01-resultat")
    if source.get("status") != "PASS" or source.get("source_type") != "offline_wheelhouse":
        raise DependencyAuthorityError("FEL: D01 package_source_verification ar inte PASS")
    expected_source_values = {
        "wheelhouse_exists": True,
        "index_urls_allowed": False,
        "find_links_only": True,
        "require_hashes": True,
        "allow_source_builds": False,
        "allow_editable_installs": False,
    }
    for field, expected in expected_source_values.items():
        if source.get(field) is not expected:
            raise DependencyAuthorityError(f"FEL: D01 package_source_verification.{field} ar fel")

    hashes = require_object(result, "package_hash_verification", "D01-resultat")
    if hashes.get("status") != "PASS":
        raise DependencyAuthorityError("FEL: D01 package_hash_verification ar inte PASS")
    if hashes.get("approved_artifact_count") != hashes.get("checked_artifact_count"):
        raise DependencyAuthorityError("FEL: D01 hashkontroll ar inte komplett")
    if hashes.get("missing_artifact_hashes") != [] or hashes.get("mismatched_artifact_hashes") != []:
        raise DependencyAuthorityError("FEL: D01 hashkontroll innehaller missar")
    if hashes.get("unapproved_artifacts") != []:
        raise DependencyAuthorityError("FEL: D01 hashkontroll hittade icke-godkanda artefakter")
    if hashes.get("all_hashes_lowercase_sha256") is not True:
        raise DependencyAuthorityError("FEL: D01 hashar ar inte lowercase sha256")

    installed = require_object(result, "installed_package_verification", "D01-resultat")
    if installed.get("status") != "PASS":
        raise DependencyAuthorityError("FEL: D01 installed_package_verification ar inte PASS")
    expected_versions = require_object(installed, "package_versions_expected", "D01-resultat.installed_package_verification")
    actual_versions = require_object(installed, "package_versions_actual", "D01-resultat.installed_package_verification")
    normalized_expected = {package_name(name): version for name, version in expected_versions.items()}
    normalized_actual = {package_name(name): version for name, version in actual_versions.items()}
    direct_missing = sorted({package_name(name) for name in DIRECT_REQUIRED_PACKAGES} - set(normalized_expected))
    if direct_missing:
        raise DependencyAuthorityError("FEL: D01-resultat tacker inte direktpaket: " + ", ".join(direct_missing))
    if normalized_expected != normalized_actual:
        raise DependencyAuthorityError("FEL: D01 installerade versioner matchar inte approval")
    if installed.get("missing_packages") != [] or installed.get("version_mismatches") != []:
        raise DependencyAuthorityError("FEL: D01 installerad paketverifiering har missar")
    if installed.get("unapproved_packages_present") is not False:
        raise DependencyAuthorityError("FEL: D01 hittade icke-godkanda paket")
    if installed.get("system_site_packages_used") is not False:
        raise DependencyAuthorityError("FEL: D01 anvande system site-packages")

    imports = require_object(result, "import_readiness_verification", "D01-resultat")
    if imports.get("status") != "PASS":
        raise DependencyAuthorityError("FEL: D01 import_readiness_verification ar inte PASS")
    direct_imports = require_object(imports, "direct_imports", "D01-resultat.import_readiness_verification")
    for package in DIRECT_IMPORTS:
        if direct_imports.get(package) is not True:
            raise DependencyAuthorityError(f"FEL: D01 direktimport misslyckades for {package}")
    if imports.get("target_interpreter_invoked") is not True:
        raise DependencyAuthorityError("FEL: D01 anropade inte target interpreter")
    if imports.get("model_loaded") is not False or imports.get("cuda_executed") is not False:
        raise DependencyAuthorityError("FEL: D01 importverifiering laddade modell eller CUDA")

    network = require_object(result, "network_verification", "D01-resultat")
    if network.get("status") != "PASS":
        raise DependencyAuthorityError("FEL: D01 network_verification ar inte PASS")
    for field in [
        "downloads_attempted",
        "dependency_download_attempted",
        "model_download_attempted",
        "telemetry_attempted",
        "package_index_attempted",
    ]:
        if network.get(field) is not False:
            raise DependencyAuthorityError(f"FEL: D01 network_verification.{field} maste vara false")

    fallback = require_object(result, "fallback_verification", "D01-resultat")
    if fallback.get("status") != "PASS":
        raise DependencyAuthorityError("FEL: D01 fallback_verification ar inte PASS")
    for field in [
        "fallback_package_source_used",
        "fallback_interpreter_used",
        "fallback_network_used",
        "fallback_version_used",
        "fallback_hash_used",
        "system_site_packages_used",
    ]:
        if fallback.get(field) is not False:
            raise DependencyAuthorityError(f"FEL: D01 fallback_verification.{field} maste vara false")
    side_effects = require_object(result, "forbidden_side_effect_check", "D01-resultat")
    if any(bool(value) for value in side_effects.values()):
        raise DependencyAuthorityError("FEL: D01-resultat visar forbjudna side effects")
    return result


def serialize_dependency_authority_result(result: dict) -> dict:
    installed = result.get("installed_package_verification", {})
    return {
        "artifact_type": result.get("artifact_type"),
        "status": result.get("status"),
        "build_id": result.get("build_id"),
        "result_authority": f"{D01_RESULT_DIR_RELATIVE}/{D01_RESULT_PREFIX}{result.get('build_id')}.json",
        "target_interpreter_path": result.get("target_interpreter_path"),
        "dependency_preparation_attempted": result.get("dependency_preparation_attempted"),
        "package_source_verification": result.get("package_source_verification", {}),
        "package_versions_expected": installed.get("package_versions_expected", {}),
        "direct_imports": result.get("import_readiness_verification", {}).get("direct_imports", {}),
        "network_verification": result.get("network_verification", {}),
        "fallback_verification": result.get("fallback_verification", {}),
    }


def require_valid_d01_pass_for_build(root: Path, build_id: str) -> dict:
    checked_build_id = validate_build_id(build_id)
    return serialize_dependency_authority_result(
        validate_d01_pass_result(
            root,
            d01_result_path(root, checked_build_id),
            expected_build_id=checked_build_id,
        )
    )


def require_valid_d01_pass_from_environment(root: Path) -> dict:
    result_artifact = os.environ.get(D01_RESULT_ARTIFACT_ENV, "").strip()
    build_id = os.environ.get(D01_RESULT_BUILD_ID_ENV, "").strip()
    if result_artifact:
        return serialize_dependency_authority_result(
            validate_d01_pass_result(root, resolve_repo_relative_path(root, result_artifact, D01_RESULT_ARTIFACT_ENV))
        )
    if build_id:
        return require_valid_d01_pass_for_build(root, build_id)
    raise DependencyAuthorityError(
        "FEL: D01 dependency authority saknas; ange "
        f"{D01_RESULT_BUILD_ID_ENV} eller {D01_RESULT_ARTIFACT_ENV}"
    )


def execute_and_write_d01(root: Path, approval_path_text: str) -> tuple[Path, dict]:
    approval_path = resolve_repo_relative_path(root, approval_path_text, "approval_artifact")
    if not approval_path.exists() or not approval_path.is_file():
        raise DependencyAuthorityError("FEL: D01 approval artifact saknas")
    result = execute_d01_dependency_preparation(root, approval_path)
    path = write_d01_result(root, result)
    return path, result


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    args = sys.argv[1:]
    try:
        if len(args) == 2 and args[0] == "--approval":
            path, result = execute_and_write_d01(root, args[1])
            print(json.dumps({"status": result["status"], "result": display_path(root, path)}, ensure_ascii=False, sort_keys=True))
            return 0 if result["status"] == "PASS" else 1
        if len(args) == 2 and args[0] == "--verify-pass-build-id":
            print(json.dumps(require_valid_d01_pass_for_build(root, args[1]), ensure_ascii=False, sort_keys=True))
            return 0
        if len(args) == 2 and args[0] == "--verify-pass-result":
            result_path = resolve_repo_relative_path(root, args[1], "result_artifact")
            print(json.dumps(serialize_dependency_authority_result(validate_d01_pass_result(root, result_path)), ensure_ascii=False, sort_keys=True))
            return 0
        raise DependencyAuthorityError(
            "FEL: anvand --approval <repo-relative-json>, "
            "--verify-pass-build-id <build_id> eller --verify-pass-result <repo-relative-json>"
        )
    except DependencyAuthorityError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
