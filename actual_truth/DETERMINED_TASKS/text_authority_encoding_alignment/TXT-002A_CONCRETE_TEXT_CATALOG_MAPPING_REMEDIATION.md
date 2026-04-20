# TXT-002A Concrete Text Catalog Mapping Remediation

TYPE: OWNER
DEPENDS_ON: [TXT-001, TXT-002]
MODE: execute
STATUS: COMPLETE_FOR_TXT_003_NON_LEGAL_ENTRY

This artifact supersedes the ambiguous wildcard catalog targets in
`TXT-002_TEXT_CATALOG_MAPPING.md` for TXT-003 entry. It does not change runtime
code, frontend rendering, backend routes, API envelopes, DB schema, email
templates, or Stripe behavior.

This artifact exists because the prior TXT-003 execution was blocked for
authority reasons: TXT-002 contained family-style target mappings, and legal
copy ownership was unresolved. The block was not an implementation failure.

## 1. Authority Load

Loaded authority inputs:

- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-001_TEXT_SURFACE_INVENTORY.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-002_TEXT_CATALOG_MAPPING.md`
- the blocked TXT-003 execution result from the current operator thread
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- active contracts under `actual_truth/contracts/`

## 2. Precheck Result

TXT-001 and TXT-002 exist and are sufficient to perform a planning-layer
correction.

TXT-003 was blocked because:

- eligible TXT-002 rows used family-style target mappings instead of concrete
  text IDs,
- legal page/body copy lacked exact active contract ownership,
- legal navigation labels lacked exact active contract ownership,
- future-facing surfaces remained correctly blocked,
- runtime implementation was not attempted.

No runtime cutover is authorized by this remediation.

## 3. Supersession Rule

For TXT-003 non-legal value population:

- this artifact is the concrete target registry,
- `TXT-002_TEXT_CATALOG_MAPPING.md` remains historical TXT-002 context,
- if this artifact and TXT-002 disagree about a non-legal eligible target,
  this artifact governs TXT-003 entry,
- if this artifact marks a target as blocked, TXT-003 MUST NOT populate it.

Every target in this artifact ends as one of:

- concrete canonical text ID,
- concrete DB-owned content field,
- concrete non-user-facing identifier,
- concrete blocked surface ID with reason.

## 4. Eligible Non-Legal Concrete Catalog Targets

All catalog text IDs below are internal ASCII identifiers. TXT-003 may populate
Swedish values for these IDs only. No value is created by this artifact.

### Auth, Onboarding, And Email

Surface IDs:

`TXT-SURF-001`, `TXT-SURF-002`, `TXT-SURF-007`, `TXT-SURF-008`,
`TXT-SURF-009`, `TXT-SURF-010`, `TXT-SURF-011`, `TXT-SURF-012`,
`TXT-SURF-013`, `TXT-SURF-014`, `TXT-SURF-015`, `TXT-SURF-016`,
`TXT-SURF-017`, `TXT-SURF-018`, `TXT-SURF-019`, `TXT-SURF-020`,
`TXT-SURF-021`, `TXT-SURF-022`, `TXT-SURF-123`, `TXT-SURF-124`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| Login UI | `contract_text`, `backend_error_text` | `auth.login.title`, `auth.login.email_label`, `auth.login.password_label`, `auth.login.submit_action`, `auth.login.forgot_password_action`, `auth.login.signup_action`, `auth.login.loading_status`, `auth.login.success_status` |
| Signup UI | `contract_text`, `backend_error_text` | `auth.signup.title`, `auth.signup.email_label`, `auth.signup.password_label`, `auth.signup.submit_action`, `auth.signup.login_action`, `auth.signup.loading_status`, `auth.signup.success_status` |
| Forgot password UI | `contract_text`, `backend_status_text`, `backend_error_text` | `auth.password.forgot.title`, `auth.password.forgot.email_label`, `auth.password.forgot.submit_action`, `auth.password.forgot.loading_status`, `auth.password.forgot.sent_status`, `auth.password.forgot.retry_action` |
| Reset password UI | `contract_text`, `backend_status_text`, `backend_error_text` | `auth.password.reset.title`, `auth.password.reset.new_password_label`, `auth.password.reset.confirm_password_label`, `auth.password.reset.submit_action`, `auth.password.reset.loading_status`, `auth.password.reset.success_status` |
| Verify email UI | `contract_text`, `backend_status_text`, `backend_error_text` | `auth.email_verification.title`, `auth.email_verification.body`, `auth.email_verification.resend_action`, `auth.email_verification.resending_status`, `auth.email_verification.resent_status`, `auth.email_verification.verified_status`, `auth.email_verification.already_verified_status` |
| Auth settings UI | `contract_text`, `backend_status_text` | `auth.settings.title`, `auth.settings.send_verification_action`, `auth.settings.change_password_action`, `auth.settings.loading_status`, `auth.settings.saved_status` |
| Auth failure messages | `backend_error_text` | `auth.error.invalid_or_expired_token`, `auth.error.invalid_current_password`, `auth.error.new_password_must_differ`, `auth.error.invalid_credentials`, `auth.error.unauthenticated`, `auth.error.refresh_token_invalid`, `auth.error.email_already_registered`, `auth.error.validation_error`, `auth.error.rate_limited`, `auth.error.internal_error` |
| Onboarding create-profile UI | `contract_text`, `backend_status_text`, `backend_error_text` | `onboarding.create_profile.title`, `onboarding.create_profile.body`, `onboarding.create_profile.display_name_label`, `onboarding.create_profile.bio_label`, `onboarding.create_profile.submit_action`, `onboarding.create_profile.saving_status`, `onboarding.create_profile.success_status`, `onboarding.create_profile.display_name_required_error` |
| Onboarding welcome UI | `contract_text`, `backend_status_text`, `backend_error_text` | `onboarding.welcome.title`, `onboarding.welcome.body`, `onboarding.welcome.confirmation_action`, `onboarding.welcome.completing_status`, `onboarding.welcome.completed_status` |
| Onboarding failure messages | `backend_error_text` | `onboarding.error.welcome_confirmation_required`, `onboarding.error.subject_not_found`, `onboarding.error.profile_not_found`, `onboarding.error.already_teacher`, `onboarding.error.already_learner`, `onboarding.error.admin_bootstrap_already_consumed`, `onboarding.error.forbidden`, `onboarding.error.admin_required` |
| Email verification template | `backend_email_text` | `email.verify.subject`, `email.verify.heading`, `email.verify.body_intro`, `email.verify.body_instruction`, `email.verify.cta`, `email.verify.plain_text`, `email.verify.footer` |
| Reset-password email template | `backend_email_text` | `email.password_reset.subject`, `email.password_reset.heading`, `email.password_reset.body_intro`, `email.password_reset.body_instruction`, `email.password_reset.cta`, `email.password_reset.plain_text`, `email.password_reset.footer` |
| Referral email template | `backend_email_text` | `email.referral.subject`, `email.referral.heading`, `email.referral.body_intro`, `email.referral.body_invitation`, `email.referral.cta`, `email.referral.plain_text`, `email.referral.footer` |
| Referral route failures | `backend_error_text`, `backend_email_text` | `email.referral.error.invalid_referral`, `email.referral.error.already_redeemed`, `email.referral.error.send_failed`, `email.referral.status.sent` |
| Email verification route failures | `backend_error_text`, `backend_email_text` | `email.verify.error.invalid_token`, `email.verify.error.expired_token`, `email.verify.error.send_failed` |

Concrete DB-owned fields:

- `app.profiles.display_name`
- `app.profiles.bio`

Concrete non-user-facing identifiers:

- `identifier.auth.error_code.invalid_credentials`
- `identifier.auth.error_code.unauthenticated`
- `identifier.auth.error_code.validation_error`
- `identifier.auth.error_code.internal_error`
- `identifier.entry_state.onboarding_state`
- `identifier.entry_state.needs_payment`
- `identifier.entry_state.needs_onboarding`
- `identifier.entry_state.can_enter_app`

### Profile

Surface IDs:

`TXT-SURF-004`, `TXT-SURF-005`, `TXT-SURF-006`, `TXT-SURF-052`,
`TXT-SURF-056`, `TXT-SURF-102`, `TXT-SURF-116`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| Current profile UI | `contract_text`, `backend_status_text`, `backend_error_text` | `profile.page.title`, `profile.form.display_name_label`, `profile.form.bio_label`, `profile.form.save_action`, `profile.form.saving_status`, `profile.form.saved_status`, `profile.form.save_failed_error` |
| Password section | `contract_text`, `backend_status_text`, `backend_error_text` | `profile.password.change_action`, `profile.password.change_title`, `profile.password.reset_send_action`, `profile.password.reset_sent_status`, `profile.password.reset_failed_error` |
| Profile API failures | `backend_error_text` | `profile.error.profile_not_found`, `profile.error.update_failed`, `profile.error.unauthenticated` |
| Public profile UI | `contract_text` | `profile.public.title`, `profile.public.display_name_label`, `profile.public.bio_label`, `profile.public.courses_label`, `profile.public.services_label`, `profile.public.empty_bio_status` |
| Logout section | `contract_text`, `backend_status_text` | `profile.logout.title`, `profile.logout.body`, `profile.logout.action`, `profile.logout.loading_status`, `profile.logout.completed_status` |
| Teacher card labels | `contract_text` | `profile.teacher_card.teacher_label`, `profile.teacher_card.open_profile_action`, `profile.teacher_card.no_bio_status` |

Concrete DB-owned fields:

- `app.profiles.display_name`
- `app.profiles.bio`
- `auth.users.email`

### Checkout, Payments, And Commerce

Surface IDs:

`TXT-SURF-003`, `TXT-SURF-023`, `TXT-SURF-024`, `TXT-SURF-025`,
`TXT-SURF-026`, `TXT-SURF-027`, `TXT-SURF-028`, `TXT-SURF-029`,
`TXT-SURF-030`, `TXT-SURF-031`, `TXT-SURF-032`, `TXT-SURF-033`,
`TXT-SURF-034`, `TXT-SURF-035`, `TXT-SURF-036`, `TXT-SURF-097`,
`TXT-SURF-098`, `TXT-SURF-121`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| Membership checkout | `backend_stripe_text`, `backend_status_text`, `backend_error_text` | `checkout.membership.headline`, `checkout.membership.trial_card_line`, `checkout.membership.contents_live_lessons`, `checkout.membership.contents_course_access`, `checkout.membership.contents_meditations`, `checkout.membership.contents_safe_learning`, `checkout.membership.trust_line`, `checkout.membership.primary_action`, `checkout.membership.creating_status`, `checkout.membership.creation_failed_error` |
| Embedded checkout shell | `backend_stripe_text`, `backend_status_text` | `checkout.embedded.loading`, `checkout.embedded.unsupported`, `checkout.embedded.retry_action`, `checkout.embedded.close_action` |
| Checkout return and cancel | `backend_stripe_text`, `backend_status_text`, `backend_error_text` | `checkout.return.title`, `checkout.return.waiting_status`, `checkout.return.retry_action`, `checkout.return.confirmed_status`, `checkout.return.failed_status`, `checkout.cancel.title`, `checkout.cancel.body`, `checkout.cancel.retry_action` |
| Paywall and booking prompt | `contract_text`, `backend_status_text` | `checkout.paywall.title`, `checkout.paywall.body`, `checkout.paywall.primary_action`, `checkout.paywall.dismiss_action`, `checkout.booking.title`, `checkout.booking.unavailable_status`, `checkout.booking.contact_action` |
| Course checkout | `backend_stripe_text`, `backend_error_text` | `checkout.course.title`, `checkout.course.start_action`, `checkout.course.loading_status`, `checkout.course.failed_error`, `checkout.course.unavailable_error` |
| Bundle checkout | `backend_stripe_text`, `backend_error_text` | `checkout.bundle.title`, `checkout.bundle.start_action`, `checkout.bundle.loading_status`, `checkout.bundle.failed_error`, `checkout.bundle.unavailable_error` |
| Billing and subscription failures | `backend_stripe_text`, `backend_error_text` | `checkout.error.checkout_unavailable`, `checkout.error.session_create_failed`, `checkout.error.customer_create_failed`, `checkout.error.subscription_create_failed`, `checkout.error.payment_required`, `checkout.error.membership_not_confirmed` |
| Payment result states | `backend_stripe_text`, `backend_status_text`, `backend_error_text` | `payments.status.waiting`, `payments.status.confirmed`, `payments.status.failed`, `payments.status.canceled`, `payments.status.retrying`, `payments.action.retry`, `payments.error.provider_unavailable`, `payments.error.payment_not_confirmed`, `payments.error.checkout_session_failed` |

Concrete DB-owned field:

- `app.course_bundles.title`

Concrete non-user-facing identifiers:

- `identifier.stripe.session_id`
- `identifier.stripe.client_secret`
- `identifier.stripe.customer_id`
- `identifier.stripe.payment_intent_id`
- `identifier.stripe.subscription_id`
- `identifier.commerce.order_id`
- `identifier.commerce.payment_id`
- `identifier.commerce.provider_reference`
- `identifier.commerce.billing_event_type`

### Home And Community

Surface IDs:

`TXT-SURF-049`, `TXT-SURF-050`, `TXT-SURF-051`, `TXT-SURF-053`,
`TXT-SURF-054`, `TXT-SURF-055`, `TXT-SURF-057`, `TXT-SURF-115`,
`TXT-SURF-119`, `TXT-SURF-127`, `TXT-SURF-128`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| Home dashboard | `contract_text`, `backend_status_text`, `backend_error_text` | `home.dashboard.title`, `home.dashboard.welcome_heading`, `home.dashboard.feed_heading`, `home.dashboard.services_heading`, `home.dashboard.empty_feed_status`, `home.dashboard.empty_services_status`, `home.dashboard.loading_status`, `home.dashboard.load_failed_error` |
| Home feed | `contract_text`, `backend_status_text`, `backend_error_text` | `home.feed.title`, `home.feed.empty_status`, `home.feed.loading_status`, `home.feed.load_failed_error`, `home.feed.retry_action` |
| Certification gate | `backend_status_text` | `home.certification.title`, `home.certification.login_required_status`, `home.certification.unavailable_status`, `home.certification.retry_action` |
| Community home and navigation | `contract_text`, `backend_status_text`, `backend_error_text` | `community.home.title`, `community.home.teachers_heading`, `community.home.services_heading`, `community.navigation.home_label`, `community.navigation.teachers_label`, `community.navigation.services_label`, `community.error.load_failed` |
| Teacher and service surfaces | `contract_text`, `backend_status_text`, `backend_error_text` | `community.teacher.title`, `community.teacher.services_heading`, `community.teacher.empty_services_status`, `community.service.title`, `community.service.booking_action`, `community.service.booking_unavailable_status`, `community.service.load_failed_error` |
| Tarot surface | `contract_text`, `backend_status_text`, `backend_error_text` | `community.tarot.title`, `community.tarot.body`, `community.tarot.start_action`, `community.tarot.loading_status`, `community.tarot.unavailable_status`, `community.tarot.error` |
| Community route failures | `backend_error_text` | `community.error.profile_not_found`, `community.error.service_not_found`, `community.error.unauthenticated`, `community.error.forbidden`, `community.error.internal_error` |
| Service and feed route failures | `backend_error_text` | `community.service.error.not_found`, `community.service.error.load_failed`, `home.feed.error.load_failed`, `home.feed.error.internal_error` |

Concrete DB-owned fields:

- `app.profiles.display_name`
- `app.profiles.bio`
- `app.courses.title`
- `app.course_public_content.short_description`

### Course And Lesson

Surface IDs:

`TXT-SURF-058`, `TXT-SURF-059`, `TXT-SURF-060`, `TXT-SURF-061`,
`TXT-SURF-062`, `TXT-SURF-063`, `TXT-SURF-064`, `TXT-SURF-065`,
`TXT-SURF-100`, `TXT-SURF-114`, `TXT-SURF-120`, `TXT-SURF-139`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| Course catalog | `contract_text`, `backend_status_text`, `backend_error_text` | `course_lesson.catalog.title`, `course_lesson.catalog.empty_status`, `course_lesson.catalog.loading_status`, `course_lesson.catalog.load_failed_error`, `course_lesson.catalog.retry_action` |
| Course intro | `contract_text`, `backend_status_text` | `course_lesson.intro.title`, `course_lesson.intro.start_action`, `course_lesson.intro.continue_action`, `course_lesson.intro.unavailable_status` |
| Course detail | `contract_text`, `backend_status_text`, `backend_error_text` | `course_lesson.detail.lessons_heading`, `course_lesson.detail.price_label`, `course_lesson.detail.access_included_status`, `course_lesson.detail.purchase_action`, `course_lesson.detail.loading_status`, `course_lesson.detail.load_failed_error` |
| Intro redirect | `backend_status_text`, `backend_error_text` | `course_lesson.redirect.loading_status`, `course_lesson.redirect.success_status`, `course_lesson.redirect.failed_error` |
| Course access gate | `backend_status_text`, `backend_error_text` | `course_lesson.access_gate.locked_title`, `course_lesson.access_gate.locked_body`, `course_lesson.access_gate.login_required_status`, `course_lesson.access_gate.purchase_required_status`, `course_lesson.access_gate.forbidden_error` |
| Lesson view | `contract_text`, `backend_status_text`, `backend_error_text` | `course_lesson.lesson.title_label`, `course_lesson.lesson.content_loading_status`, `course_lesson.lesson.content_empty_status`, `course_lesson.lesson.media_loading_status`, `course_lesson.lesson.media_unavailable_status`, `course_lesson.lesson.load_failed_error`, `course_lesson.lesson.retry_action` |
| Course and lesson route failures | `backend_error_text` | `course_lesson.error.course_not_found`, `course_lesson.error.lesson_not_found`, `course_lesson.error.enrollment_required`, `course_lesson.error.lesson_locked`, `course_lesson.error.internal_error` |
| Course card chrome | `contract_text` | `course_lesson.card.open_course_action`, `course_lesson.card.price_label`, `course_lesson.card.included_status`, `course_lesson.card.teacher_label` |

Concrete DB-owned fields:

- `app.courses.title`
- `app.course_public_content.short_description`
- `app.lessons.lesson_title`
- `app.lesson_contents.content_markdown`

### Studio, Editor, And Home Player

Surface IDs:

`TXT-SURF-066`, `TXT-SURF-067`, `TXT-SURF-068`, `TXT-SURF-069`,
`TXT-SURF-070`, `TXT-SURF-071`, `TXT-SURF-072`, `TXT-SURF-073`,
`TXT-SURF-074`, `TXT-SURF-075`, `TXT-SURF-078`, `TXT-SURF-079`,
`TXT-SURF-080`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| Studio entry | `contract_text`, `backend_status_text`, `backend_error_text` | `studio_editor.entry.title`, `studio_editor.entry.teacher_required_status`, `studio_editor.entry.loading_status`, `studio_editor.entry.load_failed_error`, `studio_editor.entry.open_dashboard_action` |
| Teacher home | `contract_text`, `backend_status_text`, `backend_error_text` | `studio_editor.teacher_home.title`, `studio_editor.teacher_home.courses_heading`, `studio_editor.teacher_home.home_player_heading`, `studio_editor.teacher_home.create_course_action`, `studio_editor.teacher_home.empty_courses_status`, `studio_editor.teacher_home.load_failed_error` |
| Course editor | `contract_text`, `backend_status_text`, `backend_error_text` | `studio_editor.course_editor.title`, `studio_editor.course_editor.course_title_label`, `studio_editor.course_editor.slug_label`, `studio_editor.course_editor.price_label`, `studio_editor.course_editor.save_action`, `studio_editor.course_editor.saving_status`, `studio_editor.course_editor.saved_status`, `studio_editor.course_editor.save_failed_error`, `studio_editor.course_editor.preview_action` |
| Editor validation | `backend_error_text` | `studio_editor.validation.course_title_required`, `studio_editor.validation.slug_required`, `studio_editor.validation.lesson_title_required`, `studio_editor.validation.position_required`, `studio_editor.validation.content_required` |
| Editor media controls | `contract_text`, `backend_status_text`, `backend_error_text` | `studio_editor.media_controls.title`, `studio_editor.media_controls.add_media_action`, `studio_editor.media_controls.remove_media_action`, `studio_editor.media_controls.processing_status`, `studio_editor.media_controls.ready_status`, `studio_editor.media_controls.failed_error` |
| Lesson media preview | `backend_status_text`, `backend_error_text` | `studio_editor.lesson_media_preview.loading_status`, `studio_editor.lesson_media_preview.empty_status`, `studio_editor.lesson_media_preview.unavailable_status`, `studio_editor.lesson_media_preview.failed_error` |
| Profile media | `contract_text`, `backend_status_text`, `backend_error_text` | `studio_editor.profile_media.title`, `studio_editor.profile_media.upload_action`, `studio_editor.profile_media.replace_action`, `studio_editor.profile_media.processing_status`, `studio_editor.profile_media.ready_status`, `studio_editor.profile_media.failed_error` |
| Cover upload | `contract_text`, `backend_status_text`, `backend_error_text` | `studio_editor.cover_upload.title`, `studio_editor.cover_upload.choose_action`, `studio_editor.cover_upload.change_action`, `studio_editor.cover_upload.remove_action`, `studio_editor.cover_upload.uploading_status`, `studio_editor.cover_upload.failed_error` |
| Audio upload and replacement | `contract_text`, `backend_status_text`, `backend_error_text` | `studio_editor.audio_upload.title`, `studio_editor.audio_upload.choose_action`, `studio_editor.audio_upload.uploading_status`, `studio_editor.audio_upload.processing_status`, `studio_editor.audio_upload.failed_error`, `studio_editor.audio_replace.title`, `studio_editor.audio_replace.confirm_action`, `studio_editor.audio_replace.cancel_action` |
| Home-player upload | `contract_text`, `backend_status_text`, `backend_error_text` | `home.player_upload.title`, `home.player_upload.audio_label`, `home.player_upload.submit_action`, `home.player_upload.uploading_status`, `home.player_upload.processing_status`, `home.player_upload.ready_status`, `home.player_upload.failed_error` |
| Studio route and authority failures | `backend_error_text`, `backend_status_text` | `studio_editor.error.course_not_found`, `studio_editor.error.lesson_not_found`, `studio_editor.error.teacher_required`, `studio_editor.error.owner_required`, `studio_editor.error.save_conflict`, `studio_editor.status.reloading` |

Concrete DB-owned fields:

- `app.courses.title`
- `app.lessons.lesson_title`
- `app.lesson_contents.content_markdown`
- `app.home_player_uploads.title`
- `app.home_player_course_links.title`

### Admin And Media System

Surface IDs:

`TXT-SURF-081`, `TXT-SURF-082`, `TXT-SURF-083`, `TXT-SURF-084`,
`TXT-SURF-085`, `TXT-SURF-086`, `TXT-SURF-087`, `TXT-SURF-088`,
`TXT-SURF-089`, `TXT-SURF-090`, `TXT-SURF-091`, `TXT-SURF-092`,
`TXT-SURF-093`, `TXT-SURF-094`, `TXT-SURF-125`, `TXT-SURF-126`,
`TXT-SURF-133`, `TXT-SURF-134`, `TXT-SURF-135`, `TXT-SURF-136`,
`TXT-SURF-137`, `TXT-SURF-138`, `TXT-SURF-140`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| Admin teacher role UI | `contract_text`, `backend_status_text`, `backend_error_text` | `admin.teacher_role.title`, `admin.teacher_role.user_id_label`, `admin.teacher_role.grant_action`, `admin.teacher_role.revoke_action`, `admin.teacher_role.granting_status`, `admin.teacher_role.revoking_status`, `admin.teacher_role.granted_status`, `admin.teacher_role.revoked_status`, `admin.teacher_role.failed_error` |
| Admin settings UI | `contract_text`, `backend_status_text` | `admin.settings.title`, `admin.settings.bootstrap_heading`, `admin.settings.bootstrap_status`, `admin.settings.reload_action`, `admin.settings.saved_status` |
| Admin route and permission failures | `backend_error_text` | `admin.error.admin_required`, `admin.error.forbidden`, `admin.error.user_not_found`, `admin.error.already_teacher`, `admin.error.already_learner`, `admin.error.internal_error` |
| Media control plane product-visible UI | `contract_text`, `backend_status_text`, `backend_error_text` | `media_system.control_plane.title`, `media_system.control_plane.summary_heading`, `media_system.control_plane.refresh_action`, `media_system.control_plane.loading_status`, `media_system.control_plane.load_failed_error` |
| Media player and preview UI | `contract_text`, `backend_status_text`, `backend_error_text` | `media_system.video.loading_status`, `media_system.video.unavailable_status`, `media_system.video.failed_error`, `media_system.audio.loading_status`, `media_system.audio.unavailable_status`, `media_system.audio.failed_error`, `media_system.preview.loading_status`, `media_system.preview.empty_status`, `media_system.preview.failed_error` |
| Network image and media repository failures | `backend_error_text` | `media_system.error.image_load_failed`, `media_system.error.media_not_found`, `media_system.error.media_unavailable`, `media_system.error.legacy_media_unavailable`, `media_system.error.storage_access_forbidden` |
| Media upload and API route failures | `backend_error_text`, `backend_status_text` | `media_system.upload.loading_status`, `media_system.upload.uploading_status`, `media_system.upload.processing_status`, `media_system.upload.ready_status`, `media_system.upload.failed_error`, `media_system.api.error.invalid_media`, `media_system.api.error.upload_failed`, `media_system.api.error.resolve_failed` |
| Product-visible media resolver failure | `backend_error_text` | `media_system.error.resolve_failed`, `media_system.error.runtime_media_missing`, `media_system.error.media_processing_failed` |

Concrete non-user-facing identifiers:

- `identifier.media.media_asset_error_message`
- `identifier.media.media_resolution_failure_reason`
- `identifier.media.control_plane_diagnostic_code`
- `identifier.observability.payment_event_type`
- `identifier.observability.billing_log_event`
- `identifier.observability.media_event_type`
- `identifier.observability.auth_event_type`
- `identifier.mcp.logs_tool_name`
- `identifier.mcp.verification_tool_name`
- `identifier.mcp.media_control_plane_tool_name`
- `identifier.mcp.stripe_observability_tool_name`
- `identifier.mcp.supabase_observability_tool_name`
- `identifier.mcp.netlify_observability_tool_name`

### MVP, Shared Widgets, And Global System

Surface IDs:

`TXT-SURF-099`, `TXT-SURF-101`, `TXT-SURF-103`, `TXT-SURF-104`,
`TXT-SURF-105`, `TXT-SURF-106`, `TXT-SURF-107`, `TXT-SURF-108`,
`TXT-SURF-109`, `TXT-SURF-110`, `TXT-SURF-111`, `TXT-SURF-112`,
`TXT-SURF-113`, `TXT-SURF-117`, `TXT-SURF-118`

Concrete catalog text IDs:

| Surface | Authority class | Concrete IDs |
|---|---|---|
| MVP shell | `contract_text` | `mvp_shared.shell.home_label`, `mvp_shared.shell.profile_label`, `mvp_shared.shell.studio_label`, `mvp_shared.shell.logout_action` |
| MVP login and profile | `contract_text`, `backend_error_text`, `db_user_content` | `mvp_shared.auth.login_title`, `mvp_shared.auth.register_action`, `mvp_shared.auth.login_action`, `mvp_shared.profile.title`, `mvp_shared.profile.save_action`, `mvp_shared.profile.save_failed_error` |
| MVP home | `contract_text`, `backend_error_text`, `db_domain_content` | `mvp_shared.home.title`, `mvp_shared.home.courses_heading`, `mvp_shared.home.feed_heading`, `mvp_shared.home.services_heading`, `mvp_shared.home.load_failed_error` |
| Not-found page | `contract_text` | `global_system.not_found.title`, `global_system.not_found.body`, `global_system.not_found.home_action` |
| Auth boot and global status | `backend_status_text`, `backend_error_text` | `global_system.auth_boot.loading_status`, `global_system.auth_boot.failed_error`, `global_system.snackbar.generic_success`, `global_system.snackbar.generic_failure` |
| Error handling replacements | `backend_error_text` | `global_system.error.internal`, `global_system.error.unavailable`, `global_system.error.network_unavailable`, `global_system.error.unauthenticated`, `global_system.error.forbidden` |
| Shared navigation chrome | `contract_text` | `global_system.navigation.home_label`, `global_system.navigation.back_label`, `global_system.navigation.teacher_label`, `global_system.navigation.profile_label` |
| Brand and generic actions | `contract_text`, `backend_status_text` | `global_system.brand.name`, `global_system.action.ok`, `global_system.action.cancel`, `global_system.action.retry`, `global_system.action.close` |

Concrete DB-owned fields:

- `app.courses.title`
- `app.course_public_content.short_description`
- `app.profiles.display_name`
- `app.profiles.bio`

## 5. Legal Isolation

No `landing_legal` catalog value may be populated by TXT-003 until an active
contract defines exact legal/product copy ownership.

Blocked legal and landing surfaces:

| Surface IDs | Blocked target | Reason |
|---|---|---|
| `TXT-SURF-037`, `TXT-SURF-041`, `TXT-SURF-045`, `TXT-SURF-122` | `blocked.landing_legal.landing.copy_ownership_missing` | Landing product copy contains unresolved exact-copy authority and current implementation includes technical leakage. |
| `TXT-SURF-038`, `TXT-SURF-042`, `TXT-SURF-046` | `blocked.landing_legal.privacy.copy_ownership_missing` | Privacy page/body copy lacks active exact legal contract ownership. |
| `TXT-SURF-039`, `TXT-SURF-043`, `TXT-SURF-047` | `blocked.landing_legal.terms.copy_ownership_missing` | Terms page/body copy lacks active exact legal contract ownership. |
| `TXT-SURF-040`, `TXT-SURF-044` | `blocked.landing_legal.gdpr.copy_ownership_missing` | GDPR page/body copy lacks active exact legal contract ownership. |
| `TXT-SURF-048` | `blocked.landing_legal.footer.labels_ownership_missing` | Legal navigation labels lack active exact contract ownership and must not be guessed. |

Legal label separation:

- `blocked.landing_legal.footer.terms_label_ownership_missing`
- `blocked.landing_legal.footer.privacy_label_ownership_missing`
- `blocked.landing_legal.footer.data_deletion_label_ownership_missing`

Dynamic landing data remains DB-owned where already classified:

- `app.courses.title`
- `app.course_public_content.short_description`
- `app.profiles.display_name`
- `app.profiles.bio`

## 6. Future-Facing And Other Explicit Blocks

These surfaces remain blocked and must not receive catalog values in TXT-003:

| Surface IDs | Blocked target | Reason |
|---|---|---|
| `TXT-SURF-095` | `blocked.future.messages.list_contract_missing` | Future-facing messages surface lacks active product text contract. |
| `TXT-SURF-096` | `blocked.future.messages.chat_contract_missing` | Future-facing chat surface lacks active product text contract. |
| `TXT-SURF-129` | `blocked.future.notifications.contract_missing` | Notification text lacks active product text contract. |
| `TXT-SURF-130` | `blocked.future.events.contract_missing` | Events text lacks active product text contract. |
| `TXT-SURF-131` | `blocked.future.seminars.contract_missing` | Seminar text lacks active product text contract. |
| `TXT-SURF-132` | `blocked.future.session_slots.contract_missing` | Session-slot text lacks active product text contract. |
| `TXT-SURF-076`, `TXT-SURF-077` | `blocked.future.studio_sessions.text_contract_missing` | Studio session/calendar product text and DB-rendered session fields require an active studio-session text contract before value population. |
| `TXT-SURF-105` | `blocked.global_system.english_locale_fallback_forbidden` | English fallback locale is forbidden and is not a valid catalog target. |
| `TXT-SURF-106`, `TXT-SURF-107` | `blocked.global_system.frontend_error_authority_forbidden` | Frontend error fallback maps and raw exception rendering are invalid authority; TXT-003 may populate replacement backend IDs but must not preserve frontend authority. |

## 7. TXT-003 Entry Conditions

TXT-003 may run for non-legal canonical Swedish value population when:

- it uses this artifact as the concrete target registry,
- it populates only IDs under eligible domains listed in Section 4,
- it does not populate any `blocked.` target,
- it preserves DB-owned fields as DB-owned,
- it preserves non-user-facing identifiers as non-rendered identifiers,
- every populated value is Swedish-only,
- no populated value contains mojibake, ASCII-degraded Swedish, English
  fallback, or technical/internal leakage,
- operator prompts remain copy-paste-ready English.

Eligible TXT-003 domains:

- `auth`
- `onboarding`
- `profile`
- `checkout`
- `payments`
- `home`
- `community`
- `course_lesson`
- `studio_editor`
- `admin`
- `media_system`
- `email`
- `mvp_shared`
- `global_system`

Blocked TXT-003 domains:

- `landing_legal`
- `future_blocked`

Partially blocked TXT-003 surfaces:

- studio sessions under `studio_editor`
- English locale fallback under `global_system`
- frontend error authority rows under `global_system`

## 8. Final Assertions

- All eligible non-legal mapped user-facing surfaces now terminate in concrete
  catalog text IDs, DB-owned fields, non-user-facing identifiers, or explicit
  blocked states.
- Unresolved legal ownership is explicitly blocked and not guessed.
- Future-facing domains remain explicitly blocked.
- User-facing product text remains Swedish-only by policy.
- Operator prompts remain English and copy-paste-ready.
- No runtime compliance is claimed by this planning artifact.
