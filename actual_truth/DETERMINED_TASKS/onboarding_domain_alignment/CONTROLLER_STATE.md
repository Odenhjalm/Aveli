# Onboarding Domain Alignment Controller State

## T11

- Task executed: T11 Rewire Referral Transport And Membership Handoff
- Resulting status: completed
- Repo-visible artifacts:
  - `backend/app/services/membership_grant_service.py`
  - `backend/app/services/referral_service.py`
  - `backend/tests/test_referral_memberships.py`
  - `frontend/lib/api/api_paths.dart`
  - `frontend/lib/api/auth_repository.dart`
  - `frontend/lib/core/auth/auth_controller.dart`
  - `frontend/lib/core/routing/app_router.dart`
  - `frontend/lib/features/onboarding/onboarding_profile_page.dart`
  - `frontend/test/widgets/onboarding_profile_page_test.dart`
  - `frontend/test/unit/auth_controller_test.dart`
- Verification evidence:
  - referral email transport now builds `/create-profile?referral_code=CODE` instead of `/login`
  - referral redemption grants membership with source `referral`
  - `membership_grant_service` supports `coupon` and `referral`; referral grants require `expires_at`
  - frontend create-profile route accepts `referral_code` and `AuthController.createProfile` redeems it after profile creation
  - local verification database was aligned by applying append-only baseline slot `0037_memberships_referral_source_alignment.sql` from repo-visible T05 authority
  - scoped backend verification passed: `backend/tests/test_referral_memberships.py`, `backend/tests/test_onboarding_state.py`, and `backend/tests/test_profiles_owner.py`
  - Flutter runtime unavailable in the current shell, so frontend verification was static
- Controller decision: continue

## T10

- Task executed: T10 Separate Create-Profile From /profiles/me
- Resulting status: completed
- Repo-visible artifacts:
  - `backend/app/auth_onboarding_failures.py`
  - `backend/app/routes/auth.py`
  - `backend/app/schemas/__init__.py`
  - `backend/tests/test_onboarding_state.py`
  - `backend/tests/test_profiles_owner.py`
  - `frontend/lib/api/api_paths.dart`
  - `frontend/lib/api/auth_repository.dart`
  - `frontend/lib/core/auth/auth_controller.dart`
  - `frontend/lib/features/onboarding/onboarding_profile_page.dart`
  - `frontend/test/widgets/onboarding_profile_page_test.dart`
  - `frontend/test/unit/auth_controller_test.dart`
- Verification evidence:
  - `POST /auth/onboarding/create-profile` is mounted as the onboarding-owned create-profile mutation
  - `OnboardingCreateProfileRequest` requires non-blank `display_name` and permits optional `bio` only
  - create-profile rejects media and authority fields including `photo_url`, `avatar_media_id`, `onboarding_state`, `role_v2`, and `is_admin`
  - frontend onboarding profile save calls `AuthController.createProfile` instead of `profileRepositoryProvider.updateMe`
  - `/profiles/me` remains projection-only for onboarding and is not used by the onboarding create-profile flow
  - scoped backend verification passed: `backend/tests/test_onboarding_state.py`, `backend/tests/test_profiles_owner.py`, and `backend/tests/test_auth_change_password.py`
  - Flutter runtime unavailable in the current shell, so frontend verification was static
- Controller decision: continue

## T05

