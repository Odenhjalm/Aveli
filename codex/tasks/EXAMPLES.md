# AVELI TASK EXAMPLES (DETERMINISTIC)

Start every task in a new branch:
`./codex/scripts/start-task-branch.sh "<task-name>"`

---

# 🚨 RULE

NEVER ask Codex to “implement a feature” directly.

ALL tasks MUST follow or be a part of:

```text
DISCOVER → CONTRACT DIFF → TASK GENERATION → EXECUTION
```

---

# 🧠 STANDARD TASK PATTERN

## 1) DISCOVER + DIFF (MANDATORY)

```text
/agent

Audit <AREA> using full retrieval pipeline:

- use semantic search
- use lexical search
- use index

Identify:
- legacy fields
- fallback paths
- secondary resolver paths
- contract violations

Compare against:
- contracts/
- Aveli_System_Decisions.md
- aveli_system_manifest.json

Output:
- DIFF MATRIX
- FAIL / UNKNOWN only
```

---

## 2) GENERATE TASKS

```text
/agent

Generate deterministic OWNER tasks from diff:

- each violation → one task
- include:
  TYPE
  DEPENDS_ON
  SCOPE
  STOP CONDITIONS

Write tasks to:
actual_truth/DETERMINED_TASKS/
```

---

## 3) EXECUTE TASK

```text
/agent

Execute task:

<TASK_PATH>

- run retrieval first
- apply policy automatically
- implement minimal mutation
- verify strictly

Output:
PASS or STOPPED
```

---

# 🧩 EXAMPLES

---

## MEDIA SYSTEM CLEANUP

```text
/agent

Audit media system:

- detect:
  download_url
  signed_url
  playback_url
  fallback branches

- map:
  LAW → ROUTE → SERVICE → HELPER → SCHEMA → TEST

Generate tasks to:
- remove legacy fields
- remove fallback
- enforce canonical media object
```

---

## STUDIO MEDIA FLOW

```text
/agent

Discover studio media flow:

- verify:
  runtime_media → backend_read_composition → resolved_url

- detect:
  any alternative resolver
  any dynamic playback_url usage

Generate tasks to align flow with canonical contract
```

---

## PROFILE / COMMUNITY MEDIA

```text
/agent

Audit profile media contract:

- detect:
  download_url
  signed_url
  legacy schema fields

- verify:
  media = { media_id, state, resolved_url }

Generate tasks for:
- schema alignment
- backend composition
- frontend rendering
```

---

## TEST ALIGNMENT

```text
/agent

Audit test layer:

- detect tests asserting:
  download_url
  signed_url
  fallback behavior

- verify against canonical contracts

Generate tasks to:
- remove legacy assertions
- align tests with canonical truth
```

---

## AUTH / ONBOARDING (FUTURE)

```text
/agent

Audit onboarding system:

- map:
  LAW → ROUTE → SERVICE → DB

- detect:
  schema mismatch
  missing fields
  fallback logic

Generate tasks to:
- align schema
- enforce canonical onboarding flow
```

---

# 🧠 MENTAL MODEL

Codex is NOT a developer.

Codex is:

```text
SYSTEM OPERATOR
```

---

# 🔥 FINAL RULE

NEVER:

```text
/agent implement X
```

ALWAYS:

```text
/agent discover → diff → task → execute
```
