- TASK ID: FE-DEPLOY-001
- TYPE: GATE
- LAUNCH CLASSIFICATION: BLOCKER
- DOMAIN TAG: deployment/env-verification
- ORDER: 001
- DESCRIPTION: Verify the Netlify production build environment before any deployment correction. Confirm that the frontend production build is configured to target the canonical backend authority and that required frontend build variables are present. This gate must be read-only and must fail closed on uncertainty.
- DEPENDS_ON: []
- PROMPT:
```text
Verify Netlify production build environment for the frontend. Confirm FLUTTER_API_BASE_URL is https://aveli.fly.dev and required Flutter build variables are present. Confirm the build context cannot resolve to localhost, api.aveli.app, or any non-canonical backend authority. Do not implement, do not modify code, do not mutate Netlify configuration, and do not deploy.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_ADDED: NONE
