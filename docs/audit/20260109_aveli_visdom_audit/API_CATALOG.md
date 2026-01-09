# API Catalog (Phase 1)

Notes on methodology:
- Routes extracted from `backend/app/routes/*.py` decorators.
- Tables inferred from direct SQL strings and referenced repository/service/model functions; dynamic SQL fragments may under-report tables.
- Errors column lists explicit `HTTPException(status_code=...)` cases only.
- Notes flag missing response models, raw request parsing, and untyped bodies.
- Routers **not mounted** in `backend/app/main.py`: `backend/app/routes/auth.py` and `backend/app/routes/api_payments.py`.

## backend/app/routes/admin.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/admin/dashboard` | admin | - | schemas.AdminDashboard | - | models.list_recent_certificates, models.list_teacher_applications | app.certificates, app.profiles, app.teacher_approvals | - | - |
| GET | `/admin/settings` | admin | - | schemas.AdminSettingsResponse | - | models.fetch_admin_metrics, models.list_teacher_course_priorities | app.auth_events, app.course_display_priorities, app.courses, app.orders, app.payments, app.profiles | - | - |
| GET | `/admin/teacher-requests` | admin | - | schemas.TeacherApplicationListResponse | - | models.list_teacher_applications | app.certificates, app.profiles, app.teacher_approvals | - | - |
| POST | `/admin/teachers/{user_id}/approve` | admin | str | - | status.HTTP_204_NO_CONTENT | models.approve_teacher_user | app.certificates, app.profiles, app.teacher_approvals | - | no response_model |
| POST | `/admin/teacher-requests/{user_id}/approve` | admin | str | - | status.HTTP_204_NO_CONTENT | models.approve_teacher_user | app.certificates, app.profiles, app.teacher_approvals | - | no response_model |
| POST | `/admin/teachers/{user_id}/reject` | admin | str | - | status.HTTP_204_NO_CONTENT | models.reject_teacher_user | app.certificates, app.teacher_approvals | - | no response_model |
| POST | `/admin/teacher-requests/{user_id}/reject` | admin | str | - | status.HTTP_204_NO_CONTENT | models.reject_teacher_user | app.certificates, app.teacher_approvals | - | no response_model |
| PATCH | `/admin/certificates/{certificate_id}` | admin | str, schemas.CertificateStatusUpdate | schemas.CertificateRecord | - | models.set_certificate_status | app.certificates | 404 | - |
| PATCH | `/admin/teachers/{teacher_id}/priority` | admin | str, schemas.TeacherPriorityUpdate | schemas.TeacherPriorityRecord | - | models.get_teacher_course_priority, models.upsert_teacher_course_priority | app.course_display_priorities, app.courses, app.profiles | 404 | - |
| DELETE | `/admin/teachers/{teacher_id}/priority` | admin | str | schemas.TeacherPriorityRecord | - | models.delete_teacher_course_priority, models.get_teacher_course_priority | app.course_display_priorities, app.courses, app.profiles | 404 | - |

## backend/app/routes/api_ai.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/api/ai/execute` | teacher | AIExecuteRequest, Request | AIExecuteResponse | - | - | - | status.HTTP_400_BAD_REQUEST | - |
| POST | `/api/ai/execute-built` | required | Request | AIExecuteBuiltResponse | - | - | - | status.HTTP_400_BAD_REQUEST, status.HTTP_500_INTERNAL_SERVER_ERROR | - |
| POST | `/api/ai/tool-call` | required | Request | AIToolCallResponse | - | - | - | status.HTTP_400_BAD_REQUEST | - |
| POST | `/api/ai/plan-and-execute` | required | Request | AIPlanExecuteResponse | - | - | - | status.HTTP_400_BAD_REQUEST | - |
| POST | `/api/ai/plan-and-execute-v1` | required | Request | AIPlanExecuteV1Response | - | - | - | status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN | - |

