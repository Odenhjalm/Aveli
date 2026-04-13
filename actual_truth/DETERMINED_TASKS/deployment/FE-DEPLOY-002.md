- TASK ID: FE-DEPLOY-002
- TYPE: DEPLOYMENT_CORRECTION
- LAUNCH CLASSIFICATION: BLOCKER
- DOMAIN TAG: deployment/source-build-correction
- ORDER: 002
- DESCRIPTION: Correct the public frontend deployment surface only after FE-DEPLOY-001 and FE-DEPLOY-001B pass. The correction path must use the intended source build path and must preserve backend-only frontend authority.
- DEPENDS_ON: [FE-DEPLOY-001B]
- PROMPT:
```text
Correct the public frontend deployment surface by producing a Netlify source build from the intended production source of truth. Do not use raw netlify deploy --dir uploads. Record the deploy id and commit ref. Preserve the backend-only dumb-renderer contract and do not modify backend systems.
```
- MUTATION POLICY: DEPLOYMENT_SURFACE_ONLY_WHEN_GATE_AUTHORIZED
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_ADDED: NONE
