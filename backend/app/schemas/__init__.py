from datetime import datetime
from enum import Enum
from typing import Any, List, Literal, Optional

from pydantic import (
    AliasChoices,
    BaseModel,
    ConfigDict,
    Field,
    SerializerFunctionWrapHandler,
    field_validator,
    model_validator,
    model_serializer,
)
from uuid import UUID

from .billing import (
    SubscriptionCheckoutResponse as SubscriptionCheckoutResponse,
    SubscriptionInterval as SubscriptionInterval,
    SubscriptionSessionRequest as SubscriptionSessionRequest,
)
from .checkout import (
    CheckoutCreateRequest as CheckoutCreateRequest,
    CheckoutCreateResponse as CheckoutCreateResponse,
    CheckoutType as CheckoutType,
)
from .memberships import (
    MembershipRecord as MembershipRecord,
    MembershipResponse as MembershipResponse,
)
from .referrals import (
    ReferralCodeCreateRequest as ReferralCodeCreateRequest,
    ReferralCodeCreateResponse as ReferralCodeCreateResponse,
    ReferralCodeRecord as ReferralCodeRecord,
    ReferralRedeemRequest as ReferralRedeemRequest,
    ReferralRedeemResponse as ReferralRedeemResponse,
)

__all__ = [
    "CheckoutCreateRequest",
    "CheckoutCreateResponse",
    "CheckoutType",
    "MembershipRecord",
    "MembershipResponse",
    "ReferralCodeCreateRequest",
    "ReferralCodeCreateResponse",
    "ReferralCodeRecord",
    "ReferralRedeemRequest",
    "ReferralRedeemResponse",
    "SubscriptionCheckoutResponse",
    "SubscriptionInterval",
    "SubscriptionSessionRequest",
]

class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    refresh_token: str


class TokenPayload(BaseModel):
    sub: UUID


class AuthLoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str
    password: str


class AuthRegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str
    password: str


class AuthForgotPasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str


class AuthResetPasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str
    new_password: str


class TokenRefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    refresh_token: str


class Profile(BaseModel):
    user_id: UUID
    email: str
    display_name: str | None = None
    bio: str | None = None
    photo_url: str | None = None
    avatar_media_id: UUID | None = None
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
    model_config = ConfigDict(extra="forbid")

    title: str
    description: Optional[str] = None
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    capacity: Optional[int] = Field(default=None, ge=0)
    price_cents: int = Field(ge=0)
    currency: str = Field(min_length=3, max_length=3)
    visibility: SessionVisibility
    recording_url: Optional[str] = None
    stripe_price_id: Optional[str] = None

    @field_validator("currency")
    @classmethod
    def _validate_currency(cls, value: str) -> str:
        if value.strip() != value or value.lower() != value:
            raise ValueError("currency must be a lowercase 3-letter code")
        return value


class SessionCreateRequest(SessionBase):
    pass


class SessionUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

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

    @field_validator("currency")
    @classmethod
    def _validate_currency(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if value.strip() != value or value.lower() != value:
            raise ValueError("currency must be a lowercase 3-letter code")
        return value


class SessionResponse(SessionBase):
    id: UUID
    teacher_id: UUID
    created_at: datetime
    updated_at: datetime


class SessionListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: List[SessionResponse]


class SessionSlotBase(BaseModel):
    model_config = ConfigDict(extra="forbid")

    start_at: datetime
    end_at: datetime
    seats_total: int = Field(ge=0)


class SessionSlotCreateRequest(SessionSlotBase):
    pass


class SessionSlotUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

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
    model_config = ConfigDict(extra="forbid")

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


class ProfileMediaVisibility(str, Enum):
    draft = "draft"
    published = "published"


class TeacherProfileMediaItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    subject_user_id: UUID
    media_asset_id: UUID
    visibility: ProfileMediaVisibility
    media: Optional["ResolvedMedia"] = None


class TeacherProfileMediaCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    visibility: ProfileMediaVisibility


class TeacherProfileMediaUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: Optional[UUID] = None
    visibility: Optional[ProfileMediaVisibility] = None


class TeacherProfileMediaListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: List[TeacherProfileMediaItem]


class TeacherProfileMediaPublicResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: List[TeacherProfileMediaItem]


class HomePlayerUploadItem(BaseModel):
    id: UUID
    teacher_id: UUID
    media_asset_id: UUID
    title: str
    kind: Literal["audio"]
    active: bool
    created_at: datetime
    updated_at: datetime
    content_type: Optional[str] = None
    byte_size: Optional[int] = None
    original_name: Optional[str] = None
    media_state: Optional[Literal["uploaded", "processing", "ready", "failed"]] = None


class HomePlayerUploadCreate(BaseModel):
    title: str
    active: bool = True
    media_asset_id: UUID


class HomePlayerCourseLinkStatus(str, Enum):
    active = "active"
    source_missing = "source_missing"
    course_unpublished = "course_unpublished"


class HomePlayerCourseLinkItem(BaseModel):
    id: UUID
    teacher_id: UUID
    lesson_media_id: Optional[UUID] = None
    title: str
    course_title: str
    enabled: bool
    status: HomePlayerCourseLinkStatus
    kind: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class HomePlayerUploadUpdate(BaseModel):
    title: Optional[str] = None
    active: Optional[bool] = None


class HomePlayerCourseLinkCreate(BaseModel):
    lesson_media_id: UUID
    title: str
    enabled: bool = True


class HomePlayerCourseLinkUpdate(BaseModel):
    enabled: Optional[bool] = None
    title: Optional[str] = None


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


class ResolvedMedia(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_id: UUID
    state: str
    resolved_url: str | None = None


class CourseCoverMedia(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_id: UUID
    state: Literal["ready"]
    resolved_url: str = Field(min_length=1)

    @field_validator("resolved_url")
    @classmethod
    def _validate_resolved_url(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("course cover resolved_url must be nonblank")
        return value


class HomeAudioItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_type: Literal["course_link", "direct_upload"]
    title: str
    lesson_title: Optional[str] = None
    course_id: Optional[UUID] = None
    course_title: Optional[str] = None
    course_slug: Optional[str] = None
    teacher_id: UUID
    teacher_name: Optional[str] = None
    created_at: datetime
    media: ResolvedMedia


class HomeAudioFeedResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

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
    course_id: Optional[UUID] = None
    bundle_id: Optional[UUID] = None
    amount_cents: Optional[int] = None
    currency: Optional[str] = None
    metadata: Optional[dict[str, Any]] = None


class OrderRecord(BaseModel):
    id: UUID
    user_id: UUID
    course_id: Optional[UUID] = None
    bundle_id: Optional[UUID] = None
    order_type: str = "one_off"
    amount_cents: int
    currency: str
    status: str
    stripe_checkout_id: Optional[str] = None
    stripe_payment_intent: Optional[str] = None
    stripe_subscription_id: Optional[str] = None
    stripe_customer_id: Optional[str] = None
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
    model_config = ConfigDict(extra="forbid")

    id: UUID
    slug: str
    title: str
    course_group_id: UUID
    group_position: int
    cover_media_id: UUID | None = None
    cover: CourseCoverMedia | None = None
    price_amount_cents: int | None = None
    drip_enabled: bool
    drip_interval_days: Optional[int]


class CoursePricingResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    amount_cents: int
    currency: str = Field(min_length=3, max_length=3)

    @field_validator("currency")
    @classmethod
    def _validate_currency(cls, value: str) -> str:
        if value.strip() != value or value.lower() != value:
            raise ValueError("currency must be a lowercase 3-letter code")
        return value


class LandingCourseCard(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    slug: str
    title: str
    group_position: int
    cover_media_id: UUID | None = None
    cover: CourseCoverMedia | None = None
    price_amount_cents: int | None = None
    short_description: str | None = None


class LandingCourseSectionResponse(BaseModel):
    items: List[LandingCourseCard]


class LandingTeacherCard(BaseModel):
    user_id: UUID
    display_name: str
    photo_url: str | None = None
    bio: str | None = None


class LandingTeacherSectionResponse(BaseModel):
    items: List[LandingTeacherCard]


class LandingServiceCard(BaseModel):
    id: UUID
    title: str
    description: str | None = None
    certified_area: str | None = None
    price_cents: int | None = None


class LandingServiceSectionResponse(BaseModel):
    items: List[LandingServiceCard]


class LessonStructureItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    lesson_title: str
    position: int


class CourseDetailResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course: Course
    lessons: List[LessonStructureItem]
    short_description: str | None = None


class LessonContentItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    course_id: UUID
    lesson_title: str
    position: int
    content_markdown: str | None = None


class LearnerLessonMediaItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    lesson_id: UUID
    media_asset_id: UUID | None = None
    position: int
    media_type: Literal["audio", "image", "video", "document"]
    state: Literal["pending_upload", "uploaded", "processing", "ready", "failed"]
    media: ResolvedMedia | None = None


class LessonContentResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson: LessonContentItem
    course_id: UUID
    lessons: List[LessonStructureItem]
    media: List[LearnerLessonMediaItem]


class CourseListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: List[Course]


class CoursePublicContent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_id: UUID
    short_description: str


class CourseEnrollmentRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    user_id: UUID
    course_id: UUID
    source: str
    granted_at: datetime
    drip_started_at: datetime
    current_unlock_position: int


class CourseAccessStateResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_id: UUID
    group_position: int
    required_enrollment_source: str | None = None
    enrollment: CourseEnrollmentRecord | None = None


class StudioCoursePublicContentUpsert(BaseModel):
    model_config = ConfigDict(extra="forbid")

    short_description: str


class MediaUploadUrlRequest(BaseModel):
    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)
    media_type: Literal["audio", "image", "video", "document"]
    course_id: UUID | None = None
    lesson_id: UUID | None = None
    purpose: Literal["lesson_audio", "home_player_audio", "lesson_media"] | None = None


class MediaUploadUrlRefreshRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    media_asset_id: UUID = Field(
        validation_alias=AliasChoices("media_asset_id", "media_id")
    )


class MediaUploadCompleteRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    media_asset_id: UUID = Field(
        validation_alias=AliasChoices("media_asset_id", "media_id")
    )


class MediaAttachRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    media_asset_id: UUID = Field(
        validation_alias=AliasChoices("media_asset_id", "media_id")
    )
    lesson_id: UUID | None = None
    link_scope: Literal["lesson", "home_upload"]
    lesson_media_id: UUID | None = None


class MediaUploadUrlResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    media_asset_id: UUID = Field(
        validation_alias=AliasChoices("media_asset_id", "media_id")
    )
    media_id: UUID | None = None
    upload_url: str
    storage_path: str = Field(
        validation_alias=AliasChoices("storage_path", "object_path")
    )
    object_path: str | None = None
    headers: dict[str, str]
    expires_at: datetime


class MediaStatusResponse(BaseModel):
    media_id: UUID
    state: Literal["pending_upload", "uploaded", "processing", "ready", "failed"]
    error_message: str | None = None
    ingest_format: str | None = None
    streaming_format: str | None = None
    duration_seconds: int | None = None
    codec: str | None = None
    lesson_media_id: UUID | None = None
    lesson_media: dict[str, Any] | None = None


class MediaCompleteResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    media_asset_id: UUID = Field(
        validation_alias=AliasChoices("media_asset_id", "media_id")
    )
    media_id: UUID | None = None
    state: Literal["pending_upload", "uploaded", "processing", "ready", "failed"]
    error_message: str | None = None
    ingest_format: str | None = None
    streaming_format: str | None = None
    duration_seconds: int | None = None
    codec: str | None = None


class MediaAttachResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    media_asset_id: UUID = Field(
        validation_alias=AliasChoices("media_asset_id", "media_id")
    )
    media_id: UUID | None = None
    state: Literal["pending_upload", "uploaded", "processing", "ready", "failed"]
    error_message: str | None = None
    ingest_format: str | None = None
    streaming_format: str | None = None
    duration_seconds: int | None = None
    codec: str | None = None
    lesson_media_id: UUID | None = None
    runtime_media_id: UUID | None = None
    lesson_media: dict[str, Any] | None = None


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
    media_type: Literal["image", "audio", "video", "document", "pdf"] | None = None


class LessonMediaUploadCompleteRequest(BaseModel):
    storage_path: str
    storage_bucket: str
    content_type: str
    byte_size: int
    original_name: str | None = None
    checksum: str | None = None


class MediaPreviewBatchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ids: list[UUID]


class MediaPreviewItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_type: str
    authoritative_editor_ready: bool = False
    resolved_preview_url: str | None = None
    duration_seconds: int | None = None
    file_name: str | None = None
    failure_reason: str | None = None


class MediaPreviewBatchResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: dict[str, MediaPreviewItem]


class QuizSubmission(BaseModel):
    answers: dict


class StudioCourseCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str
    slug: str
    course_group_id: UUID
    group_position: int = Field(ge=0)
    cover_media_id: UUID | None = None
    price_amount_cents: int | None = None
    drip_enabled: bool
    drip_interval_days: Optional[int]

    @model_validator(mode="after")
    def _validate_drip_configuration(self):
        if self.drip_enabled and self.drip_interval_days is None:
            raise ValueError("drip_interval_days is required when drip_enabled is true")
        if not self.drip_enabled and self.drip_interval_days is not None:
            raise ValueError(
                "drip_interval_days must be null when drip_enabled is false"
            )
        return self


class StudioCourseUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str | None = None
    slug: str | None = None
    course_group_id: UUID | None = None
    group_position: int | None = Field(default=None, ge=0)
    cover_media_id: UUID | None = None
    price_amount_cents: int | None = None
    drip_enabled: bool | None = None
    drip_interval_days: int | None = None


class StudioModuleCreate(BaseModel):
    id: UUID | None = None
    course_id: str
    title: str
    position: int = 0


class StudioModuleUpdate(BaseModel):
    title: str | None = None
    position: int | None = None


class StudioLessonCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID | None = None
    course_id: UUID
    lesson_title: str
    content_markdown: str
    position: int


class StudioLessonUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_title: str | None = None
    content_markdown: str | None = None
    position: int | None = None


class StudioLesson(BaseModel):
    id: UUID
    course_id: UUID
    lesson_title: str
    position: int


class StudioLessonListResponse(BaseModel):
    items: List[StudioLesson]


class StudioLessonStructureCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_title: str
    position: int


class StudioLessonStructureUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_title: str | None = None
    position: int | None = None


class StudioLessonStructure(BaseModel):
    id: UUID
    course_id: UUID
    lesson_title: str
    position: int


class StudioLessonContentUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    content_markdown: str


class StudioLessonContentMediaItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_media_id: UUID
    media_asset_id: UUID | None = None
    position: int
    media_type: Literal["audio", "image", "video", "document"]
    state: Literal["pending_upload", "uploaded", "processing", "ready", "failed"]


class StudioLessonContentRead(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_id: UUID
    content_markdown: str
    media: List[StudioLessonContentMediaItem] = Field(default_factory=list)


class StudioLessonContent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_id: UUID
    content_markdown: str


class StudioLessonMediaUploadUrlRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)
    media_type: Literal["audio", "image", "video", "document"]


class StudioLessonMediaUploadUrlResponse(BaseModel):
    lesson_media_id: UUID
    lesson_id: UUID
    media_type: Literal["audio", "image", "video", "document"]
    state: Literal["pending_upload"]
    position: int
    upload_url: str
    headers: dict[str, str]
    expires_at: datetime


class StudioLessonMediaCompleteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


class StudioLessonMediaItem(BaseModel):
    lesson_media_id: UUID
    lesson_id: UUID
    media_asset_id: UUID | None = None
    position: int
    media_type: Literal["audio", "image", "video", "document"]
    state: Literal["pending_upload", "uploaded", "processing", "ready", "failed"]
    media: ResolvedMedia | None = None
    preview_ready: bool
    original_name: str | None = None


class StudioLessonMediaListResponse(BaseModel):
    items: List[StudioLessonMediaItem]


class StudioLessonMediaPreviewResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_media_id: UUID
    preview_url: str
    expires_at: datetime


class StudioLessonMediaReorder(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_media_ids: List[UUID]


class CanonicalLessonMediaUploadUrlRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_type: Literal["audio", "image", "video", "document"]
    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)


class CanonicalLessonMediaUploadUrlResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    asset_state: Literal["pending_upload"]
    upload_session_id: UUID
    upload_endpoint: str
    expires_at: datetime


class CanonicalCourseCoverUploadUrlRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)


class CanonicalCourseCoverUploadUrlResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    asset_state: Literal["pending_upload"]
    upload_session_id: UUID
    upload_endpoint: str
    expires_at: datetime


class CanonicalHomePlayerMediaUploadUrlRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)


class CanonicalHomePlayerMediaUploadUrlResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    asset_state: Literal["pending_upload"]
    upload_session_id: UUID
    upload_endpoint: str
    expires_at: datetime


class CanonicalProfileAvatarInitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    filename: str
    mime_type: str
    size_bytes: int = Field(ge=1)


class CanonicalProfileAvatarInitResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    asset_state: Literal["pending_upload"]
    upload_session_id: UUID
    upload_endpoint: str
    expires_at: datetime


class CanonicalProfileAvatarAttachRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID


class CanonicalMediaAssetUploadBytesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    uploaded: Literal[True]


class CanonicalMediaAssetUploadCompletionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CanonicalMediaAssetUploadCompletionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    asset_state: Literal["uploaded"]


class CanonicalMediaAssetStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID
    asset_state: Literal["pending_upload", "uploaded", "processing", "ready", "failed"]


class CanonicalLessonMediaPlacementCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_asset_id: UUID


class CanonicalLessonMediaPlacementResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_media_id: UUID
    lesson_id: UUID
    media_asset_id: UUID
    position: int
    media_type: Literal["audio", "image", "video", "document"]
    asset_state: Literal["uploaded", "processing", "ready"]


class CanonicalMediaPlacementReadResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lesson_media_id: UUID
    lesson_id: UUID
    media_asset_id: UUID
    position: int
    media_type: Literal["audio", "image", "video", "document"]
    asset_state: Literal["uploaded", "processing", "ready", "failed"]
    media: ResolvedMedia | None


class MediaReorder(BaseModel):
    media_ids: List[str]


class LessonReorderItem(BaseModel):
    id: str
    position: int


class LessonReorder(BaseModel):
    lessons: List[LessonReorderItem]


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
    model_config = ConfigDict(extra="forbid")

    display_name: Optional[str] = None
    bio: Optional[str] = None


class OnboardingCreateProfileRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str
    bio: Optional[str] = None

    @field_validator("display_name")
    @classmethod
    def validate_display_name(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("display_name_required")
        return normalized

    @field_validator("bio")
    @classmethod
    def normalize_bio(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip()


class StudioCertificateCreate(BaseModel):
    title: str
    status: str = "pending"
    notes: Optional[str] = None
    evidence_url: Optional[str] = None


class PurchaseClaimRequest(BaseModel):
    token: UUID


class PurchaseClaimResponse(BaseModel):
    ok: bool


class OnboardingStateResponse(BaseModel):
    onboarding_state: str


class OnboardingCompletionResponse(BaseModel):
    status: Literal["completed"]
    onboarding_state: Literal["completed"]
    token_refresh_required: Literal[True]


class EntryStateResponse(BaseModel):
    can_enter_app: bool
    onboarding_state: str
    onboarding_completed: bool
    membership_active: bool
    needs_onboarding: bool
    needs_payment: bool
    role: str


class EntitlementsMembership(BaseModel):
    is_active: bool
    status: Optional[str] = None


class EntitlementsResponse(BaseModel):
    membership: Optional[EntitlementsMembership] = None
    courses: List[str]
