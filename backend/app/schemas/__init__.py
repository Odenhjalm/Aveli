from datetime import datetime
from enum import Enum
from typing import Any, List, Literal, Optional

from pydantic import BaseModel, Field
from uuid import UUID

from .billing import (
    SubscriptionCheckoutResponse,
    SubscriptionInterval,
    SubscriptionSessionRequest,
)
from .checkout import CheckoutCreateRequest, CheckoutCreateResponse, CheckoutType
from .memberships import MembershipRecord, MembershipResponse


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    refresh_token: str


class TokenPayload(BaseModel):
    sub: UUID


class AuthLoginRequest(BaseModel):
    email: str
    password: str


class AuthRegisterRequest(BaseModel):
    email: str
    password: str
    display_name: str


class AuthForgotPasswordRequest(BaseModel):
    email: str


class AuthResetPasswordRequest(BaseModel):
    email: str
    new_password: str


class TokenRefreshRequest(BaseModel):
    refresh_token: str


class Profile(BaseModel):
    user_id: UUID
    email: str
    display_name: str | None = None
    bio: str | None = None
    photo_url: str | None = None
    avatar_media_id: UUID | None = None
    role_v2: str
    is_admin: bool
    created_at: datetime
    updated_at: datetime


class SimpleProfile(BaseModel):
    user_id: UUID
    display_name: Optional[str] = None
    photo_url: Optional[str] = None
    bio: Optional[str] = None


class SessionVisibility(str, Enum):
    draft = "draft"
    published = "published"


class SessionBase(BaseModel):
    title: str
    description: Optional[str] = None
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    capacity: Optional[int] = Field(default=None, ge=0)
    price_cents: int = Field(default=0, ge=0)
    currency: str = Field(default="sek", min_length=3, max_length=3)
    visibility: SessionVisibility = SessionVisibility.draft
    recording_url: Optional[str] = None
    stripe_price_id: Optional[str] = None


class SessionCreateRequest(SessionBase):
    pass


class SessionUpdateRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    capacity: Optional[int] = Field(default=None, ge=0)
    price_cents: Optional[int] = Field(default=None, ge=0)
    currency: Optional[str] = Field(default=None, min_length=3, max_length=3)
    visibility: Optional[SessionVisibility] = None
    recording_url: Optional[str] = None
    stripe_price_id: Optional[str] = None


class SessionResponse(SessionBase):
    id: UUID
    teacher_id: UUID
    created_at: datetime
    updated_at: datetime


class SessionListResponse(BaseModel):
    items: List[SessionResponse]


class SessionSlotBase(BaseModel):
    start_at: datetime
    end_at: datetime
    seats_total: int = Field(default=1, ge=0)


class SessionSlotCreateRequest(SessionSlotBase):
    pass


class SessionSlotUpdateRequest(BaseModel):
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    seats_total: Optional[int] = Field(default=None, ge=0)
    seats_taken: Optional[int] = Field(default=None, ge=0)


class SessionSlotResponse(SessionSlotBase):
    id: UUID
    session_id: UUID
    seats_taken: int
    created_at: datetime
    updated_at: datetime


class SessionSlotListResponse(BaseModel):
    items: List[SessionSlotResponse]


class CommunityPost(BaseModel):
    id: UUID
    author_id: UUID
    content: str
    media_paths: List[str] = []
    created_at: datetime
    profile: Optional[SimpleProfile] = None


class CommunityPostCreate(BaseModel):
    content: str
    media_paths: Optional[List[str]] = None


class CommunityPostListResponse(BaseModel):
    items: List[CommunityPost]


class TeacherDirectoryItem(BaseModel):
    user_id: UUID
    headline: Optional[str] = None
    specialties: List[str] = []
    rating: Optional[float] = None
    created_at: datetime
    profile: Optional[SimpleProfile] = None
    verified_certificates: int = 0


class TeacherDirectoryResponse(BaseModel):
    items: List[TeacherDirectoryItem]


class SeminarStatus(str, Enum):
    draft = "draft"
    scheduled = "scheduled"
    live = "live"
    ended = "ended"
    canceled = "canceled"


class SeminarSessionStatus(str, Enum):
    scheduled = "scheduled"
    live = "live"
    ended = "ended"
    canceled = "canceled"