## backend/app/routes/api_auth.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/auth/oauth` | public | - | - | - | - | - | status.HTTP_410_GONE | no response_model |
| POST | `/auth/register` | public | schemas.AuthRegisterRequest, Request | schemas.Token | status.HTTP_201_CREATED | models.is_teacher_user, repositories.create_user, repositories.get_profile, repositories.get_user_by_email, repositories.insert_auth_event, repositories.upsert_refresh_token | app.auth_events, app.profiles, app.refresh_tokens, app.teacher_approvals, app.teacher_permissions, auth.users | status.HTTP_409_CONFLICT | - |
| POST | `/auth/login` | public | schemas.AuthLoginRequest, Request | schemas.Token | - | models.is_teacher_user, repositories.get_profile, repositories.get_user_by_email, repositories.insert_auth_event, repositories.upsert_refresh_token | app.auth_events, app.profiles, app.refresh_tokens, app.teacher_approvals, app.teacher_permissions, auth.users | status.HTTP_401_UNAUTHORIZED | - |
| POST | `/auth/refresh` | public | schemas.TokenRefreshRequest, Request | schemas.Token | - | models.is_teacher_user, repositories.get_profile, repositories.get_refresh_token, repositories.insert_auth_event, repositories.revoke_refresh_token, repositories.touch_refresh_token_as_rotated, repositories.upsert_refresh_token | app.auth_events, app.profiles, app.refresh_tokens, app.teacher_approvals, app.teacher_permissions | status.HTTP_400_BAD_REQUEST, status.HTTP_401_UNAUTHORIZED | - |
| GET | `/auth/me` | required | - | schemas.Profile | - | repositories.get_profile | app.profiles | status.HTTP_404_NOT_FOUND | - |
| PATCH | `/auth/me` | required | schemas.ProfileUpdate | schemas.Profile | - | repositories.update_profile | app.profiles | status.HTTP_404_NOT_FOUND | - |
| POST | `/auth/me/avatar` | required | UploadFile | schemas.Profile | - | models.cleanup_media_object, models.create_media_object, models.get_media_object, repositories.get_profile, repositories.update_profile | app.lesson_media, app.media_objects, app.profiles | status.HTTP_400_BAD_REQUEST, status.HTTP_404_NOT_FOUND, status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, status.HTTP_500_INTERNAL_SERVER_ERROR | multipart upload |
| GET | `/auth/avatar/{media_id}` | public | str | - | - | models.get_media_object | app.media_objects | status.HTTP_404_NOT_FOUND | no response_model |

## backend/app/routes/api_checkout.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/api/checkout/create` | required | CheckoutCreateRequest | CheckoutCreateResponse | status.HTTP_201_CREATED | checkout_service.create_course_checkout, universal_checkout_service.create_checkout_session | app.billing_logs, app.memberships, app.orders | exc.status_code, status.HTTP_400_BAD_REQUEST | - |

## backend/app/routes/api_context7.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/api/context7/build` | required | ContextBuildRequest, Request | ContextBuildResponse | - | - | - | status.HTTP_500_INTERNAL_SERVER_ERROR | - |

## backend/app/routes/api_feed.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/feed` | required | int | schemas.FeedResponse | - | repositories.list_feed | app.activities_feed | - | - |

## backend/app/routes/api_me.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/api/me/membership` | required | - | MembershipResponse | - | repositories.get_membership | app.memberships | - | - |
| GET | `/api/me/entitlements` | required | - | schemas.EntitlementsResponse | - | repositories.get_membership, repositories.list_entitlements_for_user | app.course_entitlements, app.memberships | - | - |

## backend/app/routes/api_orders.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/orders` | required | schemas.OrderCreateRequest | schemas.OrderResponse | status.HTTP_201_CREATED | repositories.create_order, repositories.get_service | app.orders, app.services | status.HTTP_400_BAD_REQUEST, status.HTTP_404_NOT_FOUND | - |
| GET | `/orders/{order_id}` | required | str | schemas.OrderResponse | - | repositories.get_user_order | app.orders | status.HTTP_404_NOT_FOUND | - |
| GET | `/orders` | required | str \| None, int | schemas.OrderListResponse | - | repositories.list_user_orders | app.orders | - | - |

## backend/app/routes/api_payments.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/payments/create-checkout-session` | required | CheckoutSessionRequest | CheckoutSessionResponse | status.HTTP_201_CREATED | subscription_service.create_checkout_session | app.billing_logs | exc.status_code | - |

## backend/app/routes/api_profiles.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/profiles/me` | required | - | schemas.Profile | - | repositories.get_profile | app.profiles | status.HTTP_404_NOT_FOUND | - |
| PATCH | `/profiles/me` | required | schemas.ProfileUpdate | schemas.Profile | - | repositories.update_profile | app.profiles | status.HTTP_404_NOT_FOUND | - |
| POST | `/profiles/me/avatar` | required | UploadFile | schemas.Profile | - | models.cleanup_media_object, models.create_media_object, models.get_media_object, repositories.get_profile, repositories.update_profile | app.lesson_media, app.media_objects, app.profiles | status.HTTP_400_BAD_REQUEST, status.HTTP_404_NOT_FOUND, status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, status.HTTP_500_INTERNAL_SERVER_ERROR | multipart upload |
| GET | `/profiles/avatar/{media_id}` | public | str | - | - | models.get_media_object | app.media_objects | status.HTTP_404_NOT_FOUND | no response_model |
| GET | `/profiles/{user_id}/certificates` | required | str, bool | - | - | models.certificates_of | - | status.HTTP_403_FORBIDDEN | no response_model |

## backend/app/routes/api_services.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/services` | public | str \| None | schemas.ServiceListResponse | - | repositories.list_services | app.services | 400 | - |

## backend/app/routes/api_sfu.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/sfu/token` | required | schemas.LiveKitTokenRequest | schemas.LiveKitTokenResponse | - | repositories.get_latest_session, repositories.get_seminar, repositories.get_seminar_session, repositories.get_user_seminar_role | app.profiles, app.seminar_attendees, app.seminar_sessions, app.seminars | status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND, status.HTTP_409_CONFLICT, status.HTTP_503_SERVICE_UNAVAILABLE | - |
| POST | `/sfu/webhooks/livekit` | public | Request | - | - | - | - | exc.status_code, status.HTTP_400_BAD_REQUEST | no response_model |

