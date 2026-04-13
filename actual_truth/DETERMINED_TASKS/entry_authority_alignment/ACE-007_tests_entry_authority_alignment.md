## TASK_ID
ACE-007

## TYPE
TEST_ALIGNMENT

## DEPENDS_ON
- ACE-006

## GOAL
Justera tester sa att de validerar den konsoliderade `entry-state` kontraktytan och routing-reglerna.

## EXACT CHANGES REQUIRED
- Uppdatera backendtester for `GET /entry-state` sa att de matchar den nya responseformen och forbjudna falt.
- Uppdatera frontendtester som skapar `EntryState` sa att de anvander nya falt och tar bort `isInvite`.
- Uppdatera routingtester sa att de inte forutsatter `profileDisplayName` for pre-entry routing.
- Uppdatera route-inventory-tester om klassificering eller enforcement kravs efter nya entry authority-regler.

## ACCEPTANCE CRITERIA
- Tester for `entry-state` verifierar exakt kontraktsfaltlista.
- Inga tester forutsatter `is_invite` eller profil som routing-input.
- Routingtester bekraftar att `/entry-state` ar enda routing-authority.

## VERIFICATION STEPS
- Kor backendtester for entry-state och route inventory.
- Kor frontendtester for routing och auth bootstrap.
