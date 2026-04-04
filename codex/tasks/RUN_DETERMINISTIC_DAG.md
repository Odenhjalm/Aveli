# RUN DETERMINISTIC TASK DAG (GENERIC)

LOAD: codex/AVELI_OPERATING_SYSTEM.md
LOAD: codex/AVELI_EXECUTION_POLICY.md

MODE:
execute

TASK:
Execute a deterministic task DAG based on provided TASK_ORDER and BASE_PATH.

---

INPUT (REQUIRED):

TASK_ORDER:

- <TASK_ID_1>
- <TASK_ID_2>
- ...

BASE_PATH:
<ABSOLUTE_OR_RELATIVE_PATH_TO_TASKS>

---

EXECUTION MODEL:

FOR EACH TASK IN TASK_ORDER:

---

STATE 1 — LOAD TASK

- resolve:
  BASE_PATH + TASK_ID

- read:
  PURPOSE
  SCOPE
  STOP CONDITIONS
  VERIFICATION RULES
  DEPENDS_ON

---

STATE 2 — DEPENDENCY CHECK

- verify all DEPENDS_ON tasks are completed

STOP if:

- dependency not satisfied

---

STATE 3 — FULL RETRIEVAL

MUST use:

- semantic search
- lexical search
- index

Build:

LAW → ROUTE → SERVICE → HELPER → SCHEMA → TEST

---

STATE 4 — PLAN CHECK

STOP if:

- canonical replacement missing
- conflicting truths detected
- scope incomplete

---

STATE 5 — EXECUTION

IF TYPE = OWNER:

- apply minimal mutation

IF TYPE = VERIFY:

- run verification only

---

STATE 6 — HARD VERIFY

- grep:
  download_url
  signed_url
  playback_url
  preferredUrl

- run:
  scoped tests

---

STATE 7 — VALIDATE

confirm:

- runtime_media is sole truth
- backend_read_composition is only authority
- frontend is render-only
- no fallback exists
- no secondary resolver exists

---

STATE 8 — RESULT

IF FAIL:

TASK: <TASK_ID>
RESULT: STOPPED

BLOCKER:

- file
- line
- reason

HALT ENTIRE DAG

---

IF PASS:

CONTINUE to next task

---

FINAL OUTPUT:

## FINAL SERIES STATUS

- each task: PASS / STOPPED
- remaining blockers
- system state:
  CLEAN / PARTIAL / BROKEN

---

GLOBAL RULES:

- NEVER ask about resolved decisions
- NEVER introduce fallback
- NEVER expand scope
- ALWAYS use retrieval pipeline
- ALWAYS respect contracts

---

STOP CONDITIONS (GLOBAL):

- hidden dependency detected
- legacy field exists
- contract violation detected

---

Codex must confirm:
AVELI OPERATING SYSTEM LOADED

If missing:
STOP
