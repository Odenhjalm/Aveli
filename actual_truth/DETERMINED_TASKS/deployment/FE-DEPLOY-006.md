- TASK ID: FE-DEPLOY-006
- TYPE: GO_LIVE_GATE
- LAUNCH CLASSIFICATION: BLOCKER
- DOMAIN TAG: deployment/final-go-live-gate
- ORDER: 006
- DESCRIPTION: Run the final no-code frontend go-live gate only after all prior deployment remediation gates pass. This gate must prove the production frontend is aligned with backend-only authority and public launch constraints.
- DEPENDS_ON: [FE-DEPLOY-005]
- PROMPT:
```text
Run the final no-code frontend go-live gate against Netlify metadata, served bundle, backend health/readiness, CORS, Supabase isolation, and Swedish launch-critical text. Confirm repo truth, deployment metadata, served artifact, backend HTTP behavior, and config comparison all agree. Do not implement, do not modify code, do not mutate Netlify configuration, backend systems, or deployment state, and do not deploy.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_ADDED: NONE
