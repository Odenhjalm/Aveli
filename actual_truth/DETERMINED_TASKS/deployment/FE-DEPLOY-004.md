- TASK ID: FE-DEPLOY-004
- TYPE: LOCALIZATION_GATE
- LAUNCH CLASSIFICATION: PRE_LAUNCH_REQUIRED
- DOMAIN TAG: deployment/localization
- ORDER: 004
- DESCRIPTION: Verify launch-critical user-facing frontend copy after the served artifact passes backend-authority verification. Product-facing text must be Swedish on the production-critical path; debug and internal strings must be classified separately.
- DEPENDS_ON: [FE-DEPLOY-003]
- PROMPT:
```text
Verify launch-critical user-facing frontend text on the served production-critical path is Swedish. Classify non-critical debug/internal strings separately. Do not infer from repository source alone; verify the served artifact and production-critical path. Do not modify code, copy, Netlify configuration, backend systems, or deployment state.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_ADDED: NONE
