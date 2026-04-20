# TXT-001 Text Surface Inventory

TYPE: OWNER
DEPENDS_ON: []
MODE: execute
STATUS: COMPLETE_FOR_TXT_001

## Inspection Scope

Static inspection covered these in-scope roots:

- `actual_truth/contracts/`
- `frontend/lib/`
- `frontend/landing/`
- `backend/app/`
- `backend/supabase/baseline_v2_slots/`

The active index manifest was present at `.repo_index/index_manifest.json`.
No index rebuild, backend startup, MCP call, database query, API call, or UI
runtime inspection was performed for TXT-001.

Candidate text-producing files found by static retrieval:

- Frontend Flutter/Dart UI candidates: 118 files.
- Landing/static web candidates: 15 files.
- Backend response/error/email/Stripe candidates: 111 files.
- Baseline DB text-field candidates: 10 SQL files.

Inventory rows classify surface ownership and current text-producing
locations. Where one file contains multiple text classes, the row describes
the product-facing class that must own that text after cutover.

## Authority Classes

Allowed classes are exactly:

- `contract_text`
- `backend_error_text`
- `backend_status_text`
- `backend_email_text`
- `backend_stripe_text`
- `db_domain_content`
- `db_user_content`
- `non_user_facing_identifier`

Frontend is not an authority class.

## Surface Inventory

