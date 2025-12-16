# Phase C: Aveli Pro Platform Migration

## Objective
Deliver the marketplace-ready “Aveli Pro Platform” with Stripe Connect, teacher dashboards, product/price sync, stable entitlements, and course lifecycle tooling across Supabase, FastAPI, and Flutter.

## Scope
- Database: teacher accounts, product/price mappings for courses/lessons, entitlements, enrollments view, RLS for teachers/students/admins.
- Backend: Stripe Connect flows, product sync endpoints, teacher course/sales/students/revenue APIs, entitlements service, checkout metadata + webhook handling.
- Frontend (Flutter): teacher Connect UI, dashboards (courses, students, sales, revenue), entitlement watcher/polling, corrected course CTA logic and routing, teacher-mode surfacing.
- DevOps: env templates for Connect + frontend base URL; test scenarios for purchases, entitlements, and teacher revenue flows.

## High-Level Plan
1) **Data layer** ✔️ Supabase migration (uuid-aligned) for `teacher_accounts`, `course_products`, `lesson_packages`, `entitlements`, `course_enrollments_view`; RLS policies (self/owner/admin + student entitlements).  
2) **Backend services** ✔️ `teacher_connect`, `products_sync`, `courses_admin` routes; `entitlements_service`; checkout metadata includes course/teacher/product_type; webhook grants entitlements.  
3) **Frontend teacher suite** ✔️ Pages for Connect, dashboard, course sales, student list, revenue; GoRouter wiring; teacher-mode guards; entitlement watcher with success-page refresh + web polling; course CTA fixes.  
4) **Stripe sync automation** ▶️ Auto-create product/price on course creation/update (best-effort if Stripe configured); lesson package auto-sync still pending until lesson pricing is defined.  
5) **Verification** ✔️ Env template updated; test scenarios documented (buy course/lesson, connect teacher, unlock access, revenue dashboards).

## Immediate Next Steps
- Supabase migration `021_aveli_pro_platform` applied to test project (`evgwgepnscopsiznqkqc`); tables/view/RLS confirmed for `teacher_accounts`, `course_products`, `lesson_packages`, `entitlements`, `course_enrollments_view`.
- Prep envs for manual testing after key rotation (see checklist below).
- Run end-to-end smoke once envs are finalized (checkout → entitlement, Connect onboarding, revenue surfaces).

## Webhook & pricing checklist (team)
- [x] Stripe webhook points to `/webhooks/lessons/stripe` with `STRIPE_WEBHOOK_SECRET` set in envs.
- [ ] Lesson create/update clients send `price_amount_cents` and `price_currency`; other ingestion paths mirror this so auto-sync keeps Stripe in sync.

## Pre-flight for manual testing
- [x] Confirm Stripe keys set: `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`.
- [ ] Set Stripe Connect vars: `STRIPE_CONNECT_CLIENT_ID`, `STRIPE_CONNECT_RETURN_URL`, `STRIPE_CONNECT_REFRESH_URL`.
- [ ] Set frontend/redirects: `FRONTEND_BASE_URL`, `CHECKOUT_SUCCESS_URL`, `CHECKOUT_CANCEL_URL` (choose deep links vs localhost consistently).
- [ ] Verify Supabase creds in use: `SUPABASE_URL`, `SUPABASE_SECRET_API_KEY`, `SUPABASE_PAT`.
- [ ] Toggle `SUBSCRIPTIONS_ENABLED` as desired for the run and ensure `STRIPE_CHECKOUT_UI_MODE` matches flow (hosted vs custom).

## Test Scenarios (to execute)
- **Buy course**: start checkout (web/mobile), confirm Stripe payment, ensure `/checkout/success` refreshes entitlements, course unlocks, CTA switches to “Starta kurs”.
- **Buy lesson package**: start checkout for lesson package, webhook grants entitlement, lesson content unlocks.
- **Teacher connect**: start Stripe Connect onboarding, return/refresh, verify status shows charges/payouts enabled, dashboard updates.
- **Access unlock**: after purchase, entitlements reflected in `/api/me/entitlements` and course_enrollments_view; PaywallGate allows access.
- **Revenue dashboard**: teacher courses list revenue/orders; aggregated revenue matches paid orders; student list shows name/email/source.