class SeminarBase(BaseModel):
    title: str
    description: Optional[str] = None
    scheduled_at: Optional[datetime] = None
    duration_minutes: Optional[int] = Field(default=None, ge=0)


class SeminarCreateRequest(SeminarBase):
    pass


class SeminarUpdateRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    scheduled_at: Optional[datetime] = None
    duration_minutes: Optional[int] = Field(default=None, ge=0)


class SeminarResponse(SeminarBase):
    id: UUID
    host_id: UUID
    host_display_name: Optional[str] = None
    status: SeminarStatus
    livekit_room: Optional[str] = None
    livekit_metadata: dict[str, Any] | None = None
    created_at: datetime
    updated_at: datetime


class SeminarListResponse(BaseModel):
    items: List[SeminarResponse]


class SeminarSessionResponse(BaseModel):
    id: UUID
    seminar_id: UUID
    status: SeminarSessionStatus
    scheduled_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    livekit_room: Optional[str] = None
    livekit_sid: Optional[str] = None
    metadata: dict[str, Any] = {}
    created_at: datetime
    updated_at: datetime


class SeminarSessionStartRequest(BaseModel):
    session_id: Optional[UUID] = None
    max_participants: Optional[int] = Field(default=None, ge=0)
    metadata: Optional[dict[str, Any]] = None


class SeminarSessionEndRequest(BaseModel):
    reason: Optional[str] = None


class SeminarSessionStartResponse(BaseModel):
    session: SeminarSessionResponse
    ws_url: str
    token: str


class SeminarRecordingReserveRequest(BaseModel):
    session_id: Optional[UUID] = None
    extension: Optional[str] = "mp4"


class SeminarAttendeeGrantRequest(BaseModel):
    user_id: UUID
    role: str = "participant"
    invite_status: str = "accepted"


class SeminarRegistrationResponse(BaseModel):
    seminar_id: UUID
    user_id: UUID
    role: str
    invite_status: str
    joined_at: Optional[datetime] = None
    left_at: Optional[datetime] = None
    livekit_identity: Optional[str] = None
    livekit_participant_sid: Optional[str] = None
    created_at: datetime
    profile_display_name: Optional[str] = None
    profile_email: Optional[str] = None
    host_course_titles: List[str] = Field(default_factory=list)


class SeminarRecordingResponse(BaseModel):
    id: UUID
    seminar_id: UUID
    session_id: Optional[UUID] = None
    asset_url: str
    status: str
    duration_seconds: Optional[int] = None
    byte_size: Optional[int] = None
    published: bool
    metadata: dict[str, Any] = {}
    created_at: datetime
    updated_at: datetime


class TeacherProfileMediaKind(str, Enum):
    lesson_media = "lesson_media"
    seminar_recording = "seminar_recording"
    external = "external"


class TeacherProfileLessonSource(BaseModel):
    id: UUID
    lesson_id: UUID
    lesson_title: Optional[str] = None
    course_id: Optional[UUID] = None
    course_title: Optional[str] = None
    course_slug: Optional[str] = None
    kind: str
    storage_path: Optional[str] = None
    storage_bucket: Optional[str] = None
    content_type: Optional[str] = None
    duration_seconds: Optional[int] = None
    position: Optional[int] = None
    created_at: Optional[datetime] = None
    download_url: Optional[str] = None
    signed_url: Optional[str] = None
    signed_url_expires_at: Optional[str] = None


class TeacherProfileRecordingSource(BaseModel):
    id: UUID
    seminar_id: UUID
    seminar_title: Optional[str] = None
    session_id: Optional[UUID] = None
    asset_url: str
    status: str
    duration_seconds: Optional[int] = None
    byte_size: Optional[int] = None
    published: bool
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class TeacherProfileMediaBase(BaseModel):
    media_kind: TeacherProfileMediaKind
    media_id: Optional[UUID] = None
    external_url: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    cover_media_id: Optional[UUID] = None
    cover_image_url: Optional[str] = None
    position: int = 0
    is_published: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class TeacherProfileMediaSource(BaseModel):
    lesson_media: Optional[TeacherProfileLessonSource] = None
    seminar_recording: Optional[TeacherProfileRecordingSource] = None


