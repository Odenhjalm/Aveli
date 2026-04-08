# PLAN_UNBLOCK_EXECUTE_CORE_VALIDATION

## Syfte

Denna plan definierar den minsta kanoniska auktoritetsreparation som krävs för att låsa upp execute-mode kärnvalidering för onboarding, teacher rights och media-upload route authority utan att göra några runtime- eller databasmutationer i detta steg.

## Nuvarande blockeringssammanfattning

- Exakt gap 1: Det finns ingen primär kontraktfil under `actual_truth/contracts/` som definierar `onboarding_state`, `role`, `role_v2`, `is_admin`, teacher-rights ägarskap och den kanoniska muteringsvägen för användarskapande, onboarding-slutförande och teacher-rights tilldelning.
- Exakt gap 2: `actual_truth/system_runtime_rules.md` är den primära route-auktoriteten, men den nuvarande filen listar bara playback, courses och delar av studio och lämnar auth, onboarding, admin, connect, media och upload i konflikt med observerande auditdokument.
- Exakt gap 3: Det finns ingen primär kontraktbeslutspunkt som väljer en enda kanonisk media-uploadyta mellan lesson-scoped studio upload, generell media-signing och äldre uploadytor.
- Konsekvens: `TASK_CONFIRM_BASELINE_ONBOARDING_READINESS` kan inte bli `READY`, och `TASK_EXEC_CORE_SYSTEM_VALIDATION` måste förbli `DEFERRED`.

## Auktoritetsmatris

| Domän | Källa | Klass | Beslut |
| --- | --- | --- | --- |
| onboarding state och role authority | `actual_truth/contracts/onboarding_teacher_rights_contract.md` | `MISSING` | Denna fil ska skapas och bli den enda primära kontraktauktoriteten för onboarding state, role-fält och teacher-rights kontraktstillstånd. |
| onboarding state och role authority | `codex/AVELI_EXECUTION_POLICY.md` | `MIRROR` | Policyn namnger kanoniska fält men får inte fortsätta bära affärskontraktstillstånd ensam. |
| onboarding state och role authority | `Aveli_System_Decisions.md` | `MIRROR` | Beslutslagret ger semantisk ram och fokus, men inte det detaljerade kontraktstillståndet. |
| onboarding state och role authority | `aveli_system_manifest.json` | `MIRROR` | Manifestet bekräftar fokus och externa beroenden, men definierar inte onboarding/role-kontraktet. |
| onboarding state och role authority | `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md` | `OBSERVATIONAL` | Visar observerade auth- och onboardingytor men kan inte bära kanoniskt kontraktstillstånd. |
| onboarding state och role authority | `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md` | `OBSERVATIONAL` | Visar observerad frontend/runtime-passning för auth, inte primärt kontraktstillstånd. |
| onboarding state och role authority | `docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md` | `OBSERVATIONAL` | Visar observerad claims-härledning via `profiles.role_v2`, `profiles.is_admin` och `is_teacher_user()`. |
| onboarding state och role authority | `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md` | `OBSERVATIONAL` | Visar observerade authflöden, inte kontraktsägarskap. |
| onboarding state och role authority | `actual_truth/DETERMINED_TASKS/doc_execute_readiness/TASK_DOC_ONBOARDING_AND_TEACHER_AUTHORITY_AUDIT.md` | `MIRROR` | Härledd uppgift, inte primär sanning. |
| teacher-rights mutation authority | `actual_truth/contracts/onboarding_teacher_rights_contract.md` | `MISSING` | Samma nya kontraktfil ska bli enda primära källa för teacher-rights ägarskap och muteringsväg. |
| teacher-rights mutation authority | `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md` | `OBSERVATIONAL` | Observerar `/admin/teachers/{user_id}/approve` och relaterade ytor, men kan inte vara primär mutation authority. |
| teacher-rights mutation authority | `docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md` | `OBSERVATIONAL` | Observerar claims, tabeller och enforcement, men avgör inte ensam mutation authority. |
| teacher-rights mutation authority | `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md` | `OBSERVATIONAL` | Observerar relation mellan auth och teacher-tabeller, men inte kanoniskt muteringsägarskap. |
| teacher-rights mutation authority | `codex/AVELI_EXECUTION_POLICY.md` | `MIRROR` | Policyn kräver role-logik men definierar inte ensam mutation path. |
| teacher-rights mutation authority | `actual_truth/DETERMINED_TASKS/doc_execute_readiness/TASK_DOC_ONBOARDING_AND_TEACHER_AUTHORITY_AUDIT.md` | `MIRROR` | Härledd reparationsuppgift, inte primär sanning. |
| active runtime route authority | `actual_truth/system_runtime_rules.md` | `PRIMARY` | Denna fil är redan utsedd som primär route-auktoritet och måste repareras där, inte i auditnoterna. |
| active runtime route authority | `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md` | `OBSERVATIONAL` | Observerad routeinventering från repo och notering om vissa omonterade routers. |
| active runtime route authority | `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md` | `OBSERVATIONAL` | Observerad frontend mot mounted backend-passning för utvalda ytor. |
| active runtime route authority | `docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md` | `OBSERVATIONAL` | Observerad notering om monterad vs legacy auth. |
| active runtime route authority | `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md` | `OBSERVATIONAL` | Observerade flöden och routepåståenden, inte primär active-runtime authority. |
| active runtime route authority | `actual_truth/DETERMINED_TASKS/doc_execute_readiness/TASK_CONFIRM_BASELINE_ONBOARDING_READINESS.md` | `MIRROR` | Härledd readiness-gate, inte primär route-auktoritet. |
| media upload authority | `actual_truth/contracts/lesson_media_edge_contract.md` | `PRIMARY` | Denna befintliga kontraktfil ska utökas och bli den enda primära upload/write-auktoriteten för lesson-scoped media upload. |
| media upload authority | `actual_truth/contracts/media_unified_authority_contract.md` | `MIRROR` | Denna fil förblir primär för renderkedjan men inte för upload-sign-complete-beslutet. |
| media upload authority | `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md` | `OBSERVATIONAL` | Visar flera observerade uploadytor: presign/complete, multipart och `/api/upload/course-media`. |
| media upload authority | `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md` | `OBSERVATIONAL` | Visar aktiv mismatch för `/api/media/sign` mot `/media/sign`. |
| media upload authority | `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md` | `OBSERVATIONAL` | Visar splittrad bild mellan `/media/presign`, `/media/sign` och lesson-scoped studio upload. |
| media upload authority | `actual_truth/DETERMINED_TASKS/doc_execute_readiness/TASK_EXEC_CORE_SYSTEM_VALIDATION.md` | `MIRROR` | Härledd execute-uppgift, inte primär upload authority. |
| media render authority | `actual_truth/contracts/media_unified_authority_contract.md` | `PRIMARY` | Detta är den enda primära renderauktoriteten. |
| media render authority | `actual_truth/contracts/lesson_media_edge_contract.md` | `MIRROR` | Speglar studio-surface-regler under den enhetliga renderkedjan. |
| media render authority | `Aveli_System_Decisions.md` | `MIRROR` | Beslutslagret bekräftar `runtime_media` och `backend_read_composition`, men detaljrenderkontraktet ligger i kontrakten. |
| media render authority | `aveli_system_manifest.json` | `MIRROR` | Manifestet speglar samma renderkedja som styrande regelkontext. |
| media render authority | `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md` | `OBSERVATIONAL` | Visar observerade read-signing-ytor, inte den primära renderauktoriteten. |
| media render authority | `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md` | `OBSERVATIONAL` | Visar observerat mediaflöde, inte primär renderlag. |

