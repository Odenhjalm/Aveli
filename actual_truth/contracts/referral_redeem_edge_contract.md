# REFERRAL REDEEM EDGE CONTRACT

STATUS: ACTIVE

This contract operates under `SYSTEM_LAWS.md`,
`referral_membership_grant_contract.md`,
`commerce_membership_contract.md`, and `auth_onboarding_contract.md`.
This contract contains execution-boundary law only for
`POST /referrals/redeem`.
This contract defines request shape, response shape, transport behavior,
ordering, and execution-surface constraints only.

## EXECUTION SURFACE

- Canonical mounted execution surface: `POST /referrals/redeem`
- No other route may express the same redemption meaning.
- Caller MUST already be authenticated before this surface is invoked.
- `POST /auth/register` remains governed only by
  `auth_onboarding_contract.md` and MUST continue to reject `referral_code`.
- Create-profile and onboarding completion remain owned by
  `auth_onboarding_contract.md` and are not owned by this surface.

## REQUEST BOUNDARY

Request body uses this serialized field order:

- `code`

Field rules:

- The request body MUST be exactly `{ "code": string }`
- `code` MUST be present and MUST be a string
- No additional request body fields may be present
- User identity MUST come from authenticated execution context and MUST NOT be
  supplied in the request body
- `email`, `referral_code`, `free_days`, `free_months`, auth credentials,
  profile fields, order fields, payment fields, and Stripe fields MUST NOT be
  present

## RESPONSE BOUNDARY

Success output uses this serialized field order:

- `status`

Success field rules:

- Success response MUST be exactly `{ "status": "redeemed" }`
- No additional success response fields may be present

Failure output uses this serialized field order:

- `detail`

Failure field rules:

- Failure response MUST use the single-field shape
  `{ "detail": "stable_error_code" }`
- `stable_error_code` denotes a stable string error identifier at the execution
  boundary
- No additional failure response fields may be present

## ORDERING CONSTRAINTS

- Redemption through `POST /referrals/redeem` MUST occur only after identity
  creation is complete
- Successful execution order is:
  1. authenticated identity exists
  2. the referral recipient is operating inside the canonical onboarding flow
  3. the surface receives `{ "code": string }`
  4. referral redemption is validated and applied under
     `referral_membership_grant_contract.md`
  5. resulting membership grant is handed off under
     `commerce_membership_contract.md`
  6. the surface emits `{ "status": "redeemed" }`
- Resulting membership state remains owned only by
  `commerce_membership_contract.md`

## NON-OWNERSHIP EXCLUSIONS

- Referral code creation, invitation semantics, recipient binding, redemption
  eligibility, single-use rules, and grant semantics are owned only by
  `referral_membership_grant_contract.md`
- Auth credential creation, auth token issuance, create-profile ownership, and
  onboarding completion ownership are owned only by
  `auth_onboarding_contract.md`
- Membership state ownership, purchase authority, payment authority, and Stripe
  authority are owned only by `commerce_membership_contract.md`
- This contract does not own referral semantics, auth semantics, membership
  state ownership, purchase authority, payment authority, or domain error
  meaning

## TRANSPORT CONSTRAINTS

- `referral_code` remains transport-only context before redemption under
  `referral_membership_grant_contract.md`
- `referral_code` MUST NOT be accepted on `POST /auth/register`
- This surface MUST NOT emit auth tokens, profile payloads, membership objects,
  order objects, payment objects, or Stripe objects
- Response payloads MUST preserve the listed field names exactly

## FINAL ASSERTION

- `POST /referrals/redeem` is the sole canonical execution surface for mounted
  referral redemption
- Redemption occurs only after identity exists
- Auth remains auth-only
- Referral remains owner of referral semantics
- Commerce remains owner of resulting membership state