class TeacherProfileMediaItem(TeacherProfileMediaBase):
    id: UUID
    teacher_id: UUID
    created_at: datetime
    updated_at: datetime
    source: TeacherProfileMediaSource = Field(default_factory=TeacherProfileMediaSource)


class TeacherProfileMediaCreate(BaseModel):
    media_kind: TeacherProfileMediaKind
    media_id: Optional[UUID] = None
    external_url: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    cover_media_id: Optional[UUID] = None
    cover_image_url: Optional[str] = None
    position: Optional[int] = None
    is_published: Optional[bool] = None
    metadata: Optional[dict[str, Any]] = None


class TeacherProfileMediaUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    cover_media_id: Optional[UUID] = None
    cover_image_url: Optional[str] = None
    position: Optional[int] = None
    is_published: Optional[bool] = None
    metadata: Optional[dict[str, Any]] = None


class TeacherProfileMediaListResponse(BaseModel):
    items: List[TeacherProfileMediaItem]
    lesson_media: List[TeacherProfileLessonSource] = Field(default_factory=list)
    seminar_recordings: List[TeacherProfileRecordingSource] = Field(default_factory=list)


class TeacherProfileMediaPublicResponse(BaseModel):
    items: List[TeacherProfileMediaItem]


class SeminarDetailResponse(BaseModel):
    seminar: SeminarResponse
    sessions: List[SeminarSessionResponse] = []
    attendees: List[SeminarRegistrationResponse] = []
    recordings: List[SeminarRecordingResponse] = []


class ServiceSummary(BaseModel):
    id: UUID
    title: str
    description: Optional[str] = None
    price_cents: Optional[int] = None
    duration_min: Optional[int] = None
    certified_area: Optional[str] = None
    active: Optional[bool] = None
    created_at: datetime


class MeditationSummary(BaseModel):
    id: UUID
    teacher_id: UUID
    title: str
    description: Optional[str] = None
    audio_path: str
    duration_seconds: Optional[int] = None
    is_public: bool | None = None
    created_at: datetime
    audio_url: Optional[str] = None


class TeacherDetailResponse(BaseModel):
    teacher: Optional[TeacherDirectoryItem] = None
    services: List[ServiceSummary] = []
    meditations: List[MeditationSummary] = []
    certificates: List[dict[str, Any]] = []


class ReviewRecord(BaseModel):
    id: UUID
    service_id: UUID
    reviewer_id: UUID
    rating: int
    comment: Optional[str] = None
    created_at: datetime


class ReviewListResponse(BaseModel):
    items: List[ReviewRecord]


class ReviewCreate(BaseModel):
    rating: int
    comment: Optional[str] = None


class MeditationListResponse(BaseModel):
    items: List[MeditationSummary]


class HomeAudioItem(BaseModel):
    id: UUID
    lesson_id: UUID
    lesson_title: str
    course_id: UUID
    course_title: str
    course_slug: Optional[str] = None
    kind: str
    storage_path: str
    storage_bucket: Optional[str] = None
    media_id: Optional[UUID] = None
    duration_seconds: Optional[int] = None
    created_at: datetime
    content_type: Optional[str] = None
    byte_size: Optional[int] = None
    original_name: Optional[str] = None
    download_url: Optional[str] = None
    signed_url: Optional[str] = None
    signed_url_expires_at: Optional[str] = None
    is_intro: Optional[bool] = None
    is_free_intro: Optional[bool] = None


class HomeAudioFeedResponse(BaseModel):
    items: List[HomeAudioItem]


class MessageRecord(BaseModel):
    id: UUID
    channel: str
    sender_id: UUID
    content: str
    created_at: datetime


class MessageListResponse(BaseModel):
    items: List[MessageRecord]


class MessageCreate(BaseModel):
    channel: str
    content: str


class ServiceDetailResponse(BaseModel):
    service: Optional[dict[str, Any]] = None
    provider: Optional[dict[str, Any]] = None


class TarotRequestRecord(BaseModel):
    id: UUID
    requester_id: UUID
    reader_id: Optional[UUID] = None
    question: str
    status: str
    deliverable_url: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class TarotRequestListResponse(BaseModel):
    items: List[TarotRequestRecord]


class TarotRequestCreate(BaseModel):
    question: str


