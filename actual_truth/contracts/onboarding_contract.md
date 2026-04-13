# AVELI ONBOARDING CONTRACT v1

## PURPOSE

Define UX companion guidance for onboarding copy, pre-entry UI sequencing, and
onboarding completion intent.

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

---

## 2. ONBOARDING COMPLETION UX INTENT

UX completion intent is represented when:

* user clicks:
  "Jag förstår hur Aveli fungerar"
* profile display name may be collected as UX projection data

Persisted onboarding completion authority remains outside this UX companion and
is governed by `auth_onboarding_contract.md` and
`onboarding_entry_authority_contract.md`.

Onboarding MUST NOT complete via:

* register
* login
* payment
* invite
* referral
* profile update
* email verification

---

## 3. PAYMENT

Payment:

* creates or updates membership
* MUST NOT grant entry
* MUST NOT modify onboarding_state

---

## 4. INVITE

Invite flow:

* creates membership:
  source = "invite"
  expires_at is required
* MUST NOT grant entry
* MUST NOT complete onboarding

Invite user routing is still determined only by delegated `GET /entry-state`.

---

## 5. REFERRAL

Referral:

* MUST be post-auth only
* MUST use:
  POST /referrals/redeem
* MUST NOT exist in register flow
* MUST NOT create entry

---

## 6. PROFILE

Profile:

* display name is UX projection data
* bio is optional
* image is optional

Profile MUST NOT grant entry.
Profile MUST NOT bootstrap routing.

---

## 7. COURSE SELECTION

Intro course:

* is optional
* is UX only
* MUST NOT affect entry

---

## 8. FRONTEND UX SEQUENCING

Frontend:

* MUST use /entry-state through onboarding_entry_authority_contract.md
* MUST NOT infer authority from:

  * profile
  * token
  * role
  * local state

Routing authority is not defined here. Routing MUST depend only on:

GET /entry-state as defined by onboarding_entry_authority_contract.md

---

## 9. HOME

Home:

* is post-entry

* MUST NOT grant entry