## backend/app/routes/auth.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/auth/register` | public | schemas.AuthRegisterRequest, Request | schemas.Token | status.HTTP_201_CREATED | models.create_user, models.get_profile_row, models.get_user_by_email, models.get_user_by_id, models.is_teacher_user, models.record_auth_event, models.register_refresh_token | app.auth_events, app.profiles, app.teacher_approvals, app.teacher_permissions | 400, status.HTTP_429_TOO_MANY_REQUESTS | - |
| POST | `/auth/login` | public | schemas.AuthLoginRequest, Request | schemas.Token | - | models.get_profile_row, models.get_user_by_email, models.get_user_by_id, models.is_teacher_user, models.record_auth_event, models.register_refresh_token | app.auth_events, app.profiles, app.teacher_approvals, app.teacher_permissions | 401, status.HTTP_429_TOO_MANY_REQUESTS | - |
| POST | `/auth/forgot-password` | public | schemas.AuthForgotPasswordRequest | - | status.HTTP_202_ACCEPTED | models.get_user_by_email | - | - | no response_model |
| POST | `/auth/reset-password` | public | schemas.AuthResetPasswordRequest | - | - | models.get_user_by_email, models.update_user_password | auth.users | 404 | no response_model |
| POST | `/auth/refresh` | public | schemas.TokenRefreshRequest, Request | schemas.Token | - | models.get_profile_row, models.get_user_by_id, models.is_teacher_user, models.record_auth_event, models.register_refresh_token, models.validate_refresh_token | app.auth_events, app.profiles, app.refresh_tokens, app.teacher_approvals, app.teacher_permissions | 401 | - |

## backend/app/routes/billing.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/api/billing/create-subscription` | required | SubscriptionSessionRequest | SubscriptionCheckoutResponse | status.HTTP_201_CREATED | subscription_service.create_subscription_checkout | app.billing_logs, app.memberships | exc.status_code | - |
| POST | `/api/billing/customer-portal` | required | - | BillingPortalResponse | status.HTTP_201_CREATED | billing_portal_service.create_billing_portal_session | app.billing_logs, app.memberships | exc.status_code | - |
| POST | `/api/billing/create-checkout-session` | required | CheckoutSessionRequest | CheckoutSessionResponse | status.HTTP_201_CREATED | subscription_service.create_checkout_session | app.billing_logs | exc.status_code | - |
| GET | `/api/billing/session-status` | public | str | SessionStatusResponse | - | subscription_service.fetch_session_status | app.memberships | exc.status_code | - |
| POST | `/api/billing/cancel-subscription` | required | SubscriptionCancelRequest | SubscriptionCancelResponse | - | subscription_service.cancel_subscription | app.billing_logs, app.memberships | exc.status_code | - |

## backend/app/routes/community.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/community/posts` | public | int | schemas.CommunityPostListResponse | - | models.list_community_posts | app.posts, app.profiles | - | - |
| POST | `/community/posts` | required | schemas.CommunityPostCreate | schemas.CommunityPost | status.HTTP_201_CREATED | models.create_community_post | app.posts, app.profiles | 422 | - |
| GET | `/community/teachers` | public | int | schemas.TeacherDirectoryResponse | - | models.list_teacher_directory | app.certificates, app.profiles, app.teacher_directory | - | - |
| GET | `/community/teachers/{user_id}` | optional,required | str | schemas.TeacherDetailResponse | - | models.certificates_of, models.get_teacher_directory_item, models.list_teacher_meditations, models.list_teacher_services | app.certificates, app.meditations, app.profiles, app.services, app.teacher_directory | - | - |
| GET | `/community/teachers/{user_id}/media` | public | str | schemas.TeacherProfileMediaPublicResponse | - | repositories.list_public_teacher_profile_media | app.courses, app.lesson_media, app.lessons, app.media_objects, app.modules, app.seminar_recordings, app.seminars, app.teacher_profile_media | - | - |
| GET | `/community/teachers/{user_id}/services` | public | str | List[schemas.ServiceSummary] | - | models.list_teacher_services | app.services | - | - |
| GET | `/community/services/{service_id}` | public | str | schemas.ServiceDetailResponse | - | models.service_detail | app.profiles, app.services | 404 | - |
| GET | `/community/teachers/{user_id}/meditations` | public | str | List[schemas.MeditationSummary] | - | models.list_teacher_meditations | app.meditations | - | - |
| GET | `/community/teachers/{user_id}/certificates` | required | str | - | - | models.certificates_of | - | status.HTTP_403_FORBIDDEN | no response_model |
| GET | `/community/profiles/{user_id}` | required | str | schemas.ProfileDetailResponse | - | models.profile_overview | - | 404, status.HTTP_403_FORBIDDEN | - |
| GET | `/community/meditations/public` | public | int | schemas.MeditationListResponse | - | models.list_public_meditations | app.meditations | - | - |
| GET | `/community/meditations/audio` | public | str | - | - | - | - | - | no response_model |
| POST | `/community/follows/{user_id}` | required | str | - | status.HTTP_204_NO_CONTENT | models.follow_user | app.follows | 400 | no response_model |
| DELETE | `/community/follows/{user_id}` | required | str | - | status.HTTP_204_NO_CONTENT | models.unfollow_user | app.follows | - | no response_model |
| GET | `/community/certificates/verified-count` | public | list[str] | - | - | models.verified_certificate_counts | app.certificates | - | no response_model |
| GET | `/community/tarot/requests` | required | - | schemas.TarotRequestListResponse | - | models.list_tarot_requests_for_user | app.tarot_requests | - | - |
| POST | `/community/tarot/requests` | required | schemas.TarotRequestCreate | schemas.TarotRequestRecord | status.HTTP_201_CREATED | models.create_tarot_request | app.tarot_requests | 400 | - |
| GET | `/community/notifications` | required | bool | schemas.NotificationListResponse | - | models.list_notifications_for_user | app.notifications | - | - |
| PATCH | `/community/notifications/{notification_id}` | required | str, schemas.NotificationUpdate | schemas.NotificationRecord | - | models.mark_notification_read | app.notifications | 404 | - |
| GET | `/community/services/{service_id}/reviews` | public | str | schemas.ReviewListResponse | - | models.list_reviews_for_service | app.reviews | - | - |
| POST | `/community/services/{service_id}/reviews` | required | str, schemas.ReviewCreate | schemas.ReviewRecord | status.HTTP_201_CREATED | models.add_review_for_service | app.reviews | 422 | - |
| GET | `/community/messages` | required | str | schemas.MessageListResponse | - | models.list_channel_messages | app.messages | status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN | - |
| POST | `/community/messages` | required | schemas.MessageCreate | schemas.MessageRecord | status.HTTP_201_CREATED | models.create_channel_message | app.messages | 422, status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN | - |

