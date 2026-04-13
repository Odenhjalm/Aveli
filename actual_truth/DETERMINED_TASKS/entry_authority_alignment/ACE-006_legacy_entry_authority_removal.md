## TASK_ID
ACE-006

## TYPE
LEGACY_REMOVAL

## DEPENDS_ON
- ACE-005

## GOAL
Avveckla kvarvarande legacy-floden som gor `/profiles/me` eller andra ytor till implicit entry authority.

## EXACT CHANGES REQUIRED
- Ta bort eventuella kvarvarande `is_invite`-beroenden i frontend och backend (utover `entry-state` som ar justerad i ACE-004).
- Avveckla routing- eller bootstrap-logik som fortfarande antar att `/profiles/me` maste laddas fore entry authority ar klar.
- Rensa legacy-helpers och utiliteter som anvander profil-data for att styra pre-entry routing.

## ACCEPTANCE CRITERIA
- Ingen routing- eller bootstrap-logik anvander `/profiles/me` som krav for entry decision.
- Inga `is_invite`-falta kvarstar i entry-authority-relaterad logik.
- Ingen legacy-entry-logik overlappas med `GET /entry-state`.

## VERIFICATION STEPS
- Soka efter `is_invite` och verifiera att det inte finns i entry authority-floden.
- Soka efter routing-beroenden av `/profiles/me` och verifiera att de ar borttagna eller uttryckligen decouplade fran entry beslut.