| ID | File path | Surface name | Example or text ID | Current origin | Required authority class | Canonical owner | Current state | Violation type |
|---|---|---|---|---|---|---|---|---|
| TXT-SURF-001 | `actual_truth/contracts/auth_onboarding_contract.md` | Onboarding welcome confirmation | `Jag förstår hur Aveli fungerar` | Contract exact copy plus frontend duplicate | `contract_text` | Auth + Onboarding contract, delivered by backend catalog | Partial | `authority_violation` until frontend duplicate is removed |
| TXT-SURF-002 | `actual_truth/contracts/auth_onboarding_failure_contract.md` | Auth/onboarding failure messages | error-code message mappings | Contract policy | `backend_error_text` | Backend failure catalog | Aligned as authority model | None |
| TXT-SURF-003 | `actual_truth/contracts/aveli_embedded_checkout_spec.md` | Ordinary membership checkout copy | headline, trial/card line, CTA, waiting/cancel/retry | Contract exact copy | `backend_stripe_text` | Commerce/checkout backend catalog | Aligned as authority model | None |
| TXT-SURF-004 | `frontend/lib/features/community/presentation/profile_page.dart` | Profile UI chrome and password section | `Din profil`, `Byt lösenord`, profile save/status text | Hardcoded frontend plus DB profile fields | `contract_text`, `backend_status_text`, `backend_error_text`, `db_user_content` | Backend text catalog and profile projection | Violating | `authority_violation`, `encoding_error`, `frontend_leak` |
| TXT-SURF-005 | `backend/app/routes/profiles.py` | Profile API failures | `profile_not_found` detail payloads | Backend route exception detail | `backend_error_text` | Backend failure catalog | Violating | `contract_violation` |
| TXT-SURF-006 | `backend/supabase/baseline_v2_slots/V2_0012_core_substrate_profiles_storage_referrals.sql` | Profile display name and bio | `app.profiles.display_name`, `app.profiles.bio` | DB profile projection fields | `db_user_content` | Profile projection contract and backend read composition | Aligned as field ownership | None |
| TXT-SURF-007 | `frontend/lib/features/auth/presentation/login_page.dart` | Login UI | login title, buttons, errors | Hardcoded frontend | `contract_text`, `backend_error_text` | Auth backend text catalog | Violating | `authority_violation` |
| TXT-SURF-008 | `frontend/lib/features/auth/presentation/signup_page.dart` | Signup UI | signup labels, CTAs, errors | Hardcoded frontend | `contract_text`, `backend_error_text` | Auth backend text catalog | Violating | `authority_violation` |
| TXT-SURF-009 | `frontend/lib/features/auth/presentation/forgot_password_page.dart` | Forgot-password UI | forgot password copy and submit states | Hardcoded frontend | `contract_text`, `backend_status_text`, `backend_error_text` | Auth backend text catalog | Violating | `authority_violation` |
| TXT-SURF-010 | `frontend/lib/features/auth/presentation/new_password_page.dart` | Reset-password UI | reset password copy and submit states | Hardcoded frontend | `contract_text`, `backend_status_text`, `backend_error_text` | Auth backend text catalog | Violating | `authority_violation` |
| TXT-SURF-011 | `frontend/lib/features/auth/presentation/verify_email_page.dart` | Verify-email UI | verification-link copy and resend states | Hardcoded frontend | `contract_text`, `backend_status_text`, `backend_error_text` | Auth backend text catalog | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-012 | `frontend/lib/features/auth/presentation/settings_page.dart` | Auth settings UI | settings labels and backend endpoint copy | Hardcoded frontend | `contract_text`, `backend_status_text` | Backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-013 | `backend/app/auth_onboarding_failures.py` | Auth/onboarding canonical failures | Swedish failure messages | Backend hardcoded failure map | `backend_error_text` | Backend failure catalog | Violating | `contract_violation` due ASCII-degraded Swedish |
| TXT-SURF-014 | `backend/app/routes/auth.py` | Auth route failures | reset/verify/register/login route errors | Backend route exception text/detail | `backend_error_text` | Backend failure catalog | Violating | `contract_violation` |
| TXT-SURF-015 | `backend/app/services/supabase_auth.py` | Supabase auth failure translation | provider auth errors | Backend service exception text | `backend_error_text` | Backend failure catalog | Violating | `contract_violation` |
| TXT-SURF-016 | `backend/app/email_templates/verify_email.html` | Verify-email template | email heading/body/CTA | Backend template | `backend_email_text` | Backend email catalog | Partial | `authority_violation` until catalog-owned |
| TXT-SURF-017 | `backend/app/email_templates/reset_password.html` | Reset-password template | email heading/body/CTA | Backend template | `backend_email_text` | Backend email catalog | Partial | `authority_violation` until catalog-owned |
| TXT-SURF-018 | `backend/app/services/email_verification.py` | Email subject/plain text | reset and verification subject/body | Backend hardcoded email text | `backend_email_text` | Backend email catalog | Partial | `authority_violation` until catalog-owned |
| TXT-SURF-019 | `backend/app/services/referral_service.py` | Referral email transport | referral link body text | Backend hardcoded email text | `backend_email_text` | Referral/email backend catalog | Violating | `encoding_error`, `frontend_leak` |
| TXT-SURF-020 | `frontend/lib/features/onboarding/onboarding_profile_page.dart` | Create-profile onboarding UI | profile form labels, CTAs, errors | Hardcoded frontend plus DB profile inputs | `contract_text`, `backend_status_text`, `backend_error_text`, `db_user_content` | Onboarding backend catalog and profile projection | Violating | `authority_violation` |
| TXT-SURF-021 | `frontend/lib/features/onboarding/welcome_page.dart` | Welcome UI | welcome confirmation CTA | Hardcoded frontend duplicate of contract text | `contract_text` | Auth + Onboarding backend catalog | Violating | `authority_violation` |
| TXT-SURF-022 | `backend/app/routes/entry_state.py` | Entry-state status/routing text | entry state fields | Backend response identifiers | `non_user_facing_identifier` | Entry authority contract | Aligned if not rendered as copy | None |
| TXT-SURF-023 | `frontend/lib/features/payments/presentation/subscribe_screen.dart` | Membership checkout UI | membership headline, trial/payment states, errors | Hardcoded frontend | `backend_stripe_text`, `backend_status_text`, `backend_error_text` | Commerce/checkout backend catalog | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-024 | `frontend/lib/features/payments/presentation/embedded_membership_checkout_surface_web.dart` | Embedded membership checkout web surface | embedded checkout labels and callbacks | Hardcoded/frontend state text and provider IDs | `backend_stripe_text`, `non_user_facing_identifier` | Commerce/checkout backend catalog | Violating | `authority_violation` |
| TXT-SURF-025 | `frontend/lib/features/payments/presentation/embedded_membership_checkout_surface_webview.dart` | Embedded membership checkout webview | unsupported/loading states | Hardcoded frontend | `backend_stripe_text`, `backend_status_text` | Commerce/checkout backend catalog | Violating | `authority_violation` |
| TXT-SURF-026 | `frontend/lib/features/payments/presentation/embedded_membership_checkout_surface_stub.dart` | Embedded checkout unsupported state | unsupported text | Hardcoded frontend | `backend_status_text` | Commerce/checkout backend catalog | Violating | `authority_violation` |
| TXT-SURF-027 | `frontend/lib/features/payments/presentation/booking_page.dart` | Booking/payment placeholder UI | REST/backend endpoint copy | Hardcoded frontend | `contract_text`, `backend_status_text` | Backend text catalog | Violating | `frontend_leak` |
| TXT-SURF-028 | `frontend/lib/features/payments/presentation/paywall_prompt.dart` | Paywall prompt | paywall copy and CTAs | Hardcoded frontend | `contract_text`, `backend_status_text` | Backend text catalog | Violating | `authority_violation` |
| TXT-SURF-029 | `frontend/lib/features/paywall/presentation/checkout_result_page.dart` | Checkout result UI | session/order state, success/cancel/failure | Hardcoded frontend plus provider identifiers | `backend_stripe_text`, `non_user_facing_identifier` | Commerce/checkout backend catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-030 | `frontend/lib/features/paywall/presentation/checkout_webview_page.dart` | Hosted checkout webview | loading/error/return state text | Hardcoded frontend | `backend_stripe_text`, `backend_status_text` | Commerce/checkout backend catalog | Violating | `authority_violation` |
| TXT-SURF-031 | `frontend/landing/pages/checkout/return.tsx` | Checkout return page | `Checkout return`, `session_id`, backend/webhook text | Hardcoded landing frontend | `backend_stripe_text`, `non_user_facing_identifier` | Commerce/checkout backend catalog | Violating | `frontend_leak`, `authority_violation` |
| TXT-SURF-032 | `frontend/landing/pages/checkout/cancel.tsx` | Checkout cancel page | cancel copy, Stripe checkout badge | Hardcoded landing frontend | `backend_stripe_text` | Commerce/checkout backend catalog | Violating | `authority_violation` |
| TXT-SURF-033 | `backend/app/routes/billing.py` | Membership billing route failures | checkout and subscription errors | Backend route/service text | `backend_stripe_text`, `backend_error_text` | Commerce/checkout backend catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-034 | `backend/app/services/subscription_service.py` | Stripe membership service text | Stripe/customer/payment errors | Backend hardcoded service text | `backend_stripe_text`, `backend_error_text` | Commerce/checkout backend catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-035 | `backend/app/routes/api_checkout.py` | Course checkout route text | checkout errors | Backend route/service text | `backend_stripe_text`, `backend_error_text` | Commerce/checkout backend catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-036 | `backend/app/services/checkout_service.py` | Course checkout service text | checkout session errors | Backend hardcoded service text | `backend_stripe_text`, `backend_error_text` | Commerce/checkout backend catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-037 | `frontend/landing/pages/index.tsx` | Landing home page | product cards, footer links, technical implementation copy | Hardcoded landing frontend | `contract_text`, `db_domain_content` | Landing/backend text catalog and typed landing API | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-038 | `frontend/landing/pages/privacy.tsx` | Landing privacy page | privacy policy copy | Hardcoded landing frontend | `contract_text` | Legal/landing backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-039 | `frontend/landing/pages/terms.tsx` | Landing terms page | terms copy | Hardcoded landing frontend | `contract_text` | Legal/landing backend text catalog | Violating | `authority_violation` |
| TXT-SURF-040 | `frontend/landing/pages/gdpr.tsx` | Landing GDPR page | GDPR copy and processor text | Hardcoded landing frontend | `contract_text` | Legal/landing backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-041 | `frontend/landing/landing/index.html` | Static landing fallback | hero, app-store links, legal links | Hardcoded static HTML | `contract_text` | Landing/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-042 | `frontend/landing/landing/privacy.html` | Static privacy fallback | privacy copy and legal links | Hardcoded static HTML | `contract_text` | Legal/landing backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-043 | `frontend/landing/landing/terms.html` | Static terms fallback | terms copy and legal links | Hardcoded static HTML | `contract_text` | Legal/landing backend text catalog | Violating | `authority_violation` |
| TXT-SURF-044 | `frontend/landing/landing/gdpr.html` | Static GDPR fallback | GDPR copy and legal links | Hardcoded static HTML | `contract_text` | Legal/landing backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-045 | `frontend/lib/features/landing/presentation/landing_page.dart` | Flutter landing page | hero, course/teacher/service sections, CTAs | Hardcoded frontend plus API content | `contract_text`, `db_domain_content`, `db_user_content` | Landing/backend text catalog and typed landing API | Violating | `authority_violation` |
| TXT-SURF-046 | `frontend/lib/features/landing/presentation/legal/privacy_page.dart` | Flutter privacy page | privacy title/body | Hardcoded frontend | `contract_text` | Legal/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-047 | `frontend/lib/features/landing/presentation/legal/terms_page.dart` | Flutter terms page | terms title/body | Hardcoded frontend | `contract_text` | Legal/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-048 | `frontend/lib/widgets/base_page.dart` | Shared legal footer | Terms, Privacy, Data Deletion links | Hardcoded frontend English | `contract_text` | Legal/backend text catalog | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-049 | `frontend/lib/features/home/presentation/home_dashboard_page.dart` | Home dashboard | feed/services empty states, errors, certification text | Hardcoded frontend plus DB/API content | `contract_text`, `backend_error_text`, `backend_status_text`, `db_domain_content` | Home/backend text catalog and typed APIs | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-050 | `frontend/lib/features/community/presentation/home_page.dart` | Community home | dashboard copy, errors, DB service/profile content | Hardcoded frontend plus DB/API content | `contract_text`, `backend_error_text`, `db_domain_content`, `db_user_content` | Community/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-051 | `frontend/lib/features/community/presentation/community_page.dart` | Community page | navigation/chrome and content cards | Hardcoded frontend plus DB/API content | `contract_text`, `db_domain_content`, `db_user_content` | Community/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-052 | `frontend/lib/features/community/presentation/profile_view_page.dart` | Public profile view | profile labels and profile content | Hardcoded frontend plus DB profile content | `contract_text`, `db_user_content` | Community/profile backend catalog | Violating | `authority_violation` |
| TXT-SURF-053 | `frontend/lib/features/community/presentation/teacher_profile_page.dart` | Teacher profile | teacher labels, service/meditation content | Hardcoded frontend plus DB/API content | `contract_text`, `db_user_content`, `db_domain_content` | Community/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-054 | `frontend/lib/features/community/presentation/service_detail_page.dart` | Service detail | service labels and booking text | Hardcoded frontend plus DB content | `contract_text`, `db_domain_content` | Community/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-055 | `frontend/lib/features/community/presentation/tarot_page.dart` | Tarot surface | labels, empty/error states | Hardcoded frontend | `contract_text`, `backend_status_text`, `backend_error_text` | Backend text catalog | Violating | `authority_violation` |
| TXT-SURF-056 | `frontend/lib/features/community/presentation/widgets/profile_logout_section.dart` | Profile logout UI | logout copy/CTA | Hardcoded frontend | `contract_text`, `backend_status_text` | Profile/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-057 | `frontend/lib/features/community/application/certification_gate.dart` | Certification gate text | certification unavailable/login messages | Frontend hardcoded gate messages | `backend_status_text` | Backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-058 | `frontend/lib/features/courses/presentation/course_catalog_page.dart` | Course catalog | catalog headings, empty/error states, course cards | Hardcoded frontend plus DB course content | `contract_text`, `backend_error_text`, `db_domain_content` | Courses/backend text catalog and course API | Violating | `authority_violation` |
| TXT-SURF-059 | `frontend/lib/features/courses/presentation/course_intro_page.dart` | Course intro | intro page copy and course content | Hardcoded frontend plus DB course content | `contract_text`, `db_domain_content` | Courses/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-060 | `frontend/lib/features/courses/presentation/course_intro_redirect_page.dart` | Intro redirect state | redirect/loading/error text | Hardcoded frontend | `backend_status_text`, `backend_error_text` | Courses/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-061 | `frontend/lib/features/courses/presentation/course_page.dart` | Course detail | course chrome, lessons, pricing/access copy | Hardcoded frontend plus DB course/lesson fields | `contract_text`, `backend_status_text`, `db_domain_content` | Courses/backend text catalog and course API | Violating | `authority_violation` |
| TXT-SURF-062 | `frontend/lib/features/courses/presentation/course_access_gate.dart` | Course access gate | locked/unauthorized states | Hardcoded frontend | `backend_status_text`, `backend_error_text` | Course access backend catalog | Violating | `authority_violation` |
| TXT-SURF-063 | `frontend/lib/features/courses/presentation/lesson_page.dart` | Lesson content view | lesson labels, errors, media states | Hardcoded frontend plus DB lesson content | `contract_text`, `backend_error_text`, `backend_status_text`, `db_domain_content` | Lesson/backend text catalog and lesson API | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-064 | `backend/supabase/baseline_v2_slots/V2_0004_courses_and_public_content.sql` | Course display DB fields | `app.courses.title`, `app.course_public_content.short_description` | DB domain fields | `db_domain_content` | Course public/content contracts and backend read composition | Aligned as field ownership | None |
| TXT-SURF-065 | `backend/supabase/baseline_v2_slots/V2_0005_lessons_content_and_access.sql` | Lesson display/content DB fields | `app.lessons.lesson_title`, `app.lesson_contents.content_markdown` | DB domain fields | `db_domain_content` | Course/lesson contracts and backend read composition | Aligned as field ownership | None |
| TXT-SURF-066 | `frontend/lib/features/studio/presentation/studio_page.dart` | Studio entry | Studio title, role/entry errors | Hardcoded frontend | `contract_text`, `backend_status_text`, `backend_error_text` | Studio/backend text catalog | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-067 | `frontend/lib/features/studio/presentation/teacher_home_page.dart` | Teacher home/studio dashboard | course CRUD, invitation, home player labels | Hardcoded frontend plus DB course/home-player content | `contract_text`, `backend_status_text`, `backend_error_text`, `db_domain_content` | Studio/backend text catalog and DB content APIs | Violating | `authority_violation` |
| TXT-SURF-068 | `frontend/lib/features/studio/presentation/course_editor_page.dart` | Course editor | editor labels, validation, preview, save/upload messages | Hardcoded frontend plus DB lesson content | `contract_text`, `backend_status_text`, `backend_error_text`, `db_domain_content` | Studio/editor backend text catalog and lesson API | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-069 | `frontend/lib/features/studio/presentation/editor_media_controls.dart` | Editor media controls | media action labels/status | Hardcoded frontend | `contract_text`, `backend_status_text`, `backend_error_text` | Studio/media backend catalog | Violating | `authority_violation` |
| TXT-SURF-070 | `frontend/lib/features/studio/presentation/lesson_media_preview.dart` | Studio lesson media preview | media loading/detail/status text | Hardcoded frontend plus backend media details | `contract_text`, `backend_status_text`, `backend_error_text` | Media/backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-071 | `frontend/lib/features/studio/presentation/profile_media_page.dart` | Home-player/media library management | upload/link/delete dialogs and snackbars | Hardcoded frontend plus DB media titles | `contract_text`, `backend_status_text`, `backend_error_text`, `db_domain_content` | Studio/media backend text catalog | Violating | `authority_violation` |
| TXT-SURF-072 | `frontend/lib/features/studio/widgets/cover_upload_card.dart` | Cover upload card | upload status, choose/change image copy | Hardcoded frontend | `backend_status_text`, `backend_error_text`, `contract_text` | Studio/media backend catalog | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-073 | `frontend/lib/features/studio/widgets/wav_upload_card.dart` | Audio upload card | upload status/action labels | Hardcoded frontend | `backend_status_text`, `backend_error_text`, `contract_text` | Studio/media backend catalog | Violating | `authority_violation` |
| TXT-SURF-074 | `frontend/lib/features/studio/widgets/wav_replace_dialog.dart` | Replace audio dialog | dialog title/buttons/body | Hardcoded frontend | `contract_text`, `backend_status_text` | Studio/media backend catalog | Violating | `authority_violation` |
| TXT-SURF-075 | `frontend/lib/features/studio/widgets/home_player_upload_dialog.dart` | Home-player upload dialog | MP4/backend support messages | Hardcoded frontend | `backend_status_text`, `backend_error_text` | Home-player backend catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-076 | `frontend/lib/features/studio/widgets/studio_calendar.dart` | Studio sessions calendar | session labels, drag/drop notice, dialogs | Hardcoded frontend plus DB session content | `contract_text`, `backend_status_text`, `backend_error_text`, `db_domain_content` | Studio sessions backend catalog | Violating | `authority_violation` |
| TXT-SURF-077 | `frontend/lib/features/studio/data/studio_sessions_repository.dart` | Studio session API model fields | session title/description | API/DB content model | `db_domain_content` | Studio sessions contract and backend read composition | Aligned as field ownership | None |
| TXT-SURF-078 | `backend/app/routes/studio.py` | Studio route failures and editor messages | title required, lesson/media failures | Backend route exception text | `backend_error_text`, `backend_status_text` | Studio/backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-079 | `backend/app/services/studio_authority.py` | Studio authority failures | course/lesson owner errors | Backend hardcoded exception detail | `backend_error_text` | Studio/backend text catalog | Violating | `contract_violation` |
| TXT-SURF-080 | `backend/supabase/baseline_v2_slots/V2_0006_media_placement_and_home_audio.sql` | Home-player DB titles | `home_player_uploads.title`, `home_player_course_links.title` | DB domain fields | `db_domain_content` | Home audio contracts and backend read composition | Aligned as field ownership | None |
| TXT-SURF-081 | `frontend/lib/features/community/presentation/admin_page.dart` | Admin teacher-role UI | admin/teacher role copy | Hardcoded frontend | `contract_text`, `backend_status_text`, `backend_error_text` | Admin/backend text catalog | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-082 | `frontend/lib/features/community/presentation/admin_settings_page.dart` | Admin settings UI | admin bootstrap/settings copy | Hardcoded frontend | `contract_text`, `backend_status_text` | Admin/backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-083 | `frontend/lib/features/media_control_plane/admin/media_control_dashboard.dart` | Media control plane admin UI | admin media status text | Hardcoded frontend plus backend diagnostics | `contract_text`, `backend_status_text`, `backend_error_text` | Media control plane/backend catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-084 | `backend/app/routes/admin.py` | Admin route failures | grant/revoke/admin errors | Backend route exception text | `backend_error_text` | Admin/backend text catalog | Violating | `contract_violation` |
| TXT-SURF-085 | `backend/app/permissions.py` | Admin/teacher permission failures | `forbidden`, `admin_required` details | Backend hardcoded detail | `backend_error_text` | Backend failure catalog | Violating | `contract_violation` |
| TXT-SURF-086 | `frontend/lib/features/media/presentation/controller_video_block.dart` | Video block UI | video/loading/error labels | Hardcoded frontend plus media API details | `contract_text`, `backend_status_text`, `backend_error_text` | Media/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-087 | `frontend/lib/shared/media/AveliLessonMediaPlayer.dart` | Lesson media player | loading audio/video labels | Hardcoded frontend | `backend_status_text`, `contract_text` | Media/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-088 | `frontend/lib/shared/widgets/lesson_media_preview.dart` | Shared lesson media preview | preview loading/error text | Hardcoded frontend plus backend details | `backend_status_text`, `backend_error_text` | Media/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-089 | `frontend/lib/shared/widgets/app_network_image.dart` | Network image failure text | raw image error string | Frontend raw error text | `backend_error_text` | Media/backend text catalog | Violating | `frontend_leak`, `authority_violation` |
| TXT-SURF-090 | `frontend/lib/features/media/data/media_repository.dart` | Media repository failure text | direct Supabase public URL message | Frontend hardcoded repository failure | `backend_error_text` | Media/backend text catalog | Violating | `frontend_leak`, `authority_violation` |
| TXT-SURF-091 | `frontend/lib/services/media_service.dart` | Legacy media service failure text | legacy signing removed message | Frontend hardcoded service failure | `backend_error_text` | Media/backend text catalog | Violating | `frontend_leak`, `authority_violation` |
| TXT-SURF-092 | `backend/app/routes/media.py` | Media route failures | media delivery/preview/upload failures | Backend route exception text | `backend_error_text` | Media/backend text catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-093 | `backend/app/media_control_plane/services/media_resolver_service.py` | Media resolver failure details | runtime media failure details | Backend service failure details | `backend_error_text`, `non_user_facing_identifier` | Media/backend text catalog and control-plane diagnostics | Partial | `frontend_leak` if rendered to product UI |
| TXT-SURF-094 | `backend/supabase/baseline_v2_slots/V2_0003_media_assets.sql` | Media asset internal errors | `media_assets.error_message` | Worker/internal DB field | `non_user_facing_identifier` | Media lifecycle/control-plane observability | Aligned if not product-rendered | None |
| TXT-SURF-095 | `frontend/lib/features/messages/presentation/messages_page.dart` | Messages list | future-facing message UI copy | Hardcoded frontend | `contract_text`, `backend_status_text`, `db_user_content` | Future messaging contract/backend catalog | Violating | `authority_violation`; future-facing surface |
| TXT-SURF-096 | `frontend/lib/features/messages/presentation/chat_page.dart` | Chat UI | chat labels/messages | Hardcoded frontend plus DB/user message text | `contract_text`, `backend_status_text`, `db_user_content` | Future messaging contract/backend catalog | Violating | `authority_violation`; future-facing surface |
| TXT-SURF-097 | `frontend/lib/features/teacher/presentation/course_bundle_page.dart` | Teacher course bundle UI | package creation/payment text | Hardcoded frontend plus DB bundle title | `contract_text`, `backend_status_text`, `backend_error_text`, `db_domain_content` | Teacher commerce/backend catalog | Violating | `authority_violation` |
| TXT-SURF-098 | `backend/supabase/baseline_v2_slots/V2_0008_commerce_membership.sql` | Bundle and commerce DB fields | `course_bundles.title`, order/payment IDs | DB domain and provider fields | `db_domain_content`, `non_user_facing_identifier` | Commerce contracts and backend read composition | Aligned as field ownership | None |
| TXT-SURF-099 | `frontend/lib/mvp/mvp_app.dart` | MVP shell UI | Home/Profile/Studio labels | Hardcoded frontend | `contract_text` | Backend text catalog if MVP remains product-visible | Violating | `authority_violation` |
| TXT-SURF-100 | `frontend/lib/mvp/widgets/mvp_home_page.dart` | MVP home UI | courses/feed/services text and raw errors | Hardcoded frontend plus DB content | `contract_text`, `backend_error_text`, `db_domain_content` | Backend text catalog and typed APIs | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-101 | `frontend/lib/mvp/widgets/mvp_login_page.dart` | MVP login UI | login/register labels and raw errors | Hardcoded frontend | `contract_text`, `backend_error_text` | Backend text catalog | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-102 | `frontend/lib/mvp/widgets/mvp_profile_page.dart` | MVP profile UI | profile labels and raw errors | Hardcoded frontend plus DB/user content | `contract_text`, `backend_error_text`, `db_user_content` | Backend text catalog and profile projection | Violating | `authority_violation`, `frontend_leak` |
| TXT-SURF-103 | `frontend/lib/core/routing/not_found_page.dart` | Not-found page | not found title/body | Hardcoded frontend | `contract_text` | Backend text catalog | Violating | `authority_violation` |
| TXT-SURF-104 | `frontend/lib/core/bootstrap/auth_boot_page.dart` | Auth boot/loading state | boot/loading status text | Hardcoded frontend | `backend_status_text` | Backend text catalog | Violating | `authority_violation` |
| TXT-SURF-105 | `frontend/lib/main.dart` | Global snackbar and localization fallback | global snackbar text render, English fallback locale | Frontend render/fallback | `contract_text`, `backend_status_text` | Backend text catalog; Swedish-only locale policy | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-106 | `frontend/lib/core/errors/app_failure.dart` | Frontend error fallback map | exception-to-message mapping | Frontend error authority | `backend_error_text` | Backend failure catalog | Violating | `authority_violation`, `contract_violation` |
| TXT-SURF-107 | `frontend/lib/shared/utils/error_messages.dart` | Shared raw error fallback | `error.toString()` | Frontend raw error authority | `backend_error_text` | Backend failure catalog | Violating | `frontend_leak`, `authority_violation` |
| TXT-SURF-108 | `frontend/lib/shared/utils/snack.dart` | Snackbar renderer | caller-supplied message | Frontend renderer helper | Inherited from caller text class | Backend/catalog or DB owner upstream | Partial | `authority_violation` if caller text is frontend-originated |
| TXT-SURF-109 | `frontend/lib/shared/widgets/app_scaffold.dart` | Shared scaffold/nav chrome | Home/back tooltips | Hardcoded frontend | `contract_text` | Backend text catalog | Violating | `authority_violation` |
| TXT-SURF-110 | `frontend/lib/shared/widgets/top_nav_action_buttons.dart` | Top nav action buttons | Home/teacher/profile tooltips | Hardcoded frontend | `contract_text` | Backend text catalog | Violating | `authority_violation` |
| TXT-SURF-111 | `frontend/lib/widgets/app_logo.dart` | Brand logo text | `Aveli` | Hardcoded brand mark | `contract_text` | Brand/text contract and backend catalog | Partial | `authority_violation` until catalog-owned if rendered as copy |
| TXT-SURF-112 | `frontend/lib/shared/widgets/brand_header.dart` | Brand header | `Aveli` wordmark | Hardcoded brand mark | `contract_text` | Brand/text contract and backend catalog | Partial | `authority_violation` until catalog-owned if rendered as copy |
| TXT-SURF-113 | `frontend/lib/shared/widgets/card_text.dart` | Course/teacher card text renderers | course title/description/teacher name | Caller/API supplied text | `db_domain_content`, `db_user_content` | Backend read composition | Aligned as renderer if caller-provenance exists | None |
| TXT-SURF-114 | `frontend/lib/shared/widgets/course_card.dart` | Course card | course display text and labels | Hardcoded frontend plus DB course fields | `contract_text`, `db_domain_content`, `db_user_content` | Course/backend text catalog and read composition | Violating | `authority_violation` |
| TXT-SURF-115 | `frontend/lib/shared/widgets/service_card.dart` | Service card | service title/description/area labels | Hardcoded frontend plus DB/API content | `contract_text`, `db_domain_content`, `db_user_content` | Community/backend text catalog | Violating | `authority_violation` |
| TXT-SURF-116 | `frontend/lib/shared/widgets/teacher_card.dart` | Teacher card | teacher display name and labels | Hardcoded frontend plus profile content | `contract_text`, `db_user_content` | Community/backend text catalog and profile projection | Violating | `authority_violation` |
| TXT-SURF-117 | `frontend/lib/domain/services/ai/gemini_client.dart` | AI helper action text | default `OK` label | Frontend fallback label | `backend_status_text` | Backend text catalog if user-visible | Violating | `authority_violation` |
| TXT-SURF-118 | `backend/app/main.py` | Global backend error handler | exception/failure envelopes | Backend framework/error text | `backend_error_text` | Backend failure catalog | Partial | `contract_violation` if legacy fields emitted |
| TXT-SURF-119 | `backend/app/routes/community.py` | Community route failures/content | community profile/service route text | Backend route/service text and DB content | `backend_error_text`, `db_domain_content`, `db_user_content` | Community/backend text catalog and read composition | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-120 | `backend/app/routes/courses.py` | Course route failures/content | course/lesson access failures and DB content | Backend route text and DB content | `backend_error_text`, `db_domain_content` | Course/backend text catalog and read composition | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-121 | `backend/app/routes/course_bundles.py` | Course bundle route failures/content | bundle checkout/errors/title | Backend route text and DB bundle content | `backend_error_text`, `backend_stripe_text`, `db_domain_content` | Commerce/backend text catalog and read composition | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-122 | `backend/app/routes/landing.py` | Landing route content | landing course/public data | Backend route and DB content | `contract_text`, `db_domain_content`, `db_user_content` | Landing/backend text catalog and typed read composition | Partial | `authority_violation` until product copy catalog-owned |
| TXT-SURF-123 | `backend/app/routes/referrals.py` | Referral route failures | referral redeem/create failures | Backend route text | `backend_error_text`, `backend_email_text` | Referral/backend text catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-124 | `backend/app/routes/email_verification.py` | Email verification route failures | verification token failures | Backend route text | `backend_error_text`, `backend_email_text` | Auth/email backend catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-125 | `backend/app/routes/upload.py` | Upload route failures | media upload validation errors | Backend route text | `backend_error_text`, `backend_status_text` | Media/backend text catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-126 | `backend/app/routes/api_media.py` | API media route failures | media operation errors | Backend route text | `backend_error_text` | Media/backend text catalog | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-127 | `backend/app/routes/api_services.py` | Service route content/failures | service title/description/errors | Backend route text and DB content | `backend_error_text`, `db_domain_content`, `db_user_content` | Community/backend text catalog and read composition | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-128 | `backend/app/routes/api_feed.py` | Feed route content/failures | feed item summaries/errors | Backend route text and DB content | `backend_error_text`, `db_domain_content`, `db_user_content` | Home/backend text catalog and read composition | Violating | `authority_violation` until catalog-owned |
| TXT-SURF-129 | `backend/app/routes/api_notifications.py` | Notification route text | notification payload/status/errors | Backend route text and DB/user content | `backend_error_text`, `db_domain_content`, `db_user_content` | Notification contract/backend catalog | Blocked for future-facing contract | `contract_violation` until explicit notification text contract exists |
| TXT-SURF-130 | `backend/app/routes/api_events.py` | Events route text | event payload/status/errors | Backend route text and DB/user content | `backend_error_text`, `db_domain_content`, `db_user_content` | Events contract/backend catalog | Blocked for future-facing contract | `contract_violation` until explicit events text contract exists |
| TXT-SURF-131 | `backend/app/routes/seminars.py` | Seminar route text | seminar status/errors/content | Backend route text and DB content | `backend_error_text`, `db_domain_content` | Future seminar contract/backend catalog | Blocked for future-facing contract | `contract_violation` until explicit seminar text contract exists |
| TXT-SURF-132 | `backend/app/routes/session_slots.py` | Session slots route text | session labels/descriptions/errors | Backend route text and DB content | `backend_error_text`, `db_domain_content` | Session contract/backend catalog | Blocked for future-facing contract | `contract_violation` until explicit session text contract exists |
| TXT-SURF-133 | `backend/app/routes/logs_mcp.py` | Logs MCP descriptions | tool descriptions | MCP/operator diagnostics | `non_user_facing_identifier` | MCP/operator contract | Aligned if not product-rendered | None |
| TXT-SURF-134 | `backend/app/routes/verification_mcp.py` | Verification MCP descriptions | tool descriptions | MCP/operator diagnostics | `non_user_facing_identifier` | MCP/operator contract | Aligned if not product-rendered | None |
| TXT-SURF-135 | `backend/app/routes/media_control_plane_mcp.py` | Media control plane MCP descriptions | diagnostic tool descriptions | MCP/operator diagnostics | `non_user_facing_identifier` | MCP/operator contract | Aligned if not product-rendered | None |
| TXT-SURF-136 | `backend/app/routes/stripe_observability_mcp.py` | Stripe observability MCP descriptions | diagnostic tool descriptions | MCP/operator diagnostics | `non_user_facing_identifier` | MCP/operator contract | Aligned if not product-rendered | None |
| TXT-SURF-137 | `backend/app/routes/supabase_observability_mcp.py` | Supabase observability MCP descriptions | diagnostic tool descriptions | MCP/operator diagnostics | `non_user_facing_identifier` | MCP/operator contract | Aligned if not product-rendered | None |
| TXT-SURF-138 | `backend/app/routes/netlify_observability_mcp.py` | Netlify observability MCP descriptions | diagnostic tool descriptions | MCP/operator diagnostics | `non_user_facing_identifier` | MCP/operator contract | Aligned if not product-rendered | None |
| TXT-SURF-139 | `backend/supabase/baseline_v2_slots/V2_0010_read_projections.sql` | Read projection text fields | course title, lesson title, short description, content markdown | DB projection from source tables | `db_domain_content` | Source table contracts and backend read composition | Aligned as field ownership | None |
| TXT-SURF-140 | `backend/supabase/baseline_v2_slots/V2_0009_runtime_support_inert.sql` | Observability/support text fields | billing/media/auth event metadata | Support/observability DB fields | `non_user_facing_identifier` | Observability contracts | Aligned if not product-rendered | None |