## backend/app/routes/connect.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/connect/onboarding` | teacher | schemas.ConnectOnboardingRequest | schemas.ConnectOnboardingResponse | status.HTTP_201_CREATED | connect_service.create_onboarding_link | app.profiles, app.teachers | - | - |
| GET | `/connect/status` | teacher | - | schemas.ConnectStatusResponse | - | connect_service.get_connect_status | app.teachers | - | - |

## backend/app/routes/course_bundles.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/api/course-bundles/{bundle_id}` | public | str | CourseBundleResponse | - | course_bundles_service.get_bundle | - | status.HTTP_404_NOT_FOUND | - |
| POST | `/api/teachers/course-bundles` | teacher | CourseBundleCreateRequest | CourseBundleResponse | status.HTTP_201_CREATED | course_bundles_service.create_bundle | app.course_bundles | exc.status_code | - |
| GET | `/api/teachers/course-bundles` | teacher | - | CourseBundleListResponse | - | course_bundles_service.list_teacher_bundles | app.course_bundles | exc.status_code | - |
| POST | `/api/teachers/course-bundles/{bundle_id}/courses` | teacher | str, CourseBundleCourseRequest | CourseBundleResponse | - | course_bundles_service.attach_course | app.course_bundles | exc.status_code | - |
| POST | `/api/course-bundles/{bundle_id}/checkout-session` | required | str | CheckoutCreateResponse | status.HTTP_201_CREATED | course_bundles_service.create_checkout_session | app.orders | exc.status_code | - |

