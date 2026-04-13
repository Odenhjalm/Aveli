- TASK ID: FE-DEPLOY-005
- TYPE: REPO_HYGIENE_GATE
- LAUNCH CLASSIFICATION: PRE_LAUNCH_REQUIRED
- DOMAIN TAG: deployment/repo-hygiene
- ORDER: 005
- DESCRIPTION: Audit repository hygiene only after the served artifact and localization gates pass. This task must separate deploy-surface blockers from repository cleanup findings and must not collapse cleanup into deployment correction.
- DEPENDS_ON: [FE-DEPLOY-004]
- PROMPT:
```text
Audit repo hygiene for hidden frontend Supabase SDK dependency or imports after the served artifact passes. Confirm whether supabase_flutter remains necessary or must be removed before launch. Separate deployment-surface blockers from repo-hygiene findings. Do not implement, do not modify code, do not mutate Netlify configuration, backend systems, or deployment state.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_ADDED: NONE
