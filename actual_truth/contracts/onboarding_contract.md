# AVELI ONBOARDING CONTRACT v1

## PURPOSE

Define the canonical onboarding and entry behavior.

This contract is the single source of truth.
Implementation must follow this exactly.

---

## 1. ENTRY LAW

User may enter app ONLY when:

* onboarding_state = completed
* membership is valid

No other condition grants entry.

---

## 2. ONBOARDING COMPLETION

Onboarding is completed ONLY when:

* user clicks:
  "Jag förstår hur Aveli fungerar"
* profile.name is present

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

Invite user MUST complete onboarding before entry.

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

* name is required for onboarding completion
* bio is optional
* image is optional

Profile MUST NOT grant entry.

---

## 7. COURSE SELECTION

Intro course:

* is optional
* is UX only
* MUST NOT affect entry

---

## 8. FRONTEND AUTHORITY

Frontend:

* MUST use /entry-state
* MUST NOT infer authority from:

  * profile
  * token
  * role
  * local state

Routing MUST depend only on:

entryState

---

## 9. HOME

Home:

* is post-entry

* MUST NOT grant entry