## backend/app/routes/courses.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/courses` | public | bool, bool \| None, str \| None, int \| None | schemas.CourseListResponse | - | courses_service.list_public_courses | app.courses | - | - |
| GET | `/courses/{slug}/pricing` | public | str | - | - | courses_repo.get_course_by_slug | - | 404 | no response_model |
| GET | `/api/courses/{slug}/pricing` | public | str | - | - | courses_repo.get_course_by_slug | - | - | no response_model |
| POST | `/courses/{slug}/bind-price` | admin | str, dict[str, str] | - | - | courses_repo.get_course_by_slug, courses_repo.update_course_stripe_ids | app.courses | 404, status.HTTP_400_BAD_REQUEST | no response_model; untyped body (dict) |
| GET | `/courses/{course_id}/modules` | public | str | - | - | courses_service.list_modules | app.modules | - | no response_model |
| GET | `/courses/modules/{module_id}/lessons` | public | str | - | - | courses_service.list_lessons | app.lessons | - | no response_model |
| GET | `/courses/lessons/{lesson_id}` | public | str | - | - | courses_service.fetch_lesson, courses_service.fetch_module, courses_service.list_course_lessons, courses_service.list_lesson_media, courses_service.list_lessons, courses_service.list_modules | app.lesson_media, app.lessons, app.media_objects, app.modules | 404 | no response_model |
| GET | `/courses/me` | required | - | schemas.CourseListResponse | - | courses_service.list_my_courses | app.courses, app.enrollments | - | - |
| GET | `/courses/{course_id}/enrollment` | required | str | - | - | courses_service.is_user_enrolled | app.enrollments | - | no response_model |
| POST | `/courses/{course_id}/enroll` | required | str | - | - | courses_service.enroll_free_intro | app.app_config, app.courses, app.enrollments, app.profiles, app.subscriptions | status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND | no response_model |
| GET | `/courses/{course_id}/latest-order` | required | str | - | - | courses_service.latest_order_for_course | app.orders | - | no response_model |
| GET | `/courses/free-consumed` | required | - | - | - | courses_service.free_consumed_count, courses_service.get_free_course_limit | app.app_config, app.courses, app.enrollments | - | no response_model |
| GET | `/courses/config/free-limit` | public | - | - | - | courses_service.get_free_course_limit | app.app_config | - | no response_model |
| GET | `/config/free-course-limit` | public | - | - | - | courses_service.get_free_course_limit | app.app_config | - | no response_model |
| GET | `/courses/intro-first` | public | - | - | - | courses_service.list_public_courses | app.courses | - | no response_model |
| GET | `/courses/{course_id}/access` | required | str | - | - | courses_service.course_access_snapshot | app.app_config, app.profiles, app.subscriptions | - | no response_model |
| GET | `/courses/{course_id}/quiz` | required | str | - | - | courses_service.course_quiz_info | app.certificates, app.course_quizzes | - | no response_model |
| GET | `/courses/quiz/{quiz_id}/questions` | public | str | - | - | courses_service.quiz_questions | app.quiz_questions | - | no response_model |
| POST | `/courses/quiz/{quiz_id}/submit` | required | str, schemas.QuizSubmission | - | - | courses_service.submit_quiz | app.grade_quiz_and_issue_certificate | - | no response_model |
| GET | `/courses/by-slug/{slug}` | public | str | - | - | courses_service.fetch_course, courses_service.list_lessons, courses_service.list_modules | app.courses, app.lessons, app.modules | 404 | no response_model |
| GET | `/courses/{course_id}` | public | str | - | - | courses_service.fetch_course, courses_service.list_lessons, courses_service.list_modules | app.courses, app.lessons, app.modules | 404 | no response_model |

## backend/app/routes/landing.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/landing/intro-courses` | public | - | - | - | models.list_intro_courses | - | - | no response_model |
| GET | `/landing/popular-courses` | public | - | - | - | models.list_popular_courses | app.course_display_priorities, app.courses | - | no response_model |
| GET | `/landing/teachers` | public | - | - | - | models.list_teachers | app.profiles | - | no response_model |
| GET | `/landing/services` | public | - | - | - | models.list_services | - | - | no response_model |

## backend/app/routes/livekit_webhooks.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/webhooks/livekit` | public | Request | - | status.HTTP_200_OK | - | - | exc.status_code, status.HTTP_400_BAD_REQUEST | no response_model |

## backend/app/routes/media.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/media/sign` | required | schemas.MediaSignRequest | schemas.MediaSignResponse | - | models.get_media | app.lesson_media, app.media_objects | 404, 503 | - |
| GET | `/media/stream/{token}` | public | str, Request | - | - | models.get_media, models.get_media_object | app.lesson_media, app.media_objects | 400, 401, 404, 503 | no response_model |

## backend/app/routes/profiles.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/profiles/me` | required | - | schemas.Profile | - | models.get_profile | - | - | - |
| PATCH | `/profiles/me` | required | schemas.ProfileUpdate | schemas.Profile | - | models.get_profile, models.update_profile | - | status.HTTP_404_NOT_FOUND | - |
| POST | `/profiles/me/avatar` | required | UploadFile | schemas.Profile | - | models.cleanup_media_object, models.create_media_object, models.get_media_object, models.get_profile, models.update_profile | app.lesson_media, app.media_objects, app.profiles | status.HTTP_400_BAD_REQUEST, status.HTTP_404_NOT_FOUND, status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, status.HTTP_500_INTERNAL_SERVER_ERROR | multipart upload |
| GET | `/profiles/avatar/{media_id}` | public | str | - | - | models.get_media_object | app.media_objects | status.HTTP_404_NOT_FOUND | no response_model |
| GET | `/profiles/{user_id}/certificates` | required | str, bool | - | - | models.certificates_of | - | status.HTTP_403_FORBIDDEN | no response_model |

## backend/app/routes/seminars.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/seminars` | public | int | schemas.SeminarListResponse | - | repositories.list_public_seminars | app.profiles, app.seminars | - | - |
| GET | `/seminars/{seminar_id}` | public | UUID | schemas.SeminarDetailResponse | - | repositories.get_seminar, repositories.list_seminar_attendees, repositories.list_seminar_recordings, repositories.list_seminar_sessions | app.courses, app.enrollments, app.profiles, app.seminar_attendees, app.seminar_recordings, app.seminar_sessions, app.seminars | status.HTTP_404_NOT_FOUND | - |
| POST | `/seminars/{seminar_id}/register` | required | UUID | schemas.SeminarRegistrationResponse | status.HTTP_201_CREATED | repositories.get_seminar, repositories.register_attendee, repositories.user_has_seminar_access | app.orders, app.profiles, app.seminar_attendees, app.seminars | status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND, status.HTTP_409_CONFLICT | - |
| DELETE | `/seminars/{seminar_id}/register` | required | UUID | - | status.HTTP_204_NO_CONTENT | repositories.unregister_attendee | app.seminar_attendees | status.HTTP_404_NOT_FOUND | no response_model |