## Minimal primär reparationsmängd

### Exakta filer att skapa

- `actual_truth/contracts/onboarding_teacher_rights_contract.md`

### Exakta filer att uppdatera

- `actual_truth/system_runtime_rules.md`
- `actual_truth/contracts/lesson_media_edge_contract.md`
- `codex/AVELI_EXECUTION_POLICY.md`

### Exakta filer att uppdatera nedströms som observationslager

- `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md`
- `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`
- `docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md`
- `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`
- `actual_truth/rule_layers/CONTRACT.md`

## Explicit auktoritetsbeslut

### Primär fil för onboarding och teacher rights

- Vald primär fil: `actual_truth/contracts/onboarding_teacher_rights_contract.md`
- Skäl: Den saknade kontraktauktoriteten måste ligga under `actual_truth/contracts/` enligt OS-regeln om kontraktauktoritet, och samma fil ska bära både onboarding state och teacher-rights kontraktstillstånd för att undvika dubbel primärauktoritet.

### Primär fil för aktiv runtime route surface

- Vald primär fil: `actual_truth/system_runtime_rules.md`
- Skäl: Den filen är redan definierad som primär active-runtime authority och måste därför repareras där i stället för i auditdokumenten.

### Auktoritetsbeslut för media upload

- Vald primär kontraktyta: `actual_truth/contracts/lesson_media_edge_contract.md`
- Vald kanonisk write-surface för teacher lesson media: `POST /studio/lessons/{lesson_id}/media/presign` följt av `POST /studio/lessons/{lesson_id}/media/complete`
- Beslut för read/signing: `POST /media/sign` och `GET /media/stream/{token}` är read/signing-surfaces och får inte definiera upload authority
- Beslut för observations- eller deprecated-ytor tills de är reconcilerade:
  - `POST /api/media/sign`
  - `POST /media/presign`
  - `POST /studio/lessons/{lesson_id}/media`
  - `POST /api/upload/course-media`

