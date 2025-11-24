--
-- PostgreSQL database dump
--

\restrict FyP0dJdUichEecNr8aKks3jcqip7vUEzX7Tyy60HLBFFgaRmTh4te3gZjWrfKtY

-- Dumped from database version 15.14 (Debian 15.14-1.pgdg13+1)
-- Dumped by pg_dump version 17.6 (Ubuntu 17.6-2.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app; Type: SCHEMA; Schema: -; Owner: oden
--

CREATE SCHEMA app;


ALTER SCHEMA app OWNER TO oden;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: oden
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO oden;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: activity_kind; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.activity_kind AS ENUM (
    'profile_updated',
    'course_published',
    'lesson_published',
    'service_created',
    'order_paid',
    'seminar_scheduled'
);


ALTER TYPE app.activity_kind OWNER TO oden;

--
-- Name: enrollment_source; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.enrollment_source AS ENUM (
    'free_intro',
    'purchase',
    'membership',
    'grant'
);


ALTER TYPE app.enrollment_source OWNER TO oden;

--
-- Name: order_status; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.order_status AS ENUM (
    'pending',
    'requires_action',
    'processing',
    'paid',
    'canceled',
    'failed',
    'refunded'
);


ALTER TYPE app.order_status OWNER TO oden;

--
-- Name: payment_status; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.payment_status AS ENUM (
    'pending',
    'processing',
    'paid',
    'failed',
    'refunded'
);


ALTER TYPE app.payment_status OWNER TO oden;

--
-- Name: profile_role; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.profile_role AS ENUM (
    'student',
    'teacher',
    'admin'
);


ALTER TYPE app.profile_role OWNER TO oden;

--
-- Name: review_visibility; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.review_visibility AS ENUM (
    'public',
    'private'
);


ALTER TYPE app.review_visibility OWNER TO oden;

--
-- Name: seminar_status; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.seminar_status AS ENUM (
    'draft',
    'scheduled',
    'live',
    'ended',
    'canceled'
);


ALTER TYPE app.seminar_status OWNER TO oden;

--
-- Name: service_status; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.service_status AS ENUM (
    'draft',
    'active',
    'paused',
    'archived'
);


ALTER TYPE app.service_status OWNER TO oden;

--
-- Name: user_role; Type: TYPE; Schema: app; Owner: oden
--

CREATE TYPE app.user_role AS ENUM (
    'user',
    'professional',
    'teacher'
);


ALTER TYPE app.user_role OWNER TO oden;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: app; Owner: oden
--

CREATE FUNCTION app.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION app.set_updated_at() OWNER TO oden;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activities; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    activity_type app.activity_kind NOT NULL,
    actor_id uuid,
    subject_table text NOT NULL,
    subject_id uuid,
    summary text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.activities OWNER TO oden;

--
-- Name: activities_feed; Type: VIEW; Schema: app; Owner: oden
--

CREATE VIEW app.activities_feed AS
 SELECT a.id,
    a.activity_type,
    a.actor_id,
    a.subject_table,
    a.subject_id,
    a.summary,
    a.metadata,
    a.occurred_at
   FROM app.activities a;


ALTER VIEW app.activities_feed OWNER TO oden;

--
-- Name: auth_events; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.auth_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    email text,
    event text NOT NULL,
    ip_address inet,
    user_agent text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.auth_events OWNER TO oden;

--
-- Name: certificates; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.certificates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    course_id uuid,
    issued_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


ALTER TABLE app.certificates OWNER TO oden;

--
-- Name: course_quizzes; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.course_quizzes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid NOT NULL,
    passing_score integer DEFAULT 80 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.course_quizzes OWNER TO oden;

--
-- Name: courses; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.courses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    description text,
    cover_url text,
    video_url text,
    branch text,
    is_free_intro boolean DEFAULT false NOT NULL,
    price_cents integer DEFAULT 0 NOT NULL,
    currency text DEFAULT 'sek'::text NOT NULL,
    is_published boolean DEFAULT false NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.courses OWNER TO oden;

--
-- Name: enrollments; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    course_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    source app.enrollment_source DEFAULT 'purchase'::app.enrollment_source NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.enrollments OWNER TO oden;

--
-- Name: lesson_media; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.lesson_media (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    lesson_id uuid NOT NULL,
    kind text NOT NULL,
    media_id uuid,
    storage_path text,
    storage_bucket text DEFAULT 'lesson-media'::text NOT NULL,
    duration_seconds integer,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lesson_media_kind_check CHECK ((kind = ANY (ARRAY['video'::text, 'audio'::text, 'image'::text, 'pdf'::text, 'other'::text]))),
    CONSTRAINT lesson_media_path_or_object CHECK (((media_id IS NOT NULL) OR (storage_path IS NOT NULL)))
);


ALTER TABLE app.lesson_media OWNER TO oden;

--
-- Name: lessons; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.lessons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    module_id uuid NOT NULL,
    title text NOT NULL,
    content_markdown text,
    video_url text,
    duration_seconds integer,
    is_intro boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.lessons OWNER TO oden;

--
-- Name: media_objects; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.media_objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid,
    storage_path text NOT NULL,
    storage_bucket text DEFAULT 'lesson-media'::text NOT NULL,
    content_type text,
    byte_size bigint DEFAULT 0 NOT NULL,
    checksum text,
    original_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.media_objects OWNER TO oden;

--
-- Name: meditations; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.meditations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    media_id uuid,
    duration_seconds integer,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.meditations OWNER TO oden;

--
-- Name: messages; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sender_id uuid,
    recipient_id uuid,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.messages OWNER TO oden;

--
-- Name: modules; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.modules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid NOT NULL,
    title text NOT NULL,
    summary text,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.modules OWNER TO oden;

--
-- Name: notifications; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.notifications OWNER TO oden;

--
-- Name: orders; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    course_id uuid,
    service_id uuid,
    amount_cents integer NOT NULL,
    currency text DEFAULT 'sek'::text NOT NULL,
    status app.order_status DEFAULT 'pending'::app.order_status NOT NULL,
    stripe_checkout_id text,
    stripe_payment_intent text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.orders OWNER TO oden;

--
-- Name: payments; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    provider text NOT NULL,
    provider_reference text,
    status app.payment_status DEFAULT 'pending'::app.payment_status NOT NULL,
    amount_cents integer NOT NULL,
    currency text DEFAULT 'sek'::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.payments OWNER TO oden;

--
-- Name: posts; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    author_id uuid NOT NULL,
    title text NOT NULL,
    body text,
    visibility text DEFAULT 'public'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.posts OWNER TO oden;

--
-- Name: profiles; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.profiles (
    user_id uuid NOT NULL,
    email text NOT NULL,
    display_name text,
    role app.profile_role DEFAULT 'student'::app.profile_role NOT NULL,
    role_v2 app.user_role DEFAULT 'user'::app.user_role NOT NULL,
    bio text,
    photo_url text,
    is_admin boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    avatar_media_id uuid
);


ALTER TABLE app.profiles OWNER TO oden;

--
-- Name: quiz_questions; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.quiz_questions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid NOT NULL,
    prompt text NOT NULL,
    correct_answer text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.quiz_questions OWNER TO oden;

--
-- Name: refresh_tokens; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.refresh_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    jti uuid NOT NULL,
    token_hash text NOT NULL,
    issued_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    rotated_at timestamp with time zone,
    revoked_at timestamp with time zone,
    last_used_at timestamp with time zone
);