class TeacherApplication(BaseModel):
    id: UUID
    user_id: UUID
    title: str
    status: str
    notes: Optional[str] = None
    evidence_url: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    display_name: Optional[str] = None
    email: Optional[str] = None
    role_v2: Optional[str] = None
    approval: Optional[dict[str, Any]] = None


class TeacherApplicationListResponse(BaseModel):
    items: List[TeacherApplication]


class TeacherPriorityUpdate(BaseModel):
    priority: int = Field(gt=0, le=1000)
    notes: Optional[str] = None


class TeacherPriorityRecord(BaseModel):
    teacher_id: UUID
    display_name: Optional[str] = None
    email: Optional[str] = None
    photo_url: Optional[str] = None
    priority: int
    notes: Optional[str] = None
    updated_at: Optional[datetime] = None
    updated_by: Optional[UUID] = None
    updated_by_name: Optional[str] = None
    total_courses: int = 0
    published_courses: int = 0


class AdminMetrics(BaseModel):
    total_users: int = 0
    total_teachers: int = 0
    total_courses: int = 0
    published_courses: int = 0
    paid_orders_total: int = 0
    paid_orders_30d: int = 0
    paying_customers_total: int = 0
    paying_customers_30d: int = 0
    revenue_total_cents: int = 0
    revenue_30d_cents: int = 0
    login_events_7d: int = 0
    active_users_7d: int = 0


class AdminSettingsResponse(BaseModel):
    metrics: AdminMetrics
    priorities: List[TeacherPriorityRecord]


# ---------------------------------------------------------------------------
# V2 API schemas (Aveli by SoulAveli)
# ---------------------------------------------------------------------------


class MeResponse(BaseModel):
    user_id: UUID
    email: str
    display_name: Optional[str] = None
    role: str
    is_admin: bool


class ServiceItem(BaseModel):
    id: UUID
    title: str
    description: Optional[str] = None
    price_cents: int
    currency: str
    status: str
    duration_minutes: Optional[int] = None
    requires_certification: bool
    certified_area: Optional[str] = None
    thumbnail_url: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class ServiceListResponse(BaseModel):
    items: List[ServiceItem]


class OrderCreateRequest(BaseModel):
    service_id: Optional[UUID] = None
    course_id: Optional[UUID] = None
    amount_cents: Optional[int] = None
    currency: Optional[str] = None
    metadata: Optional[dict[str, Any]] = None


class OrderRecord(BaseModel):
    id: UUID
    user_id: UUID
    service_id: Optional[UUID] = None
    course_id: Optional[UUID] = None
    session_id: Optional[UUID] = None
    session_slot_id: Optional[UUID] = None
    order_type: str = "one_off"
    amount_cents: int
    currency: str
    status: str
    stripe_checkout_id: Optional[str] = None
    stripe_payment_intent: Optional[str] = None
    stripe_subscription_id: Optional[str] = None
    stripe_customer_id: Optional[str] = None
    connected_account_id: Optional[str] = None
    metadata: dict[str, Any] = {}
    created_at: datetime
    updated_at: datetime


class OrderResponse(BaseModel):
    order: OrderRecord


class OrderListResponse(BaseModel):
    items: List[OrderRecord]


class CheckoutSessionRequest(BaseModel):
    order_id: UUID
    success_url: str
    cancel_url: str
    customer_email: Optional[str] = None


class CheckoutSessionResponse(BaseModel):
    url: str
    id: str


class SessionCheckoutRequest(BaseModel):
    session_id: Optional[UUID] = None
    session_slot_id: Optional[UUID] = None
    success_url: Optional[str] = None
    cancel_url: Optional[str] = None
    payment_mode: str = Field(default="payment")
    order_type: Optional[str] = None


class SessionCheckoutResponse(BaseModel):
    order_id: UUID
    client_secret: str
    payment_intent_id: Optional[str] = None


class ConnectOnboardingRequest(BaseModel):
    refresh_url: Optional[str] = None
    return_url: Optional[str] = None


class ConnectOnboardingResponse(BaseModel):
    account_id: str
    onboarding_url: str


