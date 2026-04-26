import importlib.util
import io
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SEARCH_PYTHON = ROOT / ".repo_index" / ".search_venv" / "Scripts" / "python.exe"


def load_module(name: str, relative_path: str):
    module_path = ROOT / relative_path
    spec = importlib.util.spec_from_file_location(name, module_path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


codex_query = load_module("codex_query", "tools/index/codex_query.py")
analyze_results = load_module("analyze_results", "tools/index/analyze_results.py")
retrieval_observability = load_module(
    "retrieval_observability",
    "tools/index/retrieval_observability.py",
)


class DummyStream:
    def __init__(self) -> None:
        self.encoding = "cp1252"
        self.reconfigured_encoding = None

    def reconfigure(self, *, encoding: str) -> None:
        self.reconfigured_encoding = encoding


def assert_no_none(test_case: unittest.TestCase, value):
    if isinstance(value, dict):
        for key, item in value.items():
            test_case.assertIsNotNone(item, f"{key} unexpectedly emitted null")
            assert_no_none(test_case, item)
    elif isinstance(value, list):
        for item in value:
            assert_no_none(test_case, item)


class CodexQueryTests(unittest.TestCase):
    def test_prompt_template_is_cp1252_safe_and_keeps_english_evidence_keys(self) -> None:
        prompt = codex_query.build_prompt(
            "retrieval report",
            [
                {
                    "file": "actual_truth/contracts/retrieval/retrieval_contract.md",
                    "layer": "LAW",
                    "source_type": "chunk",
                    "score": 1.0,
                    "snippet": "Canonical retrieval evidence.",
                }
            ],
        )

        prompt.encode("cp1252")
        self.assertIn("If missing -> STOP", prompt)
        self.assertIn("FILE: actual_truth/contracts/retrieval/retrieval_contract.md", prompt)
        self.assertIn("SOURCE_TYPE: chunk", prompt)
        self.assertNotIn("\u2192", prompt)

    def test_stdio_is_reconfigured_to_utf8_for_windows_stdout(self) -> None:
        stdout = DummyStream()
        stderr = DummyStream()

        codex_query.configure_utf8_stdio(stdout=stdout, stderr=stderr)

        self.assertEqual(stdout.reconfigured_encoding, "utf-8")
        self.assertEqual(stderr.reconfigured_encoding, "utf-8")

    def test_main_builds_prompt_from_json_search_without_running_real_retrieval(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout='[{"file":"a.md","layer":"LAW","snippet":"hello","source_type":"chunk","score":1.0}]',
            stderr="",
        )

        with (
            mock.patch.object(codex_query, "require_canonical_interpreter"),
            mock.patch.object(codex_query, "configure_utf8_stdio"),
            mock.patch.object(codex_query, "run_search", return_value=completed),
            mock.patch.object(sys, "stdout", new_callable=io.StringIO) as stdout,
        ):
            exit_code = codex_query.main(["retrieval report"])

        self.assertEqual(exit_code, 0)
        self.assertIn("EVIDENCE 1", stdout.getvalue())
        self.assertIn("FILE: a.md", stdout.getvalue())


class AnalyzeResultsTests(unittest.TestCase):
    def test_parse_current_swedish_search_markers(self) -> None:
        text = """
================ RESULTAT ================

[SIMILARITET: 0.0000 | SLUTPOANG: 1.0000]
FIL: actual_truth/contracts/retrieval/retrieval_contract.md
------------------------------------------------------------
Retrieval contract text.
"""

        results = analyze_results.parse_results_text(text)

        self.assertEqual(len(results), 1)
        self.assertEqual(
            results[0]["file"],
            "actual_truth/contracts/retrieval/retrieval_contract.md",
        )
        self.assertIn("Retrieval contract text.", "\n".join(results[0]["content"]))

    def test_render_uses_classification_policy_not_deprecated_rules(self) -> None:
        manifest = {
            "classification_policy": {
                "default_layer": "OTHER",
                "precedence": [
                    {
                        "type": "path_substring",
                        "value": "actual_truth/contracts",
                        "layer": "LAW",
                    }
                ],
            }
        }
        results = [
            {
                "file": "actual_truth/contracts/retrieval/retrieval_contract.md",
                "content": ["Retrieval contract text."],
            }
        ]

        output = analyze_results.render_analysis(results, manifest)

        self.assertIn("LAW:", output)
        self.assertIn("actual_truth/contracts/retrieval/retrieval_contract.md", output)
        self.assertIn("SYSTEM LAW", output)


class RetrievalObservabilityTests(unittest.TestCase):
    def capture_write(self):
        writes = []
        patcher = mock.patch.object(
            retrieval_observability,
            "atomic_write_json",
            side_effect=lambda path, payload: writes.append((path, payload)),
        )
        return writes, patcher

    def test_model_health_uses_actual_model_authority_fields_without_nulls(self) -> None:
        writes, patcher = self.capture_write()
        runtime_state = {
            "model_authority": {
                "authority_path_text": ".repo_index/models/model_authority.json",
                "authority_root_text": ".repo_index/models",
                "local_files_only": True,
                "network_allowed": False,
                "cache_resolution_allowed": False,
                "models": {
                    "embedding": {
                        "model_id": "intfloat/e5-large-v2",
                        "model_revision": "f169b11e22de13617baa190a028a32f3493550b6",
                        "local_path_text": ".repo_index/models/embedding",
                        "model_snapshot_hash": "a" * 64,
                        "tokenizer_id": "intfloat/e5-large-v2",
                        "tokenizer_revision": "f169b11e22de13617baa190a028a32f3493550b6",
                        "tokenizer_files_hash": "b" * 64,
                        "tokenizer_files": {"tokenizer.json": "c" * 64},
                        "local_files_only": True,
                        "trust_remote_code": False,
                    },
                    "rerank": {
                        "model_id": "BAAI/bge-reranker-large",
                        "model_revision": "55611d7bca2a7133960a6d3b71e083071bbfc312",
                        "local_path_text": ".repo_index/models/rerank",
                        "model_snapshot_hash": "d" * 64,
                        "tokenizer_id": "BAAI/bge-reranker-large",
                        "tokenizer_revision": "55611d7bca2a7133960a6d3b71e083071bbfc312",
                        "tokenizer_files_hash": "e" * 64,
                        "tokenizer_files": {"tokenizer.json": "f" * 64},
                        "local_files_only": True,
                        "trust_remote_code": False,
                    },
                },
            }
        }

        with patcher:
            payload = retrieval_observability.write_retrieval_model_health(runtime_state)

        self.assertEqual(writes[0][1], payload)
        self.assertEqual(payload["authority_root"], ".repo_index/models")
        self.assertIn("model_snapshot_hash", payload["models"]["embedding"])
        self.assertNotIn("snapshot_hash", payload["models"]["embedding"])
        assert_no_none(self, payload)

    def test_dependency_health_uses_compact_d01_authority_without_nulls(self) -> None:
        writes, patcher = self.capture_write()
        build_id = "c" * 64
        runtime_state = {
            "dependency_authority": {
                "status": "PASS",
                "build_id": build_id,
                "result_authority": (
                    "actual_truth/DETERMINED_TASKS/retrieval_index_environment_dependencies/"
                    f"D01_environment_dependency_result_{build_id}.json"
                ),
                "target_interpreter_path": ".repo_index/.search_venv/Scripts/python.exe",
                "dependency_preparation_attempted": True,
                "package_versions_expected": {"chromadb": "1.5.5", "numpy": "2.4.3"},
                "package_source_verification": {"status": "PASS"},
                "network_verification": {"status": "PASS"},
                "fallback_verification": {"status": "PASS"},
            }
        }

        with patcher:
            payload = retrieval_observability.write_retrieval_dependency_health(runtime_state)

        self.assertEqual(writes[0][1], payload)
        self.assertEqual(payload["package_count"], 2)
        self.assertEqual(payload["package_source_verification"], "PASS")
        self.assertNotIn("approval_artifact", payload)
        self.assertNotIn("d01_execution_status", payload)
        self.assertNotIn("installed_package_verification", payload)
        self.assertNotIn("import_readiness_verification", payload)
        self.assertNotIn("package_hash_verification", payload)
        assert_no_none(self, payload)

    def test_last_build_status_uses_promotion_completed_at_without_nulls(self) -> None:
        writes, patcher = self.capture_write()
        promotion_result = {
            "status": "PASS",
            "promotion_started_at_utc": "2026-04-24T23:44:10Z",
            "promotion_completed_at_utc": "2026-04-24T23:45:14Z",
            "build_mode": "INITIAL_BUILD",
        }
        with (
            patcher,
            mock.patch.object(
                retrieval_observability,
                "read_build_lineage",
                return_value={
                    "active_build_id": "c" * 64,
                    "manifest_state": "ACTIVE_VERIFIED",
                    "corpus_size": 1908,
                },
            ),
            mock.patch.object(
                retrieval_observability,
                "load_json_object",
                return_value=promotion_result,
            ),
        ):
            payload = retrieval_observability.write_retrieval_last_build_status()

        self.assertEqual(writes[0][1], payload)
        self.assertEqual(payload["promotion_completed_at_utc"], "2026-04-24T23:45:14Z")
        self.assertNotIn("completed_at_utc", payload)
        self.assertNotIn("promotion_occurred", payload)
        assert_no_none(self, payload)


if __name__ == "__main__":
    if Path(sys.executable).resolve() != CANONICAL_SEARCH_PYTHON.resolve():
        raise SystemExit(
            "FEL: retrieval/indexering maste koras med kanonisk Windows-tolk: "
            f"{CANONICAL_SEARCH_PYTHON}"
        )
    unittest.main()