## Ordnad remedieringssekvens

### Steg 1

- Skapa `actual_truth/contracts/onboarding_teacher_rights_contract.md`
- Acceptance criteria:
  - filen definierar `onboarding_state`, `role`, `role_v2` och `is_admin` som ett enda kontraktstillstånd
  - filen definierar teacher-rights ägarskap explicit
  - filen definierar exakt en kanonisk muteringsväg för användarskapande, onboarding completion och teacher-rights tilldelning eller approval
  - filen markerar alla auditdokument som observationslager, inte primära kontrakt

### Steg 2

- Uppdatera `actual_truth/system_runtime_rules.md`
- Acceptance criteria:
  - filen förblir enda primära route-auktoritet
  - filen löser uttryckligen mounted status för de rutter som execute-mode kärnvalidering behöver
  - filen löser uttryckligen mounted status för auth, onboarding, teacher-rights mutation och vald media upload-surface
  - auditdokument får inte längre kunna motsäga aktiv route truth utan att klassas som observationsdrift

### Steg 3

- Uppdatera `actual_truth/contracts/lesson_media_edge_contract.md`
- Acceptance criteria:
  - filen definierar en enda kanonisk upload/write-surface för lesson media
  - filen skiljer tydligt mellan upload authority och render authority
  - filen klassar `/media/sign` som read/signing only
  - filen klassar övriga observerade uploadytor som observational eller deprecated tills de har reconcilerats

### Steg 4

- Uppdatera `codex/AVELI_EXECUTION_POLICY.md`
- Acceptance criteria:
  - policyn pekar på kontraktauktoriteten i `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - policyn slutar implicit fungera som ensam kontraktbärare för onboardingfält
  - policyn förblir konsekvent med auth/storage external-dependency-reglerna i decisions och manifest

### Steg 5

- Uppdatera observationslagret
- Acceptance criteria:
  - `API_CATALOG.md`, `API_USAGE_DIFF.md`, `SECURITY_REVIEW.md` och `E2E_FLOWS.md` beskriver sig själva som observations- eller auditbevis där primär sanning ligger i kontrakt eller runtime rules
  - inga auditdokument presenterar aktiv route truth eller upload authority i konflikt med primärkällorna
  - `actual_truth/rule_layers/CONTRACT.md` regenereras efter kontraktändringarna

## Explicit unblock-kriterier för execute-mode core validation

- `actual_truth/contracts/onboarding_teacher_rights_contract.md` finns och är den enda primära kontraktfilen för onboarding state och teacher rights
- `actual_truth/system_runtime_rules.md` definierar en entydig active-runtime inventory för alla in-scope execute-rutter
- `actual_truth/contracts/lesson_media_edge_contract.md` definierar en entydig lesson-media upload authority
- `actual_truth/contracts/media_unified_authority_contract.md` förblir enda primära renderauktoriteten
- inga observerande auditdokument motsäger primärkällorna i in-scope domäner
- `TASK_CONFIRM_BASELINE_ONBOARDING_READINESS` kan returnera `READY` utan att gissa schemafält, route-mount eller mutation boundary

## STOP-villkor

- STOP om den nya onboarding/teacher-rights-kontraktfilen inte kan välja ett enda teacher-rights ägarskap mellan `app.teacher_approvals`, `app.teacher_permissions`, `app.teachers`, profil-rollfält eller en explicit sammansättning av dessa
- STOP om `actual_truth/system_runtime_rules.md` inte kan bevisa eller uttryckligen avgränsa mounted status för auth, onboarding, teacher-rights mutation och vald uploadyta
- STOP om `lesson_media_edge_contract.md` inte kan välja en enda upload/write-surface utan att lämna flera aktiva kandidater
- STOP om något observationsdokument fortsätter att bära primär auktoritet för route truth eller upload authority

## Utanför scope i denna fas

- runtime-kodändringar
- databasändringar eller RLS-reparationer
- seedning eller uploadtester
- execute-mode validering
- Stripe Connect affärslogik utanför det som krävs för att avgränsa route authority
- bred route-reconciliation för community, seminars, payments eller andra domäner utanför execute core validation
- omdesign av media renderkedjan

## Första implementeringssteg efter plan-godkännande

- Skapa `actual_truth/contracts/onboarding_teacher_rights_contract.md` och definiera där den enda kanoniska kontraktauktoriteten för onboarding state, role-fält, teacher-rights ägarskap och mutation path.
