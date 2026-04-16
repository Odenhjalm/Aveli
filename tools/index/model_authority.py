import hashlib
import json
import os
from pathlib import Path


MODEL_AUTHORITY_SCHEMA_VERSION = "model_authority_v1"
MODEL_AUTHORITY_FILENAME = "model_authority.json"
MODEL_AUTHORITY_ROOT_RELATIVE = ".repo_index/models"
MODEL_AUTHORITY_PATH_RELATIVE = ".repo_index/models/model_authority.json"
CACHE_ENV_VARS = {
    "HF_HOME",
    "HUGGINGFACE_HUB_CACHE",
    "SENTENCE_TRANSFORMERS_HOME",
    "TRANSFORMERS_CACHE",
}
MUTABLE_REVISIONS = {"", "main", "master", "latest"}
ROLE_TO_MANIFEST_FIELD = {
    "embedding": "embedding_model",
    "rerank": "rerank_model",
}


class ModelAuthorityError(RuntimeError):
    pass


def canonical_json_dumps(data: object) -> str:
    return json.dumps(
        data,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def compute_sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def validate_sha256_hex(value: object, field_name: str) -> str:
    if not isinstance(value, str):
        raise ModelAuthorityError(f"FEL: {field_name} maste vara sha256-hex")
    digest = value.strip()
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise ModelAuthorityError(f"FEL: {field_name} maste vara 64 tecken lowercase sha256-hex")
    return digest


def validate_revision(value: object, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ModelAuthorityError(f"FEL: {field_name} maste vara en last revision")
    revision = value.strip()
    if revision in MUTABLE_REVISIONS:
        raise ModelAuthorityError(f"FEL: {field_name} far inte vara en rorlig revision")
    if len(revision) not in {40, 64} or any(char not in "0123456789abcdef" for char in revision):
        raise ModelAuthorityError(f"FEL: {field_name} maste vara 40 eller 64 tecken lowercase hex")
    return revision


def is_relative_to_path(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def display_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def require_object(container: dict, field_name: str, owner: str) -> dict:
    value = container.get(field_name)
    if not isinstance(value, dict):
        raise ModelAuthorityError(f"FEL: {owner}.{field_name} maste vara ett JSON-objekt")
    return value


def require_string(container: dict, field_name: str, owner: str) -> str:
    value = container.get(field_name)
    if not isinstance(value, str) or not value.strip():
        raise ModelAuthorityError(f"FEL: {owner}.{field_name} maste vara en icke-tom strang")
    return value.strip()


def require_bool(container: dict, field_name: str, owner: str) -> bool:
    value = container.get(field_name)
    if not isinstance(value, bool):
        raise ModelAuthorityError(f"FEL: {owner}.{field_name} maste vara boolean")
    return value


def model_authority_root(root: Path) -> Path:
    return root / ".repo_index" / "models"


def model_authority_path(root: Path) -> Path:
    return model_authority_root(root) / MODEL_AUTHORITY_FILENAME


def normalize_repo_relative_path(path_text: str, field_name: str) -> str:
    if not isinstance(path_text, str) or not path_text.strip():
        raise ModelAuthorityError(f"FEL: {field_name} maste vara en icke-tom repo-relativ sokvag")
    if "\\" in path_text:
        raise ModelAuthorityError(f"FEL: {field_name} maste anvanda forward slash")
    path = Path(path_text)
    if path.is_absolute() or ".." in path.parts:
        raise ModelAuthorityError(f"FEL: {field_name} maste vara repo-relativ utan parent traversal")
    normalized = path.as_posix()
    if normalized.startswith("./"):
        normalized = normalized[2:]
    if normalized != path_text:
        raise ModelAuthorityError(f"FEL: {field_name} maste vara normaliserad")
    return normalized


def resolve_authorized_local_model_path(root: Path, path_text: str, field_name: str) -> Path:
    normalized = normalize_repo_relative_path(path_text, field_name)
    authority_root = model_authority_root(root).resolve()
    resolved = (root / normalized).resolve()
    if resolved == authority_root or not is_relative_to_path(resolved, authority_root):
        raise ModelAuthorityError(f"FEL: {field_name} maste ligga under {MODEL_AUTHORITY_ROOT_RELATIVE}")
    lowered_parts = {part.lower() for part in resolved.relative_to(authority_root).parts}
    if ".cache" in lowered_parts or "model_cache" in lowered_parts:
        raise ModelAuthorityError(f"FEL: {field_name} far inte peka pa cacheyta")
    if not resolved.exists() or not resolved.is_dir():
        raise ModelAuthorityError(f"FEL: modellkatalog saknas vid {display_path(root, resolved)}")
    return resolved


def compute_file_hash(path: Path) -> str:
    if not path.exists() or not path.is_file():
        raise ModelAuthorityError(f"FEL: modellfil saknas vid {path}")
    return compute_sha256_bytes(path.read_bytes())


def compute_directory_hash(path: Path) -> str:
    if not path.exists() or not path.is_dir():
        raise ModelAuthorityError(f"FEL: modellkatalog saknas vid {path}")
    parts: list[bytes] = [b"AVELI_MODEL_DIRECTORY_HASH_V1\n"]
    files = [child for child in path.rglob("*") if child.is_file()]
    files.sort(key=lambda child: child.relative_to(path).as_posix().encode("utf-8"))
    for file_path in files:
        relative_path = file_path.relative_to(path).as_posix()
        relative_bytes = relative_path.encode("utf-8")
        content = file_path.read_bytes()
        parts.append(f"PATH_LEN {len(relative_bytes)}\n".encode("ascii"))
        parts.append(relative_bytes)
        parts.append(b"\n")
        parts.append(f"CONTENT_LEN {len(content)}\n".encode("ascii"))
        parts.append(content)
        parts.append(b"\n")
    return compute_sha256_bytes(b"".join(parts))


def compute_tokenizer_files_hash(tokenizer_files: dict[str, str]) -> str:
    return compute_sha256_bytes(canonical_json_dumps(tokenizer_files).encode("utf-8"))


def assert_no_implicit_cache_environment() -> None:
    present = sorted(name for name in CACHE_ENV_VARS if os.environ.get(name))
    if present:
        raise ModelAuthorityError(
            "FEL: implicit modellcachemiljo ar inte tillaten: " + ", ".join(present)
        )


def load_model_authority(root: Path) -> tuple[Path, dict]:
    authority_path = model_authority_path(root)
    if not authority_path.exists() or not authority_path.is_file():
        raise ModelAuthorityError(
            f"FEL: modellauktoritet saknas vid {MODEL_AUTHORITY_PATH_RELATIVE}"
        )
    data = json.loads(authority_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ModelAuthorityError("FEL: modellauktoritet maste vara ett JSON-objekt")
    return authority_path, data


def validate_model_authority_header(root: Path, authority: dict) -> dict:
    if authority.get("artifact_type") != "model_authority":
        raise ModelAuthorityError("FEL: modellauktoritet har fel artifact_type")
    if authority.get("schema_version") != MODEL_AUTHORITY_SCHEMA_VERSION:
        raise ModelAuthorityError("FEL: modellauktoritet har fel schema_version")
    if require_string(authority, "authority_root", "model_authority") != MODEL_AUTHORITY_ROOT_RELATIVE:
        raise ModelAuthorityError("FEL: modellauktoritet authority_root matchar inte kanonisk yta")
    if require_bool(authority, "local_files_only", "model_authority") is not True:
        raise ModelAuthorityError("FEL: modellauktoritet maste ange local_files_only=true")
    if require_bool(authority, "network_allowed", "model_authority") is not False:
        raise ModelAuthorityError("FEL: modellauktoritet far inte tillata natverk")
    if require_bool(authority, "cache_resolution_allowed", "model_authority") is not False:
        raise ModelAuthorityError("FEL: modellauktoritet far inte tillata cacheupplosning")
    models = require_object(authority, "models", "model_authority")
    for role in ROLE_TO_MANIFEST_FIELD:
        if role not in models:
            raise ModelAuthorityError(f"FEL: modellauktoritet saknar rollen {role}")
    return models


def validate_tokenizer_files(root: Path, model_path: Path, binding: dict, owner: str) -> tuple[dict[str, str], str]:
    tokenizer_files = require_object(binding, "tokenizer_files", owner)
    if not tokenizer_files:
        raise ModelAuthorityError(f"FEL: {owner}.tokenizer_files far inte vara tom")
    verified_files: dict[str, str] = {}
    for file_name, expected_hash in tokenizer_files.items():
        normalized = normalize_repo_relative_path(str(file_name), f"{owner}.tokenizer_files")
        file_path = (model_path / normalized).resolve()
        if not is_relative_to_path(file_path, model_path.resolve()):
            raise ModelAuthorityError(f"FEL: tokenizerfil pekar utanfor modellkatalogen: {file_name}")
        expected_digest = validate_sha256_hex(expected_hash, f"{owner}.tokenizer_files.{file_name}")
        actual_digest = compute_file_hash(file_path)
        if actual_digest != expected_digest:
            raise ModelAuthorityError(f"FEL: tokenizerhash matchar inte {display_path(root, file_path)}")
        verified_files[normalized] = actual_digest
    return verified_files, compute_tokenizer_files_hash(verified_files)


def resolve_model_binding(root: Path, manifest: dict, role: str, authority_path: Path, binding: dict) -> dict:
    if role not in ROLE_TO_MANIFEST_FIELD:
        raise ModelAuthorityError(f"FEL: okand modellroll: {role}")
    owner = f"model_authority.models.{role}"
    manifest_field = ROLE_TO_MANIFEST_FIELD[role]
    manifest_model_id = require_string(manifest, manifest_field, "index_manifest")
    model_id = require_string(binding, "model_id", owner)
    if model_id != manifest_model_id:
        raise ModelAuthorityError(f"FEL: {owner}.model_id matchar inte indexmanifestets {manifest_field}")
    local_path = resolve_authorized_local_model_path(root, require_string(binding, "local_path", owner), f"{owner}.local_path")
    model_revision = validate_revision(binding.get("model_revision"), f"{owner}.model_revision")
    model_snapshot_hash = validate_sha256_hex(binding.get("model_snapshot_hash"), f"{owner}.model_snapshot_hash")
    actual_snapshot_hash = compute_directory_hash(local_path)
    if actual_snapshot_hash != model_snapshot_hash:
        raise ModelAuthorityError(f"FEL: modellens snapshot-hash matchar inte {display_path(root, local_path)}")

    tokenizer_id = require_string(binding, "tokenizer_id", owner)
    tokenizer_revision = validate_revision(binding.get("tokenizer_revision"), f"{owner}.tokenizer_revision")
    tokenizer_files, actual_tokenizer_files_hash = validate_tokenizer_files(root, local_path, binding, owner)
    tokenizer_files_hash = validate_sha256_hex(binding.get("tokenizer_files_hash"), f"{owner}.tokenizer_files_hash")
    if actual_tokenizer_files_hash != tokenizer_files_hash:
        raise ModelAuthorityError(f"FEL: tokenizer_files_hash matchar inte {owner}.tokenizer_files")
    if require_bool(binding, "local_files_only", owner) is not True:
        raise ModelAuthorityError(f"FEL: {owner}.local_files_only maste vara true")
    if require_bool(binding, "trust_remote_code", owner) is not False:
        raise ModelAuthorityError(f"FEL: {owner}.trust_remote_code maste vara false")

    return {
        "role": role,
        "authority_path": authority_path,
        "authority_path_text": display_path(root, authority_path),
        "local_path": local_path,
        "local_path_text": display_path(root, local_path),
        "local_files_only": True,
        "model_id": model_id,
        "model_revision": model_revision,
        "model_snapshot_hash": model_snapshot_hash,
        "tokenizer_files": tokenizer_files,
        "tokenizer_files_hash": tokenizer_files_hash,
        "tokenizer_id": tokenizer_id,
        "tokenizer_revision": tokenizer_revision,
        "trust_remote_code": False,
        "verification": {
            "cache_environment_blocked": True,
            "model_hash_verified": True,
            "network_allowed": False,
            "tokenizer_hash_verified": True,
        },
    }


def validate_model_authority_for_manifest(root: Path, manifest: dict) -> dict:
    assert_no_implicit_cache_environment()
    authority_path, authority = load_model_authority(root)
    models = validate_model_authority_header(root, authority)
    bindings = {
        role: resolve_model_binding(root, manifest, role, authority_path, models[role])
        for role in ROLE_TO_MANIFEST_FIELD
    }
    return {
        "authority_path": authority_path,
        "authority_path_text": display_path(root, authority_path),
        "authority_root_text": MODEL_AUTHORITY_ROOT_RELATIVE,
        "cache_resolution_allowed": False,
        "local_files_only": True,
        "network_allowed": False,
        "models": bindings,
    }


def serialize_model_authority_result(model_authority: dict) -> dict:
    return {
        "authority_path": model_authority["authority_path_text"],
        "authority_root": model_authority["authority_root_text"],
        "cache_resolution_allowed": False,
        "local_files_only": True,
        "network_allowed": False,
        "models": {
            role: {
                "local_files_only": binding["local_files_only"],
                "local_path": binding["local_path_text"],
                "model_id": binding["model_id"],
                "model_revision": binding["model_revision"],
                "model_snapshot_hash": binding["model_snapshot_hash"],
                "tokenizer_files_hash": binding["tokenizer_files_hash"],
                "tokenizer_id": binding["tokenizer_id"],
                "tokenizer_revision": binding["tokenizer_revision"],
                "trust_remote_code": binding["trust_remote_code"],
                "verification": binding["verification"],
            }
            for role, binding in model_authority["models"].items()
        },
    }

