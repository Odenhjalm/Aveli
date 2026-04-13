## TASK_ID
ACE-004

## TYPE
BACKEND_ALIGNMENT

## DEPENDS_ON
- []

## GOAL
Justera backendens `GET /entry-state` och `EntryStateResponse` sa att ytan ar den enda post-auth routing-authority och exakt matchar kontraktet.

## EXACT CHANGES REQUIRED
- Uppdatera `EntryStateResponse` i `backend/app/schemas/__init__.py` till endast tillatna fält: `can_enter_app`, `onboarding_state`, `onboarding_completed`, `membership_active`, `needs_onboarding`, `needs_payment`, `role_v2`, `role`, `is_admin`.
- Ta bort forbjudna fält fran schema och response, inklusive `is_invite`.
- Uppdatera `backend/app/routes/entry_state.py` sa att response inkluderar `onboarding_state`, `role_v2`, `role`, `is_admin`.
- Harleda `onboarding_completed` enbart fran `onboarding_state == "completed"`.
- Harleda `can_enter_app` som `onboarding_completed && membership_active`.
- Harleda `needs_onboarding` och `needs_payment` utan invite-exception och utan andra forbjudna kallbackar.
- Sakra att inga profile- eller email-falt exponeras via `GET /entry-state`.

## ACCEPTANCE CRITERIA
- `GET /entry-state` returnerar exakt de tillatna fält som anges i kontraktet.
- `is_invite` forekommer inte i schema eller response.
- `can_enter_app`, `onboarding_completed`, `membership_active` foljer kontraktets derivationsregler.
- Inga forbjudna falt (profil, email, token claims, payment/order/stripe state) exponeras.

## VERIFICATION STEPS
- Inspektera `backend/app/schemas/__init__.py` och verifiera att `EntryStateResponse` matchar kontraktets fältlista.
- Inspektera `backend/app/routes/entry_state.py` och verifiera att response enbart innehaller tillatna falt.
- Bekrafta att `needs_payment` inte anvander invite-undantag och inte bygger pa forbjuden data.