## backend/app/routes/session_slots.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/sessions` | public | datetime \| None, int | schemas.SessionListResponse | - | booking_service.list_public_sessions | app.sessions | - | - |
| GET | `/sessions/{session_id}` | public | UUID | schemas.SessionResponse | - | booking_service.get_session | app.sessions | status.HTTP_404_NOT_FOUND | - |
| GET | `/sessions/{session_id}/slots` | public | UUID | schemas.SessionSlotListResponse | - | booking_service.get_session, booking_service.list_slots_for_session | app.session_slots, app.sessions | status.HTTP_404_NOT_FOUND | - |

## backend/app/routes/stripe_webhook.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/api/billing/webhook` | public | Request | - | status.HTTP_200_OK | subscription_service.handle_webhook | - | exc.status_code | no response_model |

## backend/app/routes/stripe_webhooks.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/webhooks/stripe` | public | Request | - | status.HTTP_200_OK | checkout_service.handle_payment_intent_succeeded, course_bundles_service.grant_bundle_entitlements, courses_repo.ensure_course_enrollment, courses_repo.get_course_by_slug, repositories.create_order, repositories.get_order, repositories.get_teacher_by_account, repositories.mark_order_paid, repositories.record_payment, repositories.update_teacher_status, subscription_service.process_event | app.billing_logs, app.enrollments, app.orders, app.payment_events, app.payments, app.teachers | status.HTTP_400_BAD_REQUEST, status.HTTP_500_INTERNAL_SERVER_ERROR, status.HTTP_503_SERVICE_UNAVAILABLE | no response_model |

