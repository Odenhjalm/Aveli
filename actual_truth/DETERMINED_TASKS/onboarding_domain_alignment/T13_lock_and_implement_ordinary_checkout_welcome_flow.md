# T13 Lock And Implement Ordinary Checkout Welcome Flow

TYPE: OWNER

DEPENDS_ON:

- T04
- T06
- T08
- T09
- T10
- T11

## Purpose

This task owns the revised ordinary self-signup flow introduced after the
original onboarding domain-alignment DAG was materialized.

## Superseded Target

The previous ordinary self-signup target:

`register -> subscribe -> create-profile -> app`

is superseded and MUST NOT remain canonical.

## New Locked Ordinary Target

`register -> checkout -> create-profile -> welcome -> onboarding-complete -> app`

Rules:

- registration creates identity, application subject, and session only
- checkout is required before create-profile in the ordinary path
- checkout creates purchase-backed membership semantics with 30-day free trial
  and card details required
- checkout remains purchase/payment authority only
- create-profile remains onboarding-owned and requires name
- optional image and bio remain create-profile inputs, with image
  media-mediated
- `/profiles/me` remains projection-only
- successful create-profile moves onboarding state to `welcome_pending`
- welcome is onboarding-owned
- onboarding completes only after explicit welcome confirmation:
  `Jag förstår hur Aveli fungerar`

## Referral Compatibility

Referral remains coherent as the explicit checkout-first exception:

`register -> create-profile -> redeem -> welcome -> onboarding-complete -> app`

Referral does not create purchase/payment truth, does not complete onboarding,
and does not bypass app-entry authority.

## Mutation Scope

- `actual_truth/contracts`
- `backend/supabase/baseline_slots`
- backend auth/onboarding runtime
- backend membership checkout runtime
- frontend post-auth routing
- frontend onboarding/welcome flow
- focused tests

## Verification Requirement

- contracts no longer preserve the old ordinary canonical flow
- baseline allows `welcome_pending`
- backend create-profile writes `welcome_pending`
- backend completion requires `welcome_pending` or already `completed`
- membership checkout configures 30-day trial and card collection
- frontend routes ordinary signup to checkout before create-profile
- frontend routes `welcome_pending` to welcome
- welcome confirmation is the only onboarding-complete trigger
- referral flow reaches welcome before app entry

## Stop Conditions

- any authority moves into `/profiles/me`
- checkout mutates onboarding state
- create-profile completes onboarding
- welcome completion is bypassed
- referral compatibility requires reopening T01, T02, or T03