- Task executed: T05 Append-Only Baseline Referral Vocabulary Alignment
- Resulting status: completed
- Repo-visible artifacts:
  - `backend/supabase/baseline_slots/0037_memberships_referral_source_alignment.sql`
  - `backend/supabase/baseline_slots.lock.json`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/DAG_SUMMARY.md`
- Verification evidence:
  - historical slot `0032_memberships_fail_closed_constraints.sql` remains unchanged
  - append-only slot `0037` replaces active membership source vocabulary with `purchase`, `referral`, and `coupon`
  - append-only slot `0037` removes active invite-specific baseline doctrine by dropping `memberships_invite_expires_at_check`
  - append-only slot `0037` adds `memberships_referral_expires_at_check`
  - `backend/supabase/baseline_slots.lock.json` records slot `0037` with matching SHA-256
  - normalized baseline lock verification passes for all locked slots; the stock baseline-freeze script is blocked in this Windows checkout by pre-existing CRLF worktree bytes on protected slots
- Controller decision: continue

## T09

- Task executed: T09 Move Required Name To Create-Profile
- Resulting status: completed
- Repo-visible artifacts:
  - `backend/app/schemas/__init__.py`
  - `backend/app/models.py`
  - `backend/app/routes/auth.py`
  - `backend/tests/utils.py`
  - `backend/tests/test_onboarding_state.py`
  - `backend/tests/test_auth_change_password.py`
  - `frontend/lib/api/auth_repository.dart`
  - `frontend/lib/core/auth/auth_controller.dart`
  - `frontend/lib/core/routing/app_router.dart`
  - `frontend/lib/features/auth/presentation/signup_page.dart`
  - `frontend/lib/mvp/api_client.dart`
  - `frontend/lib/mvp/widgets/mvp_login_page.dart`
  - `frontend/test/widgets/router_bootstrap_test.dart`
- Verification evidence:
  - `AuthRegisterRequest` no longer has `display_name`
  - `POST /auth/register` calls `models.create_user` without `display_name`
  - frontend signup no longer collects or sends display name
  - onboarding-needed routing enters create-profile before welcome
  - onboarding profile UI still blocks empty display name
  - scoped backend verification passed: `backend/tests/test_onboarding_state.py` and `backend/tests/test_auth_change_password.py`
  - Flutter/Dart runtime unavailable in the current shell, so frontend verification was static
- Controller decision: continue

## T08

- Task executed: T08 Remove Profile-Derived Onboarding Completion
- Resulting status: completed
- Repo-visible artifacts:
  - `backend/app/routes/auth.py`
  - `backend/tests/test_onboarding_state.py`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/DAG_SUMMARY.md`
- Verification evidence:
  - `POST /auth/onboarding/complete` no longer checks `current_user.display_name`
  - `profile_name_required` response path was removed
  - onboarding completion still explicitly writes `app.auth_subjects.onboarding_state`
  - scoped backend verification passed: `backend/tests/test_onboarding_state.py`
- Controller decision: continue

## T07

- Task executed: T07 Replace Tests That Canonize require_app_entry
- Resulting status: completed
- Repo-visible artifacts:
  - `backend/tests/test_onboarding_entry_dependency.py`
  - `backend/tests/test_payment_pre_entry_semantics.py`
  - `backend/tests/test_route_inventory_entry_authority.py`
  - `backend/tests/test_protected_lesson_content_surface_gate.py`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/DAG_SUMMARY.md`
- Verification evidence:
  - tests refer to `require_app_entry` as enforcement, not canonical routing authority
  - tests monkeypatch canonical entry-state membership reads instead of `app.auth` membership reads
  - route inventory asserts entry-state enforcement dependency without naming `require_app_entry` as canonical authority
  - scoped backend verification passed: `34 passed`
- Controller decision: continue

## T06

- Task executed: T06 Remove Duplicate Backend App Entry Model
- Resulting status: completed
- Repo-visible artifacts:
  - `backend/app/auth.py`
  - `backend/app/routes/entry_state.py`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
  - `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/DAG_SUMMARY.md`
- Verification evidence:
  - `backend/app/auth.py` no longer defines `evaluate_app_entry`
  - `backend/app/auth.py` no longer defines `is_app_entry_allowed`
  - `require_app_entry` enforces `build_entry_state(current).can_enter_app`
  - `GET /entry-state` and backend guards share the same canonical entry-state computation
  - `compileall` passed for `backend/app/auth.py`, `backend/app/permissions.py`, and `backend/app/routes/entry_state.py`
- Controller decision: continue