## DB-Rendered Field Classification

| DB field | Required authority class | Canonical owner | Render rule |
|---|---|---|---|
| `app.profiles.display_name` | `db_user_content` | Profile projection contract | May render only as profile/user display content after backend read composition |
| `app.profiles.bio` | `db_user_content` | Profile projection contract | May render only as profile/user authored content after backend read composition |
| `auth.users.email` or `app.auth_subjects.email` when projected | `db_user_content` | Auth/profile projection contracts | May render only as account identity text, never UI chrome |
| `app.courses.title` | `db_domain_content` | Course contracts | May render as course display title through backend read composition |
| `app.course_public_content.short_description` | `db_domain_content` | Course public surface contract | May render as public course description through backend read composition |
| `app.lessons.lesson_title` | `db_domain_content` | Course/lesson contracts | May render as lesson structure title through backend read composition |
| `app.lesson_contents.content_markdown` | `db_domain_content` | Course/lesson contracts | May render only on lesson content/editor surfaces through backend read composition |
| `app.home_player_uploads.title` | `db_domain_content` | Home audio contracts | May render as home-player media title through backend read composition |
| `app.home_player_course_links.title` | `db_domain_content` | Home audio contracts | May render as course-linked home-player title through backend read composition |
| `app.course_bundles.title` | `db_domain_content` | Commerce/course bundle contracts | May render as bundle title through backend read composition |
| `app.media_assets.error_message` | `non_user_facing_identifier` | Media lifecycle/control-plane observability | Must not render as ordinary product UI copy |
| `app.media_resolution_failures.reason` | `non_user_facing_identifier` | Media observability/control-plane | Must not render as ordinary product UI copy |
| `app.referral_codes.email` | `non_user_facing_identifier` | Referral transport contract | May be used for transport/account context, not UI chrome |
| `app.orders.* provider/session/payment identifiers` | `non_user_facing_identifier` | Commerce contracts | Must not render as product copy |
| `app.payments.* provider references` | `non_user_facing_identifier` | Commerce contracts | Must not render as product copy |
| `app.payment_events.*`, `app.billing_logs.*`, `app.media_events.*`, `app.auth_events.*` | `non_user_facing_identifier` | Observability/support contracts | Operator/diagnostic only |

