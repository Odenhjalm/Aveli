# TA-014

- TASK_ID: `TA-014`
- TYPE: `AGGREGATE`
- CLUSTER: `AGGREGATE`
- DESCRIPTION: `Rerun the full test-to-Newbaseline diff only after all cluster gates pass and regenerate the failing-test classification from current runtime evidence.`
- TARGET_FILES:
  - `actual_truth/DETERMINED_TASKS/test_alignment/task_manifest.json`
  - `/tmp/aveli_pytest_contract_diff.log`
  - `backend/tests`
  - `backend/context7/tests`
  - `test_email_verification.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `TA-013`

