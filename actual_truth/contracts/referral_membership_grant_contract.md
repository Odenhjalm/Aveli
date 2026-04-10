# REFERRAL MEMBERSHIP GRANT CONTRACT

## STATUS

ACTIVE

This contract defines the canonical referral truth for teacher-issued referral codes that grant non-purchase membership access.
This contract operates under `SYSTEM_LAWS.md`.
This contract composes with `auth_onboarding_contract.md` for identity creation and with `commerce_membership_contract.md` for resulting membership state.

## 1. CONTRACT LAW

- Referral code creation, identity, and redemption semantics are owned only by this contract.
- `app.referral_codes` is the only canonical referral identity authority.
- Teacher-issued referral invitations are owned only by this contract.
- `referral_code` is transport-only context before redemption.
- `referral_code` remains forbidden on `POST /auth/register`.
- Referral redemption MUST occur only after identity creation is complete.
- Referral grant is a non-purchase membership grant.
- Referral may authorize a membership grant but does not own resulting membership state.
- No endpoint or flow outside this document may be used as referral grant truth.
- No fallback path or legacy redemption path is allowed.

## 2. AUTHORITY MODEL

- `app.referral_codes` owns referral identity and lifecycle:
  - code
  - teacher association
  - recipient email binding
  - configured duration
  - active state
  - `redeemed_by_user_id`
  - `redeemed_at`
- `auth.users` under `auth_onboarding_contract.md` owns identity creation and credential truth.
- `app.auth_subjects` under `auth_onboarding_contract.md` owns onboarding and role truth.
- `app.memberships` under `commerce_membership_contract.md` owns resulting app-entry membership state only.
- `app.orders` and `app.payments` under `commerce_membership_contract.md` own purchase and payment truth only.
- Referral does not own purchase, payment, onboarding, or execution response shapes.

## 3. OWNED RULE FAMILIES

- referral code creation and identity
- teacher-issued referral invitation semantics
- recipient email binding and matching rules
- redemption eligibility
- single-use redemption rules
- referral grant semantics
- referral-to-membership handoff semantics

## 4. REFERRAL CREATION LAW

- Only a teacher-authorized referral flow may create a referral code.
- A referral code MUST bind exactly one recipient email.
- A referral code MUST bind exactly one grant duration definition.
- Exactly one of `free_days` or `free_months` may be present.
- A referral code MUST begin as active and unredeemed.
- Code generation collisions must be resolved inside the creation flow and must not create duplicate referral identity.

## 5. RECIPIENT BINDING AND ELIGIBILITY LAW

- Recipient email comparison MUST use normalized email matching.
- A referral is redeemable only when:
  - the code exists
  - `active` is `true`
  - `redeemed_by_user_id` is `null`
  - `redeemed_at` is `null`
  - the redeeming user email matches the bound recipient email
- If any eligibility rule fails, redemption MUST be rejected explicitly.
- Redemption MUST NOT be inferred from link presence alone.

## 6. TRANSPORT AND REDEMPTION BOUNDARY

- Referral links may transport `referral_code` only as pre-redemption context.
- Transport of `referral_code` does not create identity, authenticate a user, or grant membership by itself.
- `POST /auth/register` remains governed only by `auth_onboarding_contract.md` and MUST continue to reject `referral_code`.
- Referral redemption occurs only after identity creation is complete and a concrete user identity exists.
- `invite_token` remains owned only by `auth_onboarding_contract.md` and is unrelated to referral ownership.

## 7. REFERRAL GRANT SEMANTICS

- A valid referral redemption yields a non-purchase membership grant only.
- Referral grant duration is derived from the bound `free_days` or `free_months`.
- Referral grant MUST NOT create an order.
- Referral grant MUST NOT create a payment or Stripe authority record.
- Referral grant MUST be single-use.
- Successful redemption MUST bind `redeemed_by_user_id` and `redeemed_at` to the referral identity.

## 8. MEMBERSHIP HANDOFF LAW

- Referral owns the decision that a valid redemption earns a grant.
- `commerce_membership_contract.md` remains the only owner of resulting membership state in `app.memberships`.
- Referral-to-membership handoff MUST write a non-purchase membership state under the commerce membership source law.
- The resulting membership state MUST use the non-purchase source bucket `invite`.
- The resulting membership state MUST include explicit source metadata identifying the grant as referral-derived.
- Referral handoff MUST NOT reinterpret membership purchase law or Stripe webhook law.

## 9. EXCLUDED RULE FAMILIES

- auth credential creation
- auth token issuance
- auth onboarding field semantics
- `invite_token` ownership
- purchase authority
- payment / Stripe authority
- execution response shape
- profile projection authority

## 10. CANONICAL FLOW

1. A teacher-authorized referral creation flow creates a referral code under `app.referral_codes`.
2. The referral flow binds the code to one recipient email and one duration definition.
3. The referral flow delivers a signup link containing `referral_code` as transport-only context.
4. The recipient completes identity creation through the canonical Auth + Onboarding flow without `referral_code` in `POST /auth/register`.
5. After identity creation, a referral redemption flow validates the transported code against referral identity and recipient email.
6. If the referral is valid, referral marks the code redeemed and initiates a non-purchase membership grant handoff.
7. `commerce_membership_contract.md` governs the resulting `app.memberships` state as the canonical app-entry record.

## 11. FORBIDDEN PATTERNS

- Accepting `referral_code` on `POST /auth/register`.
- Redeeming a referral before identity creation exists.
- Treating link presence alone as redemption.
- Allowing one referral code to redeem more than once.
- Using referral redemption to create purchase or payment authority.
- Letting referral flows mutate onboarding or role authority.
- Letting commerce own referral code issuance or recipient binding semantics.
- Letting auth `invite_token` absorb referral meaning.
- Any fallback redemption path outside this contract.

## 12. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

- Mounted auth runtime keeps `referral_code` forbidden on `POST /auth/register`.
- Referral redemption and resulting non-purchase membership grant now route through dedicated referral and membership-grant surfaces instead of auth registration.
- Any future reintroduction of auth-side referral redemption, auth-side membership grant, or register-time `referral_code` acceptance is implementation drift only and does not redefine this contract.

## 13. FINAL ASSERTION

- This contract is the sole canonical owner of referral-driven membership grant behavior.
- `referral_code` remains transport-only before redemption and remains forbidden on `POST /auth/register`.
- Auth remains auth-only.
- Commerce membership remains owner of resulting membership state.
- Contract truth and implementation drift are intentionally separated.