## Additional Frontend Candidate Coverage

The following frontend files were identified as text-rendering or
text-forwarding locations. Their required authority class is inherited from
their surface row above or from caller provenance; none is a valid text
authority by itself.

- `frontend/lib/core/bootstrap/auth_boot_page.dart`
- `frontend/lib/core/routing/not_found_page.dart`
- `frontend/lib/domain/services/ai/gemini_client.dart`
- `frontend/lib/editor/debug/editor_debug_overlay.dart`
- `frontend/lib/features/auth/presentation/forgot_password_page.dart`
- `frontend/lib/features/auth/presentation/login_page.dart`
- `frontend/lib/features/auth/presentation/new_password_page.dart`
- `frontend/lib/features/auth/presentation/settings_page.dart`
- `frontend/lib/features/auth/presentation/signup_page.dart`
- `frontend/lib/features/auth/presentation/verify_email_page.dart`
- `frontend/lib/features/community/presentation/admin_page.dart`
- `frontend/lib/features/community/presentation/admin_settings_page.dart`
- `frontend/lib/features/community/presentation/community_page.dart`
- `frontend/lib/features/community/presentation/home_page.dart`
- `frontend/lib/features/community/presentation/home_shell.dart`
- `frontend/lib/features/community/presentation/profile_page.dart`
- `frontend/lib/features/community/presentation/profile_view_page.dart`
- `frontend/lib/features/community/presentation/service_detail_page.dart`
- `frontend/lib/features/community/presentation/tarot_page.dart`
- `frontend/lib/features/community/presentation/teacher_profile_page.dart`
- `frontend/lib/features/community/presentation/widgets/profile_logout_section.dart`
- `frontend/lib/features/courses/presentation/course_access_gate.dart`
- `frontend/lib/features/courses/presentation/course_catalog_page.dart`
- `frontend/lib/features/courses/presentation/course_intro_page.dart`
- `frontend/lib/features/courses/presentation/course_intro_redirect_page.dart`
- `frontend/lib/features/courses/presentation/course_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/lib/features/home/presentation/home_dashboard_page.dart`
- `frontend/lib/features/landing/presentation/landing_page.dart`
- `frontend/lib/features/landing/presentation/legal/privacy_page.dart`
- `frontend/lib/features/landing/presentation/legal/terms_page.dart`
- `frontend/lib/features/media/presentation/controller_video_block.dart`
- `frontend/lib/features/media_control_plane/admin/media_control_dashboard.dart`
- `frontend/lib/features/messages/presentation/chat_page.dart`
- `frontend/lib/features/messages/presentation/messages_page.dart`
- `frontend/lib/features/onboarding/onboarding_profile_page.dart`
- `frontend/lib/features/onboarding/welcome_page.dart`
- `frontend/lib/features/payments/presentation/booking_page.dart`
- `frontend/lib/features/payments/presentation/embedded_membership_checkout_surface_stub.dart`
- `frontend/lib/features/payments/presentation/embedded_membership_checkout_surface_web.dart`
- `frontend/lib/features/payments/presentation/embedded_membership_checkout_surface_webview.dart`
- `frontend/lib/features/payments/presentation/paywall_prompt.dart`
- `frontend/lib/features/payments/presentation/subscribe_screen.dart`
- `frontend/lib/features/paywall/presentation/checkout_result_page.dart`
- `frontend/lib/features/paywall/presentation/checkout_webview_page.dart`
- `frontend/lib/features/profile/presentation/my_subscription_page.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/studio/presentation/editor_media_controls.dart`
- `frontend/lib/features/studio/presentation/lesson_media_preview.dart`
- `frontend/lib/features/studio/presentation/profile_media_page.dart`
- `frontend/lib/features/studio/presentation/studio_page.dart`
- `frontend/lib/features/studio/presentation/teacher_home_page.dart`
- `frontend/lib/features/studio/widgets/cover_upload_card.dart`
- `frontend/lib/features/studio/widgets/home_player_upload_dialog.dart`
- `frontend/lib/features/studio/widgets/studio_calendar.dart`
- `frontend/lib/features/studio/widgets/wav_replace_dialog.dart`
- `frontend/lib/features/studio/widgets/wav_upload_card.dart`
- `frontend/lib/features/teacher/presentation/course_bundle_page.dart`
- `frontend/lib/main.dart`
- `frontend/lib/mvp/mvp_app.dart`
- `frontend/lib/mvp/widgets/mvp_home_page.dart`
- `frontend/lib/mvp/widgets/mvp_login_page.dart`
- `frontend/lib/mvp/widgets/mvp_profile_page.dart`
- `frontend/lib/shared/media/AveliLessonImage.dart`
- `frontend/lib/shared/media/AveliLessonMediaPlayer.dart`
- `frontend/lib/shared/utils/media_permissions.dart`
- `frontend/lib/shared/utils/snack.dart`
- `frontend/lib/shared/widgets/app_scaffold.dart`
- `frontend/lib/shared/widgets/aveli_video_player.dart`
- `frontend/lib/shared/widgets/brand_header.dart`
- `frontend/lib/shared/widgets/card_text.dart`
- `frontend/lib/shared/widgets/course_card.dart`
- `frontend/lib/shared/widgets/course_intro_badge.dart`
- `frontend/lib/shared/widgets/course_video.dart`
- `frontend/lib/shared/widgets/courses_grid.dart`
- `frontend/lib/shared/widgets/courses_showcase_section.dart`
- `frontend/lib/shared/widgets/env_banner.dart`
- `frontend/lib/shared/widgets/go_router_back_button.dart`
- `frontend/lib/shared/widgets/gradient_button.dart`
- `frontend/lib/shared/widgets/gradient_text.dart`
- `frontend/lib/shared/widgets/header_text.dart`
- `frontend/lib/shared/widgets/hero_badge.dart`
- `frontend/lib/shared/widgets/hero_cta.dart`
- `frontend/lib/shared/widgets/home_hero_panel.dart`
- `frontend/lib/shared/widgets/inline_audio_player_io.dart`
- `frontend/lib/shared/widgets/inline_audio_player_web.dart`
- `frontend/lib/shared/widgets/intro_card.dart`
- `frontend/lib/shared/widgets/kit.dart`
- `frontend/lib/shared/widgets/lesson_media_preview.dart`
- `frontend/lib/shared/widgets/lesson_video_block.dart`
- `frontend/lib/shared/widgets/media_player.dart`
- `frontend/lib/shared/widgets/semantic_text.dart`
- `frontend/lib/shared/widgets/service_card.dart`
- `frontend/lib/shared/widgets/teacher_card.dart`
- `frontend/lib/shared/widgets/top_nav_action_buttons.dart`
- `frontend/lib/widgets/app_logo.dart`
- `frontend/lib/widgets/base_page.dart`

