## TASK_ID
ACE-008

## TYPE
VERIFICATION_GATE

## DEPENDS_ON
- ACE-007

## GOAL
Verifiera att repoet nu overensstammer med konsoliderad entry authority och att ingen overlappande routing-authority finns kvar.

## EXACT CHANGES REQUIRED
- Inga kodandringar. Detta ar en ren verifieringsgate efter alignment.

## ACCEPTANCE CRITERIA
- `GET /entry-state` ar den enda post-auth routing-authority i kod och tester.
- `/profiles/me` anvands inte for routing eller bootstrap-beslut.
- Inga forbjudna falt exponeras via entry-state.
- Membership ensam ger inte app-entry utan entry-state-derivation.

## VERIFICATION STEPS
- Kor entry-state tester och verifiera kontraktets faltlista.
- Kor routingtester i frontend och verifiera att entry beslut baseras pa entry-state.
- Bekrafta att route inventory enforcement ar kompatibel med entry authority law.