class ConnectStatusResponse(BaseModel):
    account_id: Optional[str] = None
    status: str
    charges_enabled: bool = False
    payouts_enabled: bool = False
    requirements_due: dict[str, Any] = {}
    onboarded_at: Optional[datetime] = None


class StripeWebhookEvent(BaseModel):
    type: str
    data: dict[str, Any]


class FeedItem(BaseModel):
    id: UUID
    activity_type: str
    actor_id: Optional[UUID] = None
    subject_table: Optional[str] = None
    subject_id: Optional[UUID] = None
    summary: Optional[str] = None
    metadata: dict[str, Any] = {}
    occurred_at: datetime


class FeedResponse(BaseModel):
    items: List[FeedItem]


class LiveKitTokenRequest(BaseModel):
    seminar_id: UUID
    session_id: Optional[UUID] = None


class LiveKitTokenResponse(BaseModel):
    ws_url: str
    token: str


class CertificateRecord(BaseModel):
    id: UUID
    user_id: UUID
    title: str
    status: str
    notes: Optional[str] = None
    evidence_url: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class AdminDashboard(BaseModel):
    is_admin: bool
    requests: List[TeacherApplication]
    certificates: List[CertificateRecord]


class CertificateStatusUpdate(BaseModel):
    status: str


class NotificationRecord(BaseModel):
    id: UUID
    kind: str
    payload: dict[str, Any]
    is_read: bool
    created_at: datetime


class NotificationListResponse(BaseModel):
    items: List[NotificationRecord]


class NotificationUpdate(BaseModel):
    is_read: bool


class ProfileDetail(BaseModel):
    profile: dict[str, Any]
    is_following: bool
    services: List[dict[str, Any]]
    meditations: List[dict[str, Any]]


class ProfileDetailResponse(ProfileDetail):
    pass


class Course(BaseModel):
    id: UUID
    slug: str
    title: str
    description: str | None = None
    cover_url: str | None = None
    cover_media_id: UUID | None = None
    video_url: str | None = None
    is_free_intro: bool
    price_amount_cents: int = 0
    currency: str = "sek"
    stripe_product_id: str | None = None
    stripe_price_id: str | None = None
    is_published: bool
    created_by: UUID | None
    created_at: datetime
    updated_at: datetime


class CourseListResponse(BaseModel):
    items: List[Course]


class MediaSignRequest(BaseModel):
    media_id: str


class MediaSignResponse(BaseModel):
    media_id: str
    signed_url: str
    expires_at: datetime


class MediaUploadUrlRequest(BaseModel):
    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)
    media_type: Literal["audio"]
    course_id: UUID | None = None
    lesson_id: UUID | None = None


class MediaUploadUrlResponse(BaseModel):
    media_id: UUID
    upload_url: str
    object_path: str
    expires_at: datetime


class CoverUploadUrlRequest(BaseModel):
    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)
    course_id: UUID


class CoverUploadUrlResponse(BaseModel):
    media_id: UUID
    upload_url: str
    object_path: str
    expires_at: datetime


class CoverFromLessonMediaRequest(BaseModel):
    course_id: UUID
    lesson_media_id: UUID


class CoverMediaResponse(BaseModel):
    media_id: UUID
    state: Literal["uploaded", "processing", "ready", "failed"]


class CoverClearRequest(BaseModel):
    course_id: UUID


class CoverClearResponse(BaseModel):
    ok: bool


class MediaPlaybackUrlRequest(BaseModel):
    media_id: UUID


class MediaPlaybackUrlResponse(BaseModel):
    playback_url: str
    expires_at: datetime
    format: Literal["mp3"]


class MediaStatusResponse(BaseModel):
    media_id: UUID
    state: Literal["uploaded", "processing", "ready", "failed"]
    error_message: str | None = None
    ingest_format: str | None = None
    streaming_format: str | None = None
    duration_seconds: int | None = None
    codec: str | None = None


class MediaPresignRequest(BaseModel):
    intent: Literal["download", "upload"]
    storage_path: str
    filename: str | None = None
    ttl: int | None = None
    content_type: str | None = None
    upsert: bool = False


class MediaPresignResponse(BaseModel):
    url: str
    headers: dict[str, str]
    method: str
    expires_at: datetime
    storage_path: str
    storage_bucket: str | None = None


