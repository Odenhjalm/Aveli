## DAG
ACE-004 -> ACE-005 -> ACE-006 -> ACE-007 -> ACE-008

## Varfor denna DAG finns
Kontraktskonsolideringen (ACE-001 till ACE-003) fastslar att `GET /entry-state` ar den enda post-auth routing-ytan och att inga andra kontrakt far definiera entry authority. Repoet ar fortfarande i drift mot dessa kontrakt. Denna DAG ar blocker-resolution innan ny implementering kan godkannas.

## Drift (identifierad mot konsoliderad kontraktssanning)
- Backend `GET /entry-state` returnerar forbjudet faltet `is_invite` och saknar kravda fält `onboarding_state`, `role_v2`, `role`, `is_admin`.
- Backend schema `EntryStateResponse` matchar inte kontraktet (saknar fält, innehaller forbjudet fält).
- Frontend `EntryState` modell matchar inte kontraktet och innehaller forbjudet `isInvite`.
- Frontend routing anvander `profileDisplayName` från `/profiles/me` for att valja pre-entry rutt, vilket gor `/profiles/me` till routing-input.
- Auth bootstrap hydraterar `/profiles/me` som en del av routing-beroende sessionstart.
- Tester i backend och frontend forutsatter gammal `entry-state` form (inkluderar `is_invite` och saknar nya fält).
- Flera backend-rutter anvander `CurrentUser` utan tydlig app-entry enforcement; detta maste justeras eller klassificeras explicit som pre-entry enligt entry authority law.

## Vad varje task laser
- ACE-004: Laser backendens `entry-state` kontraktyta och schema mot den konsoliderade kontraktssanningen.
- ACE-005: Laser frontendens routing och entry-state konsumtion mot kontraktet och tar bort profil-bootstrapping som routing-beroende.
- ACE-006: Tar bort legacy-falt och legacy-floden som inte far styra entry authority.
- ACE-007: Justerar testerna till ny kontraktyta och routing-logik.
- ACE-008: Verifierar att alignments ar genomforda och att inga kvarvarande entry authority-overlapp finns.

## Varfor ACE-004+ ar blockerade fram tills denna DAG ar klar
Utan dessa alignments finns fortsatt drift mot forbjudna fält och oacceptabla routing-beroenden. Det gor senare implementationer instabila och icke-deterministiska mot kontrakten.

## Markering
Denna task-tree ar pre-implementation och no-code audit-driven. Den skapar endast alignments for att verkstallda kontrakt ska bli verklig sanning i kod och tester.
