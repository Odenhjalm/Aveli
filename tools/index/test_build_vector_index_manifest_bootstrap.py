import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "index" / "build_vector_index.py"

SPEC = importlib.util.spec_from_file_location("build_vector_index", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
build_vector_index = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_vector_index)


class BuildVectorIndexManifestBootstrapTests(unittest.TestCase):
    def test_bootstrap_index_manifest_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            search_manifest_path = temp_path / "search_manifest.txt"
            search_manifest_path.write_text("a.py\nb.md\n", encoding="utf-8")
            corpus_manifest_hash = build_vector_index.compute_sha256_bytes(search_manifest_path.read_bytes())
            index_manifest_path = temp_path / "index_manifest.json"

            expected_manifest = build_vector_index.build_canonical_index_manifest(corpus_manifest_hash)

            first_manifest = build_vector_index.bootstrap_index_manifest(
                corpus_manifest_hash,
                path=index_manifest_path,
            )
            second_manifest = build_vector_index.bootstrap_index_manifest(
                corpus_manifest_hash,
                path=index_manifest_path,
            )

            self.assertEqual(first_manifest, expected_manifest)
            self.assertEqual(second_manifest, expected_manifest)
            self.assertEqual(
                json.loads(index_manifest_path.read_text(encoding="utf-8")),
                expected_manifest,
            )

    def test_bootstrap_rewrites_invalid_manifest_without_guessing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            index_manifest_path = Path(temp_dir) / "index_manifest.json"
            index_manifest_path.write_text(
                '{"classification_rules": {"unexpected": true}}\n',
                encoding="utf-8",
            )

            manifest = build_vector_index.bootstrap_index_manifest(
                "deadbeef",
                path=index_manifest_path,
            )

            self.assertEqual(
                manifest,
                build_vector_index.build_canonical_index_manifest("deadbeef"),
            )

    def test_validate_index_manifest_hard_stops_on_policy_drift(self) -> None:
        manifest = build_vector_index.build_canonical_index_manifest("abc123", "chunk123")
        manifest["ranking_policy"] = {"formula": "private_score"}

        with self.assertRaisesRegex(RuntimeError, "ranking_policy"):
            build_vector_index.validate_index_manifest(
                manifest,
                "abc123",
                require_chunk_manifest_hash=True,
            )


if __name__ == "__main__":
    unittest.main()