class LessonMediaPresignRequest(BaseModel):
    filename: str
    content_type: str | None = None
    media_type: Literal["image", "audio", "video", "document"] | None = None
    is_intro: bool | None = None


class LessonMediaUploadCompleteRequest(BaseModel):
    storage_path: str
    storage_bucket: str
    content_type: str
    byte_size: int
    original_name: str | None = None
    checksum: str | None = None
    is_intro: bool | None = None


class QuizSubmission(BaseModel):
    answers: dict


class StudioCourseCreate(BaseModel):
    title: str
    slug: str
    description: str | None = None
    video_url: str | None = None
    is_free_intro: bool = False
    is_published: bool = False
    price_amount_cents: int | None = None
    branch: str | None = None


class StudioCourseUpdate(BaseModel):
    title: str | None = None
    slug: str | None = None
    description: str | None = None
    video_url: str | None = None
    is_free_intro: bool | None = None
    is_published: bool | None = None
    price_amount_cents: int | None = None
    branch: str | None = None


class StudioModuleCreate(BaseModel):
    id: UUID | None = None
    course_id: str
    title: str
    position: int = 0


class StudioModuleUpdate(BaseModel):
    title: str | None = None
    position: int | None = None


class StudioLessonCreate(BaseModel):
    id: UUID | None = None
    module_id: str
    title: str
    content_markdown: str | None = None
    position: int = 0
    is_intro: bool = False


class StudioLessonUpdate(BaseModel):
    title: str | None = None
    content_markdown: str | None = None
    position: int | None = None
    is_intro: bool | None = None


class LessonIntroUpdate(BaseModel):
    is_intro: bool


class MediaReorder(BaseModel):
    media_ids: List[str]


class QuizEnsureResult(BaseModel):
    quiz: dict


class QuizQuestionUpsert(BaseModel):
    id: str | None = None
    position: int | None = None
    kind: str | None = None
    prompt: str | None = None
    options: dict | None = None
    correct: str | None = None


class SubscriptionPlan(BaseModel):
    id: UUID
    name: str
    price_cents: int
    interval: str
    is_active: bool


class SubscriptionPlanListResponse(BaseModel):
    items: List[SubscriptionPlan]


class SubscriptionStatusResponse(BaseModel):
    has_active: bool
    subscription: Optional[dict[str, Any]] = None


class CouponPreviewRequest(BaseModel):
    plan_id: UUID
    code: Optional[str] = None


class CouponPreviewResponse(BaseModel):
    valid: bool
    pay_amount_cents: int


class CouponRedeemRequest(BaseModel):
    plan_id: UUID
    code: str


class CouponRedeemResponse(BaseModel):
    ok: bool
    reason: Optional[str] = None
    subscription: Optional[dict[str, Any]] = None


class OrderCourseCreateRequest(BaseModel):
    course_id: UUID
    amount_cents: int
    currency: Optional[str] = "sek"
    metadata: Optional[dict[str, Any]] = None


class OrderServiceCreateRequest(BaseModel):
    service_id: UUID
    amount_cents: int
    currency: Optional[str] = "sek"
    metadata: Optional[dict[str, Any]] = None


class CreateCheckoutSessionRequest(BaseModel):
    order_id: UUID
    success_url: str
    cancel_url: str
    customer_email: Optional[str] = None


class CreateSubscriptionRequest(BaseModel):
    user_id: UUID
    price_id: str


class CreateSubscriptionResponse(BaseModel):
    subscription_id: str
    client_secret: Optional[str] = None
    status: Optional[str] = None


class CancelSubscriptionRequest(BaseModel):
    subscription_id: str


class ProfileUpdate(BaseModel):
    display_name: Optional[str] = None
    bio: Optional[str] = None
    photo_url: Optional[str] = None


class StudioCertificateCreate(BaseModel):
    title: str
    status: str = "pending"
    notes: Optional[str] = None
    evidence_url: Optional[str] = None


class PurchaseClaimRequest(BaseModel):
    token: UUID


class PurchaseClaimResponse(BaseModel):
    ok: bool


class EntitlementsMembership(BaseModel):
    is_active: bool
    status: Optional[str] = None


class EntitlementsResponse(BaseModel):
    membership: Optional[EntitlementsMembership] = None
    courses: List[str]
