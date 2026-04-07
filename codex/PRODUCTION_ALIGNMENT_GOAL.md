# AVELI PRODUCTION ALIGNMENT GOAL

## MODE: LOCKED

Endast arbete som direkt bidrar till detta mål är tillåtet.

---

## TREE 1 — AUTH + ONBOARDING

- [ ] User can sign up (Supabase auth)
- [ ] User is created in auth.users
- [ ] Profile is created (above-core)
- [ ] auth_subjects row exists and is correct
- [ ] No legacy user creation path exists

---

## TREE 1.2 — STRIPE + MEMBERSHIP

- [ ] User can initiate purchase
- [ ] Stripe checkout works
- [ ] Order is created
- [ ] Membership is created
- [ ] Enrollment is created
- [ ] No legacy purchase path exists

---

## TREE 2 — COURSE + LESSON EDITOR

- [ ] Course can be created
- [ ] Lesson can be created
- [ ] Lesson structure persists correctly
- [ ] Lesson content follows canonical surfaces
- [ ] No raw-table authority paths exist

---

## TREE 3 — MEDIA PIPELINE

- [ ] File upload works
- [ ] Media asset is created
- [ ] Transcode pipeline behaves correctly (or disabled correctly)
- [ ] runtime_media projection is correct
- [ ] Playback works via canonical path only

---

## GLOBAL REQUIREMENTS

- [ ] No legacy authority paths remain
- [ ] All flows work from clean baseline
- [ ] No worker crashes on minimal baseline
- [ ] All workers classified correctly

---

## FINAL GATE

- [ ] Full Playwright E2E passes
- [ ] Full user journey works:
  - signup
  - onboarding
  - create course
  - add lesson
  - upload media
  - purchase course

ONLY WHEN ALL ITEMS ARE TRUE:
→ Aveli is production-ready