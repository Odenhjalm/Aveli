import hashlib
import importlib.util
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


class BuildVectorIndexManifestCorpusTests(unittest.TestCase):
    def test_corpus_manifest_hash_uses_canonical_serialization(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            (temp_path / "a.py").write_text("print('a')  \r\n", encoding="utf-8")
            (temp_path / "b.md").write_text("# B\t\n", encoding="utf-8")

            previous_root = build_vector_index.ROOT
            build_vector_index.ROOT = temp_path
            try:
                files = ["a.py", "b.md"]
                manifest = build_vector_index.build_canonical_index_manifest(
                    "placeholder",
                    corpus_files=files,
                )

                corpus_files = build_vector_index.load_manifest_corpus_files(manifest)
                serialization = build_vector_index.render_canonical_corpus_serialization(corpus_files)
                corpus_hash = build_vector_index.compute_corpus_manifest_hash(corpus_files)

                self.assertEqual(corpus_files, files)
                self.assertEqual(corpus_hash, hashlib.sha256(serialization).hexdigest())
                self.assertTrue(serialization.startswith(b"AVELI_CORPUS_NORMALIZATION_V1\n"))
            finally:
                build_vector_index.ROOT = previous_root

    def test_manifest_corpus_files_fail_closed_on_unstable_order(self) -> None:
        manifest = build_vector_index.build_canonical_index_manifest(
            "deadbeef",
            corpus_files=["b.md", "a.py"],
        )

        with self.assertRaisesRegex(RuntimeError, "sorterad"):
            build_vector_index.load_manifest_corpus_files(manifest)

    def test_initial_build_derives_corpus_manifest_hash_in_memory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            (temp_path / "a.py").write_text("print('a')\n", encoding="utf-8")

            previous_root = build_vector_index.ROOT
            previous_model_config = build_vector_index.get_embedding_model_config
            previous_embedding_policy = build_vector_index.get_embedding_policy
            previous_build_device = build_vector_index.resolve_manifest_build_device
            previous_batch_size = build_vector_index.get_embedding_batch_size
            build_vector_index.ROOT = temp_path
            build_vector_index.get_embedding_model_config = lambda manifest, model_authority=None: {}
            build_vector_index.get_embedding_policy = lambda manifest: {}
            build_vector_index.resolve_manifest_build_device = lambda manifest: "cpu"
            build_vector_index.get_embedding_batch_size = lambda manifest: 64
            try:
                files = ["a.py"]
                computed_hash = build_vector_index.compute_corpus_manifest_hash(files)
                manifest = build_vector_index.build_canonical_index_manifest(
                    "stale",
                    corpus_files=files,
                    embedding_model="embedding-model",
                    rerank_model="rerank-model",
                )

                build_vector_index.validate_index_manifest(
                    manifest,
                    computed_hash,
                    require_chunk_manifest_hash=False,
                    build_mode=build_vector_index.INITIAL_BUILD_MODE,
                )

                self.assertEqual(manifest["corpus_manifest_hash"], computed_hash)
            finally:
                build_vector_index.ROOT = previous_root
                build_vector_index.get_embedding_model_config = previous_model_config
                build_vector_index.get_embedding_policy = previous_embedding_policy
                build_vector_index.resolve_manifest_build_device = previous_build_device
                build_vector_index.get_embedding_batch_size = previous_batch_size

    def test_rebuild_keeps_strict_corpus_manifest_hash_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            (temp_path / "a.py").write_text("print('a')\n", encoding="utf-8")

            previous_root = build_vector_index.ROOT
            build_vector_index.ROOT = temp_path
            try:
                files = ["a.py"]
                computed_hash = build_vector_index.compute_corpus_manifest_hash(files)
                manifest = build_vector_index.build_canonical_index_manifest(
                    "stale",
                    corpus_files=files,
                    embedding_model="embedding-model",
                    rerank_model="rerank-model",
                )

                with self.assertRaisesRegex(RuntimeError, "corpus_manifest_hash"):
                    build_vector_index.validate_index_manifest(
                        manifest,
                        computed_hash,
                        require_chunk_manifest_hash=False,
                        build_mode=build_vector_index.REBUILD_MODE,
                    )

                self.assertEqual(manifest["corpus_manifest_hash"], "stale")
            finally:
                build_vector_index.ROOT = previous_root

    def test_validate_index_manifest_hard_stops_on_policy_drift(self) -> None:
        manifest = build_vector_index.build_canonical_index_manifest(
            "abc123",
            "chunk123",
            corpus_files=["a.py"],
        )
        manifest["ranking_policy"] = {"formula": "private_score"}

        with self.assertRaisesRegex(RuntimeError, "ranking_policy"):
            build_vector_index.validate_index_manifest(
                manifest,
                "abc123",
                require_chunk_manifest_hash=True,
            )


if __name__ == "__main__":
    unittest.main()
