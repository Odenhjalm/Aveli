- TASK ID: FE-DEPLOY-003
- TYPE: ARTIFACT_VERIFICATION
- LAUNCH CLASSIFICATION: BLOCKER
- DOMAIN TAG: deployment/served-artifact-verification
- ORDER: 003
- DESCRIPTION: Verify the actual served Netlify artifact after the deployment correction. Repository source and Netlify metadata are insufficient unless the served bundle agrees with them.
- DEPENDS_ON: [FE-DEPLOY-002]
- PROMPT:
```text
Inspect the served https://app.aveli.app bundle and verify it contains https://aveli.fly.dev and contains no api.aveli.app, no .supabase.co host, no Supabase env keys, no getSessionFromUrl, and no Supabase config warning strings. Verify by served artifact inspection, not UI observation alone. Do not modify code, Netlify configuration, backend systems, or deployment state.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_ADDED: NONE
