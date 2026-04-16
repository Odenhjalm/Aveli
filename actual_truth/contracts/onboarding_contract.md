# AVELI ONBOARDING CONTRACT v1

## PURPOSE

Define UX companion guidance for onboarding copy, pre-entry UI sequencing,
create-profile intent, and onboarding completion intent.

This contract is not an entry-authority contract. Entry authority, post-auth
routing authority, and `/entry-state` ownership are defined only by
`onboarding_entry_authority_contract.md`.
Implementation may use this file only as UX companion guidance.

---

## 1. UX ENTRY REFERENCE

UX sequencing may point the user toward app entry only after delegated
`GET /entry-state` under `onboarding_entry_authority_contract.md` permits it.
This file does not define the entry decision.

This file must not define entry composition, routing authority, or alternate
current-user entry surfaces.

Canonical pre-entry flow order:

* ordinary self-signup:
  register -> checkout -> create-profile -> welcome -> onboarding-complete -> app
* referral:
  register -> create-profile -> redeem -> welcome -> onboarding-complete -> app

For ordinary self-signup, checkout-first routing means checkout/payment
precedes create-profile when both payment and onboarding are needed. For
referral, transported `referral_code` context is the explicit exception and
routes to create-profile before referral redemption. In both flows, welcome is
an onboarding-owned step and `app` means app-entry only after `GET /entry-state`
permits entry under
`onboarding_entry_authority_contract.md`.

---

## 2. CREATE-PROFILE UX INTENT

Create-profile is an onboarding step.

At create-profile:

* user must provide name
* user may optionally add bio
* user may optionally add image through a media-mediated flow

Create-profile is not profile-projection authority.
Create-profile moves the onboarding-owned subject state to the welcome step
but does not complete onboarding.
Persisted onboarding completion authority remains outside this UX companion and
is governed by `auth_onboarding_contract.md` and
`onboarding_entry_authority_contract.md`.

---

## 3. ONBOARDING COMPLETION UX INTENT

UX completion intent is represented when:

* user clicks:
  "Jag förstår hur Aveli fungerar"

Persisted onboarding completion authority remains outside this UX companion and
is governed by `auth_onboarding_contract.md` and
`onboarding_entry_authority_contract.md`.

Onboarding completion MUST occur only after the explicit welcome confirmation.

Onboarding MUST NOT complete via:

* register
* login
* payment
* referral
* create-profile alone
* profile update
* email verification

---

## 4. PAYMENT

Payment:

* creates or updates membership
* MUST NOT grant entry
* MUST NOT modify onboarding_state
* is required before create-profile in ordinary self-signup when payment and
  onboarding are both needed
* uses embedded Stripe Checkout as the canonical ordinary self-signup
  membership checkout implementation path
* provides a 14-day trial/test period for ordinary self-signup membership
  checkout
* requires card details during the trial/test period
* supersedes hosted or raw Stripe URL membership checkout for ordinary
  self-signup membership checkout
* does not change course or bundle checkout transport authority

---

## 5. REFERRAL

Referral:

* occurs via email link
* MUST bring the user into onboarding at the create-profile step
* MUST be post-auth only for redemption
* MUST use:
  POST /referrals/redeem
* MUST create a non-purchase membership grant only through canonical commerce
  membership authority using source = "referral"
* MUST NOT exist in register flow
* MUST NOT create entry
* MUST NOT complete onboarding
* is the explicit exception to ordinary self-signup checkout-first routing and
  MUST route to create-profile before redemption
* MUST still continue through welcome confirmation before app entry

---

## 6. PROFILE

Profile projection:

* reflects persisted display name
* reflects optional bio
* may reflect optional image through the media boundary

`/profiles/me` remains projection-only.
Profile MUST NOT grant entry.
Profile MUST NOT bootstrap routing.
Profile MUST NOT own create-profile.

---

## 7. COURSE SELECTION

Intro course:

* is optional
* is UX only
* MUST NOT affect entry

---

## 8. FRONTEND UX SEQUENCING

Frontend:

* MUST use `/entry-state` through `onboarding_entry_authority_contract.md`
* MUST route ordinary self-signup through checkout before create-profile
* MUST route `onboarding_state = "incomplete"` to create-profile when payment
  is no longer needed
* MUST route `onboarding_state = "welcome_pending"` to welcome
* MUST trigger onboarding completion only from the welcome confirmation
* MUST land referral recipients at create-profile
* MUST NOT infer authority from:

  * profile
  * token
  * role
  * local state

Routing authority is not defined here. Routing MUST depend only on:

`GET /entry-state` as defined by `onboarding_entry_authority_contract.md`

---

## 9. HOME

Home:

* is post-entry
* MUST NOT grant entry