## backend/app/routes/studio.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/studio/courses` | teacher | - | - | - | models.teacher_courses | app.courses | - | no response_model |
| GET | `/studio/status` | required | - | - | - | models.teacher_status | - | - | no response_model |
| GET | `/studio/certificates` | required | bool | - | - | models.user_certificates | app.certificates | - | no response_model |
| POST | `/studio/certificates` | required | schemas.StudioCertificateCreate | - | - | models.add_certificate | app.certificates | - | no response_model |
| POST | `/studio/courses` | teacher | schemas.StudioCourseCreate | - | - | models.create_course_for_user | - | 400 | no response_model |
| POST | `/studio/lessons/{lesson_id}/media/presign` | teacher | UUID, schemas.LessonMediaPresignRequest | - | - | models.get_lesson | - | 404 | no response_model |
| POST | `/studio/lessons/{lesson_id}/media/complete` | teacher | UUID, schemas.LessonMediaUploadCompleteRequest | - | - | models.add_lesson_media_entry, models.get_lesson | app.lesson_media, app.media_objects | 400, 404 | no response_model |
| GET | `/studio/lessons/{lesson_id}/media` | teacher | UUID | - | - | models.list_lesson_media | - | - | no response_model |
| GET | `/studio/profile/media` | teacher | - | schemas.TeacherProfileMediaListResponse | - | repositories.list_teacher_lesson_media_sources, repositories.list_teacher_profile_media, repositories.list_teacher_seminar_recording_sources | app.courses, app.lesson_media, app.lessons, app.media_objects, app.modules, app.seminar_recordings, app.seminars, app.teacher_profile_media | - | - |
| POST | `/studio/profile/media` | teacher | schemas.TeacherProfileMediaCreate | schemas.TeacherProfileMediaItem | 201 | repositories.create_teacher_profile_media | app.teacher_profile_media | 400, 422 | - |
| PATCH | `/studio/profile/media/{item_id}` | teacher | UUID, schemas.TeacherProfileMediaUpdate | schemas.TeacherProfileMediaItem | - | repositories.update_teacher_profile_media | app.teacher_profile_media | 404 | - |
| DELETE | `/studio/profile/media/{item_id}` | teacher | UUID | - | 204 | repositories.delete_teacher_profile_media | app.teacher_profile_media | 404 | no response_model |
| GET | `/studio/seminars` | teacher | - | schemas.SeminarListResponse | - | repositories.list_host_seminars | app.profiles, app.seminars | - | - |
| POST | `/studio/seminars` | teacher | schemas.SeminarCreateRequest | schemas.SeminarResponse | - | repositories.create_seminar | app.seminars | - | - |
| GET | `/studio/seminars/{seminar_id}` | teacher | UUID | schemas.SeminarDetailResponse | - | repositories.get_seminar, repositories.list_seminar_attendees, repositories.list_seminar_recordings, repositories.list_seminar_sessions | app.courses, app.enrollments, app.profiles, app.seminar_attendees, app.seminar_recordings, app.seminar_sessions, app.seminars | 404 | - |
| POST | `/studio/seminars/{seminar_id}/attendees` | teacher | UUID, schemas.SeminarAttendeeGrantRequest | schemas.SeminarRegistrationResponse | status.HTTP_201_CREATED | repositories.get_seminar, repositories.register_attendee | app.profiles, app.seminar_attendees, app.seminars | 404 | - |
| DELETE | `/studio/seminars/{seminar_id}/attendees/{user_id}` | teacher | UUID, UUID | - | status.HTTP_204_NO_CONTENT | repositories.get_seminar, repositories.unregister_attendee | app.profiles, app.seminar_attendees, app.seminars | 404 | no response_model |
| PATCH | `/studio/seminars/{seminar_id}` | teacher | UUID, schemas.SeminarUpdateRequest | schemas.SeminarResponse | - | repositories.get_seminar, repositories.update_seminar | app.profiles, app.seminars | 404 | - |
| POST | `/studio/seminars/{seminar_id}/publish` | teacher | UUID | schemas.SeminarResponse | - | repositories.get_seminar, repositories.set_seminar_status | app.profiles, app.seminars | 404, 409, 500 | - |
| POST | `/studio/seminars/{seminar_id}/cancel` | teacher | UUID | schemas.SeminarResponse | - | repositories.get_seminar, repositories.set_seminar_status | app.profiles, app.seminars | 404, 500 | - |
| POST | `/studio/seminars/{seminar_id}/sessions/start` | teacher | UUID, schemas.SeminarSessionStartRequest | schemas.SeminarSessionStartResponse | - | livekit_service.create_room, repositories.create_seminar_session, repositories.get_seminar, repositories.get_seminar_session, repositories.update_seminar, repositories.update_seminar_session | app.profiles, app.seminar_sessions, app.seminars | 404, 409, 503 | - |
| POST | `/studio/seminars/{seminar_id}/sessions/{session_id}/end` | teacher | UUID, UUID, schemas.SeminarSessionEndRequest \| None | schemas.SeminarSessionResponse | - | livekit_service.end_room, repositories.get_seminar, repositories.get_seminar_session, repositories.update_seminar_session | app.profiles, app.seminar_sessions, app.seminars | 404 | - |
| POST | `/studio/seminars/{seminar_id}/recordings/reserve` | teacher | UUID, schemas.SeminarRecordingReserveRequest | schemas.SeminarRecordingResponse | - | repositories.get_latest_session, repositories.get_seminar, repositories.get_seminar_session, repositories.upsert_recording | app.profiles, app.seminar_recordings, app.seminar_sessions, app.seminars | 404 | - |
| GET | `/studio/courses/{course_id}` | teacher | str | - | - | models.get_course, models.is_course_owner | - | 403, 404 | no response_model |
| PATCH | `/studio/courses/{course_id}` | teacher | str, schemas.StudioCourseUpdate | - | - | models.update_course_for_user | - | 403 | no response_model |
| DELETE | `/studio/courses/{course_id}` | teacher | str | - | - | models.delete_course_for_user | - | 403 | no response_model |
| GET | `/studio/courses/{course_id}/modules` | teacher | str | - | - | courses_service.list_lessons, courses_service.list_modules, models.is_course_owner, models.list_lesson_media | app.lessons, app.modules | 403 | no response_model |
| GET | `/studio/modules/{module_id}/lessons` | teacher | str | - | - | courses_service.get_module_course_id, courses_service.list_lessons, models.is_course_owner, models.list_lesson_media | app.lessons, app.modules | 403 | no response_model |
| POST | `/studio/modules` | teacher | schemas.StudioModuleCreate | - | - | courses_service.upsert_module, models.is_course_owner | app.modules | 400, 403 | no response_model |
| PATCH | `/studio/modules/{module_id}` | teacher | str, schemas.StudioModuleUpdate | - | - | courses_service.fetch_module, courses_service.get_module_course_id, courses_service.upsert_module, models.is_course_owner | app.modules | 403, 404 | no response_model |
| DELETE | `/studio/modules/{module_id}` | teacher | str | - | - | courses_service.delete_module, courses_service.get_module_course_id, models.is_course_owner | app.modules | 403, 404 | no response_model |
| POST | `/studio/lessons` | teacher | schemas.StudioLessonCreate | - | - | courses_service.get_module_course_id, courses_service.upsert_lesson, models.is_course_owner | app.lessons, app.modules | 400, 403 | no response_model |
| PATCH | `/studio/lessons/{lesson_id}` | teacher | str, schemas.StudioLessonUpdate | - | - | courses_service.fetch_lesson, courses_service.lesson_course_ids, courses_service.upsert_lesson, models.is_course_owner | app.lessons, app.modules | 400, 403, 404 | no response_model |
| DELETE | `/studio/lessons/{lesson_id}` | teacher | str | - | - | courses_service.delete_lesson, courses_service.lesson_course_ids, models.is_course_owner | app.lessons, app.modules | 403, 404 | no response_model |
| PATCH | `/studio/lessons/{lesson_id}/intro` | teacher | str, schemas.LessonIntroUpdate | - | - | courses_service.lesson_course_ids, models.is_course_owner, models.set_lesson_intro | app.lessons, app.modules | 403, 404 | no response_model |
| GET | `/studio/lessons/{lesson_id}/media` | teacher | str | - | - | courses_service.lesson_course_ids, models.is_course_owner, models.list_lesson_media | app.lessons, app.modules | 403 | no response_model |
| POST | `/studio/lessons/{lesson_id}/media` | teacher | str, UploadFile, bool | - | - | courses_service.fetch_lesson, courses_service.lesson_course_ids, models.is_course_owner | app.lessons, app.modules | 403, 404 | no response_model; multipart upload |
| DELETE | `/studio/media/{media_id}` | teacher | str | - | - | courses_service.lesson_course_ids, models.delete_lesson_media_entry, models.get_media, models.is_course_owner | app.lesson_media, app.lessons, app.media_objects, app.modules | 403, 404 | no response_model |
| PATCH | `/studio/lessons/{lesson_id}/media/reorder` | teacher | str, schemas.MediaReorder | - | - | courses_service.lesson_course_ids, models.is_course_owner, models.reorder_media | app.lesson_media, app.lessons, app.modules | 403 | no response_model |
| GET | `/studio/media/{media_id}` | required | str, Request | - | - | models.get_media | app.lesson_media, app.media_objects | 404, 410 | no response_model |
| POST | `/studio/courses/{course_id}/quiz` | teacher | str | - | - | models.ensure_quiz_for_user, models.is_course_owner | app.course_quizzes | 400, 403 | no response_model |
| GET | `/studio/quizzes/{quiz_id}/questions` | teacher | str | - | - | models.quiz_belongs_to_user, models.quiz_questions | app.course_quizzes, app.courses | 403 | no response_model |
| POST | `/studio/quizzes/{quiz_id}/questions` | teacher | str, schemas.QuizQuestionUpsert | - | - | models.quiz_belongs_to_user, models.upsert_quiz_question | app.course_quizzes, app.courses, app.quiz_questions | 400, 403 | no response_model |
| PUT | `/studio/quizzes/{quiz_id}/questions/{question_id}` | teacher | str, str, schemas.QuizQuestionUpsert | - | - | models.quiz_belongs_to_user, models.upsert_quiz_question | app.course_quizzes, app.courses, app.quiz_questions | 403, 404 | no response_model |
| DELETE | `/studio/quizzes/{quiz_id}/questions/{question_id}` | teacher | str, str | - | - | models.delete_quiz_question, models.quiz_belongs_to_user | app.course_quizzes, app.courses, app.quiz_questions | 403, 404 | no response_model |

