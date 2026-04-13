- TASK ID: FE-DEPLOY-001B
- TYPE: GATE
- LAUNCH CLASSIFICATION: BLOCKER
- DOMAIN TAG: deployment/supabase-env-isolation
- ORDER: 001B
- DESCRIPTION: Verify that Netlify production environment and build context do not contain Supabase-related frontend environment authority. This gate is inserted between FE-DEPLOY-001 and FE-DEPLOY-002 and must fail closed on any residue or implicit fallback.
- DEPENDS_ON: [FE-DEPLOY-001]
- PROMPT:
```text
Verify that no Supabase-related environment variables (SUPABASE_*, NEXT_PUBLIC_SUPABASE_*, FLUTTER_SUPABASE_*) exist in Netlify production environment or build context. Confirm that the build does not depend on them implicitly or via fallback.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_ADDED: NONE