ALTER TABLE app.refresh_tokens OWNER TO oden;

--
-- Name: reviews; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid,
    service_id uuid,
    reviewer_id uuid NOT NULL,
    rating integer NOT NULL,
    comment text,
    visibility app.review_visibility DEFAULT 'public'::app.review_visibility NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


ALTER TABLE app.reviews OWNER TO oden;

--
-- Name: seminar_attendees; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.seminar_attendees (
    seminar_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text DEFAULT 'participant'::text NOT NULL,
    joined_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.seminar_attendees OWNER TO oden;

--
-- Name: seminars; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.seminars (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    host_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    status app.seminar_status DEFAULT 'draft'::app.seminar_status NOT NULL,
    scheduled_at timestamp with time zone,
    duration_minutes integer,
    livekit_room text,
    livekit_metadata jsonb,
    recording_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.seminars OWNER TO oden;

--
-- Name: service_orders; Type: VIEW; Schema: app; Owner: oden
--

CREATE VIEW app.service_orders AS
 SELECT orders.id,
    orders.user_id,
    orders.course_id,
    orders.service_id,
    orders.amount_cents,
    orders.currency,
    orders.status,
    orders.stripe_checkout_id,
    orders.stripe_payment_intent,
    orders.metadata,
    orders.created_at,
    orders.updated_at
   FROM app.orders
  WHERE (orders.service_id IS NOT NULL);


ALTER VIEW app.service_orders OWNER TO oden;

--
-- Name: service_reviews; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.service_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_id uuid NOT NULL,
    order_id uuid,
    reviewer_id uuid,
    rating integer NOT NULL,
    comment text,
    visibility app.review_visibility DEFAULT 'public'::app.review_visibility NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT service_reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


ALTER TABLE app.service_reviews OWNER TO oden;

--
-- Name: services; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.services (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    status app.service_status DEFAULT 'draft'::app.service_status NOT NULL,
    price_cents integer DEFAULT 0 NOT NULL,
    currency text DEFAULT 'sek'::text NOT NULL,
    duration_minutes integer,
    requires_certification boolean DEFAULT false NOT NULL,
    certified_area text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.services OWNER TO oden;

--
-- Name: stripe_customers; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.stripe_customers (
    user_id uuid NOT NULL,
    customer_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.stripe_customers OWNER TO oden;

--
-- Name: tarot_requests; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.tarot_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    requester_id uuid NOT NULL,
    question text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.tarot_requests OWNER TO oden;

--
-- Name: teacher_approvals; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.teacher_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    reviewer_id uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.teacher_approvals OWNER TO oden;

--
-- Name: teacher_directory; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.teacher_directory (
    user_id uuid NOT NULL,
    headline text,
    specialties text[],
    rating numeric(3,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.teacher_directory OWNER TO oden;

--
-- Name: teacher_payout_methods; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.teacher_payout_methods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    teacher_id uuid NOT NULL,
    provider text NOT NULL,
    reference text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.teacher_payout_methods OWNER TO oden;

--
-- Name: teacher_permissions; Type: TABLE; Schema: app; Owner: oden
--

CREATE TABLE app.teacher_permissions (
    profile_id uuid NOT NULL,
    can_edit_courses boolean DEFAULT false NOT NULL,
    can_publish boolean DEFAULT false NOT NULL,
    granted_by uuid,
    granted_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE app.teacher_permissions OWNER TO oden;

--
-- Name: users; Type: TABLE; Schema: auth; Owner: oden
--

CREATE TABLE auth.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    encrypted_password text NOT NULL,
    full_name text,
    is_verified boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE auth.users OWNER TO oden;

--
-- Data for Name: activities; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.activities (id, activity_type, actor_id, subject_table, subject_id, summary, metadata, occurred_at, created_at) FROM stdin;
aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa	order_paid	22222222-2222-4222-8222-222222222222	orders	77777777-7777-4777-8777-777777777777	Seeker Nova booked "1:1 Integration Coaching".	{"seed": true}	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: auth_events; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.auth_events (id, user_id, email, event, ip_address, user_agent, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: certificates; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.certificates (id, user_id, course_id, issued_at, metadata) FROM stdin;
\.


--
-- Data for Name: course_quizzes; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.course_quizzes (id, course_id, passing_score, created_at) FROM stdin;
\.


--
-- Data for Name: courses; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.courses (id, slug, title, description, cover_url, video_url, branch, is_free_intro, price_cents, currency, is_published, created_by, created_at, updated_at) FROM stdin;
33333333-3333-4333-8333-333333333333	foundations-of-soulwisdom	Foundations of SoulWisdom	Kickstart your practice with core breathing and journaling rituals.	https://assets.wisdom.local/course-cover.png	\N	mindfulness	t	0	sek	t	11111111-1111-4111-8111-111111111111	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: enrollments; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.enrollments (id, user_id, course_id, status, source, created_at) FROM stdin;
bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb	22222222-2222-4222-8222-222222222222	33333333-3333-4333-8333-333333333333	active	free_intro	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: lesson_media; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.lesson_media (id, lesson_id, kind, media_id, storage_path, storage_bucket, duration_seconds, "position", created_at) FROM stdin;
\.


--
-- Data for Name: lessons; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.lessons (id, module_id, title, content_markdown, video_url, duration_seconds, is_intro, "position", created_at, updated_at) FROM stdin;
55555555-5555-4555-8555-555555555555	44444444-4444-4444-8444-444444444444	Five-minute Centering Breath	# Centering Breath\\n\\nFind a comfortable seat and follow the guided rhythm.	\N	300	t	0	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: media_objects; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.media_objects (id, owner_id, storage_path, storage_bucket, content_type, byte_size, checksum, original_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: meditations; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.meditations (id, title, description, media_id, duration_seconds, created_by, created_at) FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.messages (id, sender_id, recipient_id, body, created_at) FROM stdin;
\.


--
-- Data for Name: modules; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.modules (id, course_id, title, summary, "position", created_at, updated_at) FROM stdin;
44444444-4444-4444-8444-444444444444	33333333-3333-4333-8333-333333333333	Grounding Practices	Breathwork and morning check-ins to reset your nervous system.	0	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.notifications (id, user_id, payload, read_at, created_at) FROM stdin;
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.orders (id, user_id, course_id, service_id, amount_cents, currency, status, stripe_checkout_id, stripe_payment_intent, metadata, created_at, updated_at) FROM stdin;
77777777-7777-4777-8777-777777777777	22222222-2222-4222-8222-222222222222	\N	66666666-6666-4666-8666-666666666666	12000	sek	paid	cs_test_seed	pi_test_seed	{"seed": true}	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.payments (id, order_id, provider, provider_reference, status, amount_cents, currency, metadata, raw_payload, created_at, updated_at) FROM stdin;
88888888-8888-4888-8888-888888888888	77777777-7777-4777-8777-777777777777	stripe	evt_test_seed	paid	12000	sek	{"integration_test": true}	{"stripe_event": "checkout.session.completed"}	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: posts; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.posts (id, author_id, title, body, visibility, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.profiles (user_id, email, display_name, role, role_v2, bio, photo_url, is_admin, created_at, updated_at, avatar_media_id) FROM stdin;
11111111-1111-4111-8111-111111111111	teacher@wisdom.local	Coach Aurora	teacher	teacher	Certified mindfulness coach focusing on everyday wisdom.	\N	t	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00	\N
22222222-2222-4222-8222-222222222222	student@wisdom.local	Seeker Nova	student	user	Curious student exploring SoulWisdom practices.	\N	f	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00	\N
\.


--
-- Data for Name: quiz_questions; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.quiz_questions (id, course_id, prompt, correct_answer, created_at) FROM stdin;
\.


--
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.refresh_tokens (id, user_id, jti, token_hash, issued_at, expires_at, rotated_at, revoked_at, last_used_at) FROM stdin;
\.


--
-- Data for Name: reviews; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.reviews (id, course_id, service_id, reviewer_id, rating, comment, visibility, created_at) FROM stdin;
\.


--
-- Data for Name: seminar_attendees; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.seminar_attendees (seminar_id, user_id, role, joined_at, created_at) FROM stdin;
99999999-9999-4999-8999-999999999999	22222222-2222-4222-8222-222222222222	participant	\N	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: seminars; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.seminars (id, host_id, title, description, status, scheduled_at, duration_minutes, livekit_room, livekit_metadata, recording_url, created_at, updated_at) FROM stdin;
99999999-9999-4999-8999-999999999999	11111111-1111-4111-8111-111111111111	Morning Presence Circle	Live group practice to sync breath, intention and gratitude.	scheduled	2025-10-11 13:52:27.840913+00	45	wisdom-morning-presence	{"seed": true}	\N	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: service_reviews; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.service_reviews (id, service_id, order_id, reviewer_id, rating, comment, visibility, created_at) FROM stdin;
cccccccc-cccc-4ccc-8ccc-cccccccccccc	66666666-6666-4666-8666-666666666666	77777777-7777-4777-8777-777777777777	22222222-2222-4222-8222-222222222222	5	A grounding experience that left me energized and clear.	public	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: services; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.services (id, provider_id, title, description, status, price_cents, currency, duration_minutes, requires_certification, certified_area, created_at, updated_at) FROM stdin;
66666666-6666-4666-8666-666666666666	11111111-1111-4111-8111-111111111111	1:1 Integration Coaching	Personalized session to integrate insights from your daily practice.	active	12000	sek	60	f	\N	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: stripe_customers; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.stripe_customers (user_id, customer_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: tarot_requests; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.tarot_requests (id, requester_id, question, status, created_at) FROM stdin;
\.


--
-- Data for Name: teacher_approvals; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.teacher_approvals (id, user_id, reviewer_id, status, notes, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: teacher_directory; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.teacher_directory (user_id, headline, specialties, rating, created_at) FROM stdin;
\.


--
-- Data for Name: teacher_payout_methods; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.teacher_payout_methods (id, teacher_id, provider, reference, details, is_default, created_at, updated_at) FROM stdin;
dddddddd-dddd-4ddd-8ddd-dddddddddddd	11111111-1111-4111-8111-111111111111	stripe_connect	acct_seed_teacher	{"account_id": "acct_seed_teacher"}	t	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Data for Name: teacher_permissions; Type: TABLE DATA; Schema: app; Owner: oden
--

COPY app.teacher_permissions (profile_id, can_edit_courses, can_publish, granted_by, granted_at) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: oden
--

COPY auth.users (id, email, encrypted_password, full_name, is_verified, created_at, updated_at) FROM stdin;
11111111-1111-4111-8111-111111111111	teacher@wisdom.local	$2a$06$zbYOo3KP10SPNE.ckAlQm.//s6IjUaXiCxOCaI.Z/Thfolhkyhi2q	Teacher Wisdom	t	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
22222222-2222-4222-8222-222222222222	student@wisdom.local	$2a$06$oiCiHn2fxgVjt2u7YKGNgOCIiFtu2MRGc2YK34sgZowEpNek0YMlK	Student Soul	t	2025-10-08 13:52:27.840913+00	2025-10-08 13:52:27.840913+00
\.


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: auth_events auth_events_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.auth_events
    ADD CONSTRAINT auth_events_pkey PRIMARY KEY (id);


--
-- Name: certificates certificates_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.certificates
    ADD CONSTRAINT certificates_pkey PRIMARY KEY (id);


--
-- Name: course_quizzes course_quizzes_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.course_quizzes
    ADD CONSTRAINT course_quizzes_pkey PRIMARY KEY (id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: courses courses_slug_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.courses
    ADD CONSTRAINT courses_slug_key UNIQUE (slug);


--
-- Name: enrollments enrollments_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_user_id_course_id_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_user_id_course_id_key UNIQUE (user_id, course_id);


--
-- Name: lesson_media lesson_media_lesson_id_position_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_lesson_id_position_key UNIQUE (lesson_id, "position");


--
-- Name: lesson_media lesson_media_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_pkey PRIMARY KEY (id);


--
-- Name: lessons lessons_module_id_position_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.lessons
    ADD CONSTRAINT lessons_module_id_position_key UNIQUE (module_id, "position");


--
-- Name: lessons lessons_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.lessons
    ADD CONSTRAINT lessons_pkey PRIMARY KEY (id);


--
-- Name: media_objects media_objects_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.media_objects
    ADD CONSTRAINT media_objects_pkey PRIMARY KEY (id);


--
-- Name: media_objects media_objects_storage_path_storage_bucket_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.media_objects
    ADD CONSTRAINT media_objects_storage_path_storage_bucket_key UNIQUE (storage_path, storage_bucket);


--
-- Name: meditations meditations_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.meditations
    ADD CONSTRAINT meditations_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: modules modules_course_id_position_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.modules
    ADD CONSTRAINT modules_course_id_position_key UNIQUE (course_id, "position");


--
-- Name: modules modules_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.modules
    ADD CONSTRAINT modules_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_email_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_email_key UNIQUE (email);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (user_id);


--
-- Name: quiz_questions quiz_questions_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.quiz_questions
    ADD CONSTRAINT quiz_questions_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_jti_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.refresh_tokens
    ADD CONSTRAINT refresh_tokens_jti_key UNIQUE (jti);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: seminar_attendees seminar_attendees_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.seminar_attendees
    ADD CONSTRAINT seminar_attendees_pkey PRIMARY KEY (seminar_id, user_id);


--
-- Name: seminars seminars_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.seminars
    ADD CONSTRAINT seminars_pkey PRIMARY KEY (id);


--
-- Name: service_reviews service_reviews_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_pkey PRIMARY KEY (id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: stripe_customers stripe_customers_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.stripe_customers
    ADD CONSTRAINT stripe_customers_pkey PRIMARY KEY (user_id);


--
-- Name: tarot_requests tarot_requests_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.tarot_requests
    ADD CONSTRAINT tarot_requests_pkey PRIMARY KEY (id);


--
-- Name: teacher_approvals teacher_approvals_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_pkey PRIMARY KEY (id);


--
-- Name: teacher_directory teacher_directory_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_directory
    ADD CONSTRAINT teacher_directory_pkey PRIMARY KEY (user_id);


--
-- Name: teacher_payout_methods teacher_payout_methods_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_payout_methods
    ADD CONSTRAINT teacher_payout_methods_pkey PRIMARY KEY (id);


--
-- Name: teacher_payout_methods teacher_payout_methods_teacher_id_provider_reference_key; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_payout_methods
    ADD CONSTRAINT teacher_payout_methods_teacher_id_provider_reference_key UNIQUE (teacher_id, provider, reference);


--
-- Name: teacher_permissions teacher_permissions_pkey; Type: CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_permissions
    ADD CONSTRAINT teacher_permissions_pkey PRIMARY KEY (profile_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: auth; Owner: oden
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: oden
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_activities_occurred; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_activities_occurred ON app.activities USING btree (occurred_at DESC);


--
-- Name: idx_activities_subject; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_activities_subject ON app.activities USING btree (subject_table, subject_id);


--
-- Name: idx_activities_type; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_activities_type ON app.activities USING btree (activity_type);


--
-- Name: idx_auth_events_created_at; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_auth_events_created_at ON app.auth_events USING btree (created_at DESC);


--
-- Name: idx_auth_events_user; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_auth_events_user ON app.auth_events USING btree (user_id);


--
-- Name: idx_certificates_user; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_certificates_user ON app.certificates USING btree (user_id);


--
-- Name: idx_courses_created_by; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_courses_created_by ON app.courses USING btree (created_by);


--
-- Name: idx_enrollments_course; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_enrollments_course ON app.enrollments USING btree (course_id);


--
-- Name: idx_enrollments_user; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_enrollments_user ON app.enrollments USING btree (user_id);


--
-- Name: idx_lesson_media_lesson; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_lesson_media_lesson ON app.lesson_media USING btree (lesson_id);


--
-- Name: idx_lesson_media_media; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_lesson_media_media ON app.lesson_media USING btree (media_id);


--
-- Name: idx_lessons_module; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_lessons_module ON app.lessons USING btree (module_id);


--
-- Name: idx_media_owner; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_media_owner ON app.media_objects USING btree (owner_id);


--
-- Name: idx_messages_recipient; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_messages_recipient ON app.messages USING btree (recipient_id);


--
-- Name: idx_modules_course; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_modules_course ON app.modules USING btree (course_id);


--
-- Name: idx_notifications_read; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_notifications_read ON app.notifications USING btree (user_id, read_at);


--
-- Name: idx_notifications_user; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_notifications_user ON app.notifications USING btree (user_id);


--
-- Name: idx_orders_course; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_orders_course ON app.orders USING btree (course_id);


--
-- Name: idx_orders_service; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_orders_service ON app.orders USING btree (service_id);


--
-- Name: idx_orders_status; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_orders_status ON app.orders USING btree (status);


--
-- Name: idx_orders_user; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_orders_user ON app.orders USING btree (user_id);


--
-- Name: idx_payments_order; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_payments_order ON app.payments USING btree (order_id);


--
-- Name: idx_payments_status; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_payments_status ON app.payments USING btree (status);


--
-- Name: idx_payout_methods_teacher; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_payout_methods_teacher ON app.teacher_payout_methods USING btree (teacher_id);


--
-- Name: idx_posts_author; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_posts_author ON app.posts USING btree (author_id);


--
-- Name: idx_quiz_questions_course; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_quiz_questions_course ON app.quiz_questions USING btree (course_id);


--
-- Name: idx_refresh_tokens_user; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_refresh_tokens_user ON app.refresh_tokens USING btree (user_id);


--
-- Name: idx_reviews_course; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_reviews_course ON app.reviews USING btree (course_id);


--
-- Name: idx_reviews_reviewer; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_reviews_reviewer ON app.reviews USING btree (reviewer_id);


--
-- Name: idx_reviews_service; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_reviews_service ON app.reviews USING btree (service_id);


--
-- Name: idx_seminars_host; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_seminars_host ON app.seminars USING btree (host_id);


--
-- Name: idx_seminars_scheduled_at; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_seminars_scheduled_at ON app.seminars USING btree (scheduled_at);


--
-- Name: idx_seminars_status; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_seminars_status ON app.seminars USING btree (status);


--
-- Name: idx_service_reviews_reviewer; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_service_reviews_reviewer ON app.service_reviews USING btree (reviewer_id);


--
-- Name: idx_service_reviews_service; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_service_reviews_service ON app.service_reviews USING btree (service_id);


--
-- Name: idx_services_provider; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_services_provider ON app.services USING btree (provider_id);


--
-- Name: idx_services_status; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_services_status ON app.services USING btree (status);


--
-- Name: idx_teacher_approvals_user; Type: INDEX; Schema: app; Owner: oden
--

CREATE INDEX idx_teacher_approvals_user ON app.teacher_approvals USING btree (user_id);


--
-- Name: idx_auth_users_email_lower; Type: INDEX; Schema: auth; Owner: oden
--

CREATE INDEX idx_auth_users_email_lower ON auth.users USING btree (lower(email));


--
-- Name: courses trg_courses_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_courses_touch BEFORE UPDATE ON app.courses FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: lessons trg_lessons_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_lessons_touch BEFORE UPDATE ON app.lessons FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: modules trg_modules_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_modules_touch BEFORE UPDATE ON app.modules FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: orders trg_orders_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON app.orders FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: payments trg_payments_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_payments_touch BEFORE UPDATE ON app.payments FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: seminars trg_seminars_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_seminars_touch BEFORE UPDATE ON app.seminars FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: services trg_services_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_services_touch BEFORE UPDATE ON app.services FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: teacher_payout_methods trg_teacher_payout_methods_touch; Type: TRIGGER; Schema: app; Owner: oden
--

CREATE TRIGGER trg_teacher_payout_methods_touch BEFORE UPDATE ON app.teacher_payout_methods FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: activities activities_actor_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.activities
    ADD CONSTRAINT activities_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: auth_events auth_events_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.auth_events
    ADD CONSTRAINT auth_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: certificates certificates_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.certificates
    ADD CONSTRAINT certificates_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL;


--
-- Name: certificates certificates_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.certificates
    ADD CONSTRAINT certificates_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: course_quizzes course_quizzes_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.course_quizzes
    ADD CONSTRAINT course_quizzes_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: courses courses_created_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.courses
    ADD CONSTRAINT courses_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: enrollments enrollments_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: enrollments enrollments_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: lesson_media lesson_media_lesson_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES app.lessons(id) ON DELETE CASCADE;


--
-- Name: lesson_media lesson_media_media_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_media_id_fkey FOREIGN KEY (media_id) REFERENCES app.media_objects(id) ON DELETE SET NULL;


--
-- Name: lessons lessons_module_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.lessons
    ADD CONSTRAINT lessons_module_id_fkey FOREIGN KEY (module_id) REFERENCES app.modules(id) ON DELETE CASCADE;


--
-- Name: media_objects media_objects_owner_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.media_objects
    ADD CONSTRAINT media_objects_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: meditations meditations_created_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.meditations
    ADD CONSTRAINT meditations_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: meditations meditations_media_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.meditations
    ADD CONSTRAINT meditations_media_id_fkey FOREIGN KEY (media_id) REFERENCES app.media_objects(id) ON DELETE SET NULL;


--
-- Name: messages messages_recipient_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.messages
    ADD CONSTRAINT messages_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: modules modules_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.modules
    ADD CONSTRAINT modules_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: orders orders_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL;


--
-- Name: orders orders_service_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_service_id_fkey FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE SET NULL;


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: payments payments_order_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.payments
    ADD CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE CASCADE;


--
-- Name: posts posts_author_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.posts
    ADD CONSTRAINT posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: profiles profiles_avatar_media_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_avatar_media_id_fkey FOREIGN KEY (avatar_media_id) REFERENCES app.media_objects(id);


--
-- Name: profiles profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: quiz_questions quiz_questions_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.quiz_questions
    ADD CONSTRAINT quiz_questions_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: reviews reviews_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: reviews reviews_service_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_service_id_fkey FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE CASCADE;


--
-- Name: seminar_attendees seminar_attendees_seminar_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.seminar_attendees
    ADD CONSTRAINT seminar_attendees_seminar_id_fkey FOREIGN KEY (seminar_id) REFERENCES app.seminars(id) ON DELETE CASCADE;


--
-- Name: seminar_attendees seminar_attendees_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.seminar_attendees
    ADD CONSTRAINT seminar_attendees_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: seminars seminars_host_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.seminars
    ADD CONSTRAINT seminars_host_id_fkey FOREIGN KEY (host_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: service_reviews service_reviews_order_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_order_id_fkey FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE SET NULL;


--
-- Name: service_reviews service_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: service_reviews service_reviews_service_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_service_id_fkey FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE CASCADE;


--
-- Name: services services_provider_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.services
    ADD CONSTRAINT services_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: stripe_customers stripe_customers_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.stripe_customers
    ADD CONSTRAINT stripe_customers_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: tarot_requests tarot_requests_requester_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.tarot_requests
    ADD CONSTRAINT tarot_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_approvals teacher_approvals_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id);


--
-- Name: teacher_approvals teacher_approvals_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_directory teacher_directory_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_directory
    ADD CONSTRAINT teacher_directory_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_payout_methods teacher_payout_methods_teacher_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_payout_methods
    ADD CONSTRAINT teacher_payout_methods_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_permissions teacher_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_permissions
    ADD CONSTRAINT teacher_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES app.profiles(user_id);


--
-- Name: teacher_permissions teacher_permissions_profile_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: oden
--

ALTER TABLE ONLY app.teacher_permissions
    ADD CONSTRAINT teacher_permissions_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict FyP0dJdUichEecNr8aKks3jcqip7vUEzX7Tyy60HLBFFgaRmTh4te3gZjWrfKtY