## backend/app/routes/studio_sessions.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GET | `/studio/sessions` | teacher | schemas.SessionVisibility \| None | schemas.SessionListResponse | - | booking_service.list_sessions_for_teacher | app.sessions | - | - |
| POST | `/studio/sessions` | teacher | schemas.SessionCreateRequest | schemas.SessionResponse | status.HTTP_201_CREATED | booking_service.create_teacher_session | app.sessions | - | - |
| PUT | `/studio/sessions/{session_id}` | teacher | UUID, schemas.SessionUpdateRequest | schemas.SessionResponse | - | booking_service.update_teacher_session | app.sessions | - | - |
| DELETE | `/studio/sessions/{session_id}` | teacher | UUID | - | status.HTTP_204_NO_CONTENT | booking_service.delete_session | app.sessions | - | no response_model |
| GET | `/studio/sessions/{session_id}/slots` | teacher | UUID | schemas.SessionSlotListResponse | - | booking_service.list_slots_for_session | app.session_slots | - | - |
| POST | `/studio/sessions/{session_id}/slots` | teacher | UUID, schemas.SessionSlotCreateRequest | schemas.SessionSlotResponse | status.HTTP_201_CREATED | booking_service.create_session_slot | app.session_slots | - | - |
| PATCH | `/studio/sessions/{session_id}/slots/{slot_id}` | teacher | UUID, UUID, schemas.SessionSlotUpdateRequest | schemas.SessionSlotResponse | - | booking_service.update_session_slot | app.session_slots | - | - |

## backend/app/routes/upload.py

| Method | Path | Auth | Request | Response | Status | Services/Repos | Tables | Errors | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POST | `/api/upload/profile` | required | Request, Annotated[UploadFile, File(description='Profile image file')] | - | - | - | - | status.HTTP_500_INTERNAL_SERVER_ERROR | no response_model; multipart upload |
| POST | `/api/upload/course-media` | teacher | Request, Annotated[UploadFile, File(description='Media file for course content')], Annotated[str \| None, Form()], Annotated[str \| None, Form()], Annotated[UploadMediaType \| None, Form(alias='type')], Annotated[bool \| None, Form()] | - | - | courses_service.fetch_lesson, courses_service.lesson_course_ids, models.add_lesson_media_entry, models.create_media_object, models.is_course_owner, models.list_lesson_media | app.lesson_media, app.lessons, app.media_objects, app.modules | status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND, status.HTTP_415_UNSUPPORTED_MEDIA_TYPE | no response_model; multipart upload |
| GET | `/api/files/{path:path}` | public | str | - | - | - | - | status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND | no response_model |
### Hidden routes (include_in_schema=False)
- GET `/courses/` (alias for `/courses` list) — `backend/app/routes/courses.py:42`
- GET `/courses/config/free-course-limit` (alias for `/courses/config/free-limit`) — `backend/app/routes/courses.py:192`