## Blockers Recorded For Downstream Tasks

TXT-001 ownership classification has no unclassified current product surface
in the inspected roots.

The following are downstream blockers, not TXT-001 ownership blockers:

- Future-facing messages, events, seminars, and session-slot surfaces require
  explicit product text contracts before TXT-003 can create catalog entries.
- Live/current DB row values were not queried in TXT-001. TXT-004 must verify
  DB value language and encoding before rendered DB content can be confirmed.
- Runtime API response bytes were not captured in TXT-001. TXT-005 and later
  gates must verify emitted UTF-8 and envelope compliance.
- Rendered browser/app text was not captured in TXT-001. TXT-007 through
  TXT-010 must verify rendered UI extraction.

## TXT-002 Preconditions

TXT-002 may begin when this artifact and
`actual_truth/contracts/system_text_authority_contract.md` exist.

TXT-002 MUST treat this inventory as the complete TXT-001 ownership baseline
and MUST fail closed if it discovers any additional in-scope text-producing
surface not represented here.

## Final TXT-001 Assertions

- Every inventoried user-facing text surface has exactly one required authority
  class or an explicitly inherited upstream class for renderer-only helpers.
- Frontend is never defined as a valid authority for user-facing text.
- All user-facing product text in the contract model is defined to be Swedish.
- Generated operator prompts are required to be copy-paste-ready English.
- No frontend, backend, schema, DB, API envelope, or rendering logic was
  modified by TXT-001.
