--
-- PostgreSQL database dump
--

\restrict UwadLlUJMIkDO97d4caafylDXxFjntglsF2yWDccNA1zSpsWiN8d7xwu7iy6JO3

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
-- Name: app; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app;


--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: activity_kind; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.activity_kind AS ENUM (
    'profile_updated',
    'course_published',
    'lesson_published',
    'service_created',
    'order_paid',
    'seminar_scheduled'
);


--
-- Name: enrollment_source; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.enrollment_source AS ENUM (
    'free_intro',
    'purchase',
    'membership',
    'grant'
);


--
-- Name: order_status; Type: TYPE; Schema: app; Owner: -
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


--
-- Name: payment_status; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.payment_status AS ENUM (
    'pending',
    'processing',
    'paid',
    'failed',
    'refunded'
);


--
-- Name: profile_role; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.profile_role AS ENUM (
    'student',
    'teacher',
    'admin'
);


--
-- Name: review_visibility; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.review_visibility AS ENUM (
    'public',
    'private'
);


--
-- Name: seminar_status; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.seminar_status AS ENUM (
    'draft',
    'scheduled',
    'live',
    'ended',
    'canceled'
);


--
-- Name: service_status; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.service_status AS ENUM (
    'draft',
    'active',
    'paused',
    'archived'
);


--
-- Name: user_role; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.user_role AS ENUM (
    'user',
    'professional',
    'teacher'
);


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activities; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: activities_feed; Type: VIEW; Schema: app; Owner: -
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


--
-- Name: app_config; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.app_config (
    id integer DEFAULT 1 NOT NULL,
    free_course_limit integer DEFAULT 5 NOT NULL,
    platform_fee_pct numeric DEFAULT 10 NOT NULL
);


--
-- Name: auth_events; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: certificates; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.certificates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    course_id uuid,
    title text,
    status text DEFAULT 'pending'::text NOT NULL,
    notes text,
    evidence_url text,
    issued_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: course_quizzes; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.course_quizzes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid NOT NULL,
    title text,
    pass_score integer DEFAULT 80 NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: courses; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: enrollments; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    course_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    source app.enrollment_source DEFAULT 'purchase'::app.enrollment_source NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: follows; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.follows (
    follower_id uuid NOT NULL,
    followee_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: lesson_media; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: lessons; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: media_objects; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: meditations; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.meditations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    teacher_id uuid,
    media_id uuid,
    audio_path text,
    duration_seconds integer,
    is_public boolean DEFAULT false NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: messages; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel text,
    sender_id uuid,
    recipient_id uuid,
    content text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: modules; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: notifications; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: orders; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: payments; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: posts; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    author_id uuid NOT NULL,
    content text NOT NULL,
    media_paths jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: profiles; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: quiz_questions; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.quiz_questions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid,
    quiz_id uuid,
    "position" integer DEFAULT 0 NOT NULL,
    kind text DEFAULT 'single'::text NOT NULL,
    prompt text NOT NULL,
    options jsonb DEFAULT '{}'::jsonb NOT NULL,
    correct text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: reviews; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: seminar_attendees; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.seminar_attendees (
    seminar_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text DEFAULT 'participant'::text NOT NULL,
    joined_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: seminars; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: service_orders; Type: VIEW; Schema: app; Owner: -
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


--
-- Name: service_reviews; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: services; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.services (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    status app.service_status DEFAULT 'draft'::app.service_status NOT NULL,
    price_cents integer DEFAULT 0 NOT NULL,
    currency text DEFAULT 'sek'::text NOT NULL,
    duration_min integer,
    requires_certification boolean DEFAULT false NOT NULL,
    certified_area text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stripe_customers; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.stripe_customers (
    user_id uuid NOT NULL,
    customer_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tarot_requests; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.tarot_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    requester_id uuid NOT NULL,
    question text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: teacher_approvals; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.teacher_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    reviewer_id uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    notes text,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: teacher_directory; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.teacher_directory (
    user_id uuid NOT NULL,
    headline text,
    specialties text[],
    rating numeric(3,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: teacher_payout_methods; Type: TABLE; Schema: app; Owner: -
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


--
-- Name: teacher_permissions; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.teacher_permissions (
    profile_id uuid NOT NULL,
    can_edit_courses boolean DEFAULT false NOT NULL,
    can_publish boolean DEFAULT false NOT NULL,
    granted_by uuid,
    granted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: auth; Owner: -
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


--
-- Data for Name: activities; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.activities (id, activity_type, actor_id, subject_table, subject_id, summary, metadata, occurred_at, created_at) FROM stdin;
aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa	order_paid	22222222-2222-4222-8222-222222222222	orders	77777777-7777-4777-8777-777777777777	Seeker Nova booked "1:1 Integration Coaching".	{"seed": true}	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
\.


--
-- Data for Name: app_config; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.app_config (id, free_course_limit, platform_fee_pct) FROM stdin;
1	5	10
\.


--
-- Data for Name: auth_events; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.auth_events (id, user_id, email, event, ip_address, user_agent, metadata, created_at) FROM stdin;
45af0d1e-9dfc-4b58-98bd-d99f551f325d	703977ae-ee67-4567-8737-2df9eafa0b4d	smoke_099477@aveli.local	register_success	127.0.0.1	python-httpx/0.27.0	{"refresh_jti": "3f1c0a38-84af-46f0-b206-1c83ea85e598"}	2025-10-08 18:09:25.780755+00
adf68303-89e8-4dc0-832e-e163fab237e4	1d7ef616-6c3a-452e-bcaa-bfd9b41a9c35	smoke_ea8e6f@aveli.local	register_success	127.0.0.1	python-httpx/0.27.0	{"refresh_jti": "41cf59ed-c129-4c13-a7b9-9c91b0129474"}	2025-10-08 18:10:39.814369+00
68873f3b-ca5d-4703-81bc-a417e6bdfba9	1d7ef616-6c3a-452e-bcaa-bfd9b41a9c35	\N	refresh_success	127.0.0.1	python-httpx/0.27.0	{"refresh_jti": "42afdda8-5524-48b0-8fb5-e90f24473548", "rotated_from": "41cf59ed-c129-4c13-a7b9-9c91b0129474"}	2025-10-08 18:10:39.819137+00
ff167502-5366-4866-8cfc-4dbf595c8b55	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	odenhjalm@outlook.com	login_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "ec83e5a7-6d8d-4666-852d-b83276ccb004"}	2025-10-08 18:18:16.913267+00
eefd82ae-7570-48d2-8bfe-164b010d8b15	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "e12d908c-daed-4137-946f-1048a4e91b69", "rotated_from": "ec83e5a7-6d8d-4666-852d-b83276ccb004"}	2025-10-08 18:34:12.190486+00
d0ccc764-b3fd-4f7e-9e34-55c2496b5b19	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "6ae7423e-223c-4f9a-84a0-25ca3f8b301d", "rotated_from": "e12d908c-daed-4137-946f-1048a4e91b69"}	2025-10-08 19:09:36.451521+00
80961769-eccc-4d11-b286-dcf4ab17aecf	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "400e8941-65ea-4d3f-af45-b2dbe4bdaa2e", "rotated_from": "6ae7423e-223c-4f9a-84a0-25ca3f8b301d"}	2025-10-08 19:24:51.049811+00
76f3ed7c-00ac-4d28-99d4-3a4a2d9c2eb4	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "118dfdd5-03b0-4e1b-88ac-e9c78c3260e1", "rotated_from": "400e8941-65ea-4d3f-af45-b2dbe4bdaa2e"}	2025-10-08 20:11:13.175361+00
984e3a61-60ce-4a6d-a9d0-af6b93cba1b5	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "8b7114de-c025-4cf5-ab58-0cf6df524337", "rotated_from": "118dfdd5-03b0-4e1b-88ac-e9c78c3260e1"}	2025-10-08 20:33:29.029279+00
81ec731e-0dcd-4651-a0b9-41318e10fa6e	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	odenhjalm@outlook.com	login_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "373d8149-934c-41c2-abf8-73896a50718d"}	2025-10-08 20:55:35.77372+00
a9bccc8f-0a81-4237-9bb2-fd60d501d84a	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "7e187a9f-8fd8-4a63-9de1-f2a5b9998657", "rotated_from": "373d8149-934c-41c2-abf8-73896a50718d"}	2025-10-08 21:39:17.862812+00
21e42007-9e7e-4594-806a-7c580f74041c	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "bda23166-eb8b-4522-874c-e9bd073f41a1", "rotated_from": "7e187a9f-8fd8-4a63-9de1-f2a5b9998657"}	2025-10-08 22:03:38.447214+00
58d40214-d85a-48a6-81dc-c5b83e22ec77	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "a16a1265-2191-4ece-96e9-d6ede4b7b0eb", "rotated_from": "bda23166-eb8b-4522-874c-e9bd073f41a1"}	2025-10-08 22:30:37.7495+00
f625f04b-ab49-4d58-bd8b-b96ef98f3ed7	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "b1397a20-523a-4ba9-92bd-d533f8a3da7c", "rotated_from": "a16a1265-2191-4ece-96e9-d6ede4b7b0eb"}	2025-10-08 22:56:37.607211+00
83c3fe94-62f2-4979-a8a1-b73544e75a66	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "c0d1bc08-3124-4790-8562-b98bfb851441", "rotated_from": "b1397a20-523a-4ba9-92bd-d533f8a3da7c"}	2025-10-08 23:47:49.874957+00
f441b3f5-1c05-4eae-81ca-3fdd737c3855	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	refresh_success	127.0.0.1	Dart/3.9 (dart:io)	{"refresh_jti": "9326b8f3-9da9-4e5b-b70a-1a18c67a9055", "rotated_from": "c0d1bc08-3124-4790-8562-b98bfb851441"}	2025-10-09 00:03:25.001527+00
\.


--
-- Data for Name: certificates; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.certificates (id, user_id, course_id, title, status, notes, evidence_url, issued_at, metadata, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: course_quizzes; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.course_quizzes (id, course_id, title, pass_score, created_by, created_at) FROM stdin;
\.


--
-- Data for Name: courses; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.courses (id, slug, title, description, cover_url, video_url, branch, is_free_intro, price_cents, currency, is_published, created_by, created_at, updated_at) FROM stdin;
33333333-3333-4333-8333-333333333333	foundations-of-soulaveli	Foundations of SoulAveli	Kickstart your practice with core breathing and journaling rituals.	https://assets.aveli.local/course-cover.png	\N	mindfulness	t	0	sek	t	11111111-1111-4111-8111-111111111111	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
a04fac37-5d4b-478f-982b-761d6b96f694	vem-tänker-och-vem-hör-tankar-aevu-hbuo6wmmc1	Vem tänker och vem hör tankar ?	\N	\N	\N	\N	f	0	sek	f	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	2025-10-08 20:24:17.690907+00	2025-10-08 20:24:17.690907+00
448bf8b9-e33c-45e0-a4fb-a871d31a74f9	att-tänka-själv-4yfs-hbuo58am2l	Att tänka Själv	I denna kurs lär du dig att leva med dina tankar	\N	\N	\N	t	670	sek	t	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	2025-10-08 20:22:36.360414+00	2025-10-08 20:58:22.032369+00
\.


--
-- Data for Name: enrollments; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.enrollments (id, user_id, course_id, status, source, created_at) FROM stdin;
bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb	22222222-2222-4222-8222-222222222222	33333333-3333-4333-8333-333333333333	active	free_intro	2025-10-08 18:04:03.310975+00
4fb94605-4686-49cc-b477-9559ac261cc2	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	448bf8b9-e33c-45e0-a4fb-a871d31a74f9	active	free_intro	2025-10-08 22:04:02.730803+00
\.


--
-- Data for Name: follows; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.follows (follower_id, followee_id, created_at) FROM stdin;
\.


--
-- Data for Name: lesson_media; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.lesson_media (id, lesson_id, kind, media_id, storage_path, storage_bucket, duration_seconds, "position", created_at) FROM stdin;
546f3e91-5be9-4191-b2e1-1154013fa602	8ca27fae-a1a0-416e-9593-413dd92011b2	image	058a9596-def6-455b-8d8b-97c0c39cb26a	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/530936a4de314d45983963ecc29fe6bf_Night.png	lesson-media	\N	1	2025-10-08 20:25:44.617526+00
54cf2a54-187f-4acc-be75-7de973533484	8ca27fae-a1a0-416e-9593-413dd92011b2	image	9b445b73-b893-4f37-8ec1-5e3c28302907	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/7d7e128f56e94998bb586714a1398410_Night.png	lesson-media	\N	2	2025-10-08 20:55:51.645067+00
17cb7a98-df93-44bd-9457-73eea485cbce	8ca27fae-a1a0-416e-9593-413dd92011b2	image	7fed900b-e8a7-4563-a427-05d92a87c4ca	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/8498e77ea1b9498788e016e161b0fda8_ChatGPT Image Oct 6, 2025, 01_53_18 PM.png	lesson-media	\N	3	2025-10-08 20:57:53.328387+00
e8850ac9-c0ff-42c0-a8d3-ffaaa0a6eb88	8ca27fae-a1a0-416e-9593-413dd92011b2	image	13660718-7143-4e77-a7c0-88045784168f	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/6832f87aada943eda152fe1282cebe3d_Day.png	lesson-media	\N	4	2025-10-08 21:45:16.830465+00
\.


--
-- Data for Name: lessons; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.lessons (id, module_id, title, content_markdown, video_url, duration_seconds, is_intro, "position", created_at, updated_at) FROM stdin;
55555555-5555-4555-8555-555555555555	44444444-4444-4444-8444-444444444444	Five-minute Centering Breath	# Centering Breath\\n\\nFind a comfortable seat and follow the guided rhythm.	\N	300	t	0	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
8ca27fae-a1a0-416e-9593-413dd92011b2	838d6900-8d87-43af-83d4-23292de829f5	Att lyssna på jaget	**🜂 Lektion 1: Att Lyssna på Jaget**\n\n\n\n\n\n\n\n**🕊 Inledning**\n\n\n\nDe flesta människor tror att de tänker själva — men i själva verket upprepar de bara världens röster\\. Röster från föräldrar, lärare, media, religion, tradition\\. De har blivit så vana vid ekot att de inte längre känner igen sin egen ton\\.\n\nDenna lektion handlar om att bryta igenom det bruset — och lyssna\\. Inte med öronen, utan med hela ditt väsen\\.\n\n\n\n**🜁 Syfte**\n\n\n\nAtt återupptäcka den direkta kontakten med ditt innersta Jag\\.\n\nInte det inlärda, inte det programmerade — utan den levande intelligensen inom dig som alltid vet\\.\n\n\n\nMålet är inte att “bli” något, utan att höra det som redan är\\.\n\n\n\n**🜃 Begrepp: Vad är Jaget?**\n\n\n\nJaget är inte din personlighet\\.\n\nDet är inte ditt namn, din roll, eller dina tankar\\.\n\nJaget är det som vet att du tänker\\.\n\nDet är stillheten bakom varje tanke — det som betraktar, upplever, lyssnar\\.\n\n\n\nNär du lär dig att lyssna på Jaget, upptäcker du att visdom inte behöver läras in\\.\n\nDen uppstår av sig själv, ur tystnadens djup\\.\n\n\n\n**🜄 Övning 1: Det första lyssnandet**\n\n\n\nSätt dig bekvämt\\. Slut ögonen\\.\n\n\n\nAndas djupt tre gånger\\.\n\n\n\nLåt alla tankar få röra sig som moln på himlen\\.\n\n\n\nIstället för att följa tankarna, fråga tyst:\n\n\n\n“Vem är det som lyssnar nu?”\n\n\n\nKänn hur något inom dig svarar — inte med ord, utan med närvaro\\.\n\n\n\nStanna där\\.\n\nDu behöver inte förstå\\.\n\nDu behöver bara höra stillheten svara\\.\n\n\n\n**🜅 Reflektion**\n\n\n\nEfter övningen, skriv i din dagbok:\n\n\n\nVad kände jag när jag frågade “Vem lyssnar?”\n\n\n\nKom någon tanke, bild eller känsla upp?\n\n\n\nHur känns skillnaden mellan att tänka och att lyssna?\n\n\n\nInga svar är fel — det viktiga är att du ser skillnaden mellan tankens röst och medvetandets röst\\.\n\n\n\n🜆 Övning 2: Rösterna i mig\n\n\n\nUnder dagen, observera:\n\n\n\nNär jag talar, vem talar genom mig?\n\n\n\nNär jag känner skuld, vem är det som skuldbelägger?\n\n\n\nNär jag känner frid, vem är det som är fridfull?\n\n\n\nSkriv ner tre tillfällen då du märkte att du inte var ditt “äkta jag” — och ett tillfälle då du var det\\.\n\n\n\n**🜇 Avslutning**\n\n\n\nAtt lyssna på Jaget kräver mod\\.\n\nFör när du verkligen lyssnar, tystnar allt annat — och det kan kännas som att världen försvinner\\.\n\nMen det är då du börjar tänka själv\\.\n\nInte längre som en produkt av samhället, utan som en fri medveten varelse\\.\n\n\n\n“Den som lär sig att lyssna på sitt Jag, behöver inte längre fråga världen vem hen är\\.”\n\n	\N	\N	f	1	2025-10-08 20:25:35.843229+00	2025-10-08 20:58:04.836381+00
\.


--
-- Data for Name: media_objects; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.media_objects (id, owner_id, storage_path, storage_bucket, content_type, byte_size, checksum, original_name, created_at, updated_at) FROM stdin;
058a9596-def6-455b-8d8b-97c0c39cb26a	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/530936a4de314d45983963ecc29fe6bf_Night.png	lesson-media	image/png	3061291	54e4779455888006682029467ad8d9a599a034955cbf261435c1df0c3dda7a0e	Night.png	2025-10-08 20:25:44.614426+00	2025-10-08 20:25:44.614426+00
9b445b73-b893-4f37-8ec1-5e3c28302907	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/7d7e128f56e94998bb586714a1398410_Night.png	lesson-media	image/png	3061291	54e4779455888006682029467ad8d9a599a034955cbf261435c1df0c3dda7a0e	Night.png	2025-10-08 20:55:51.643067+00	2025-10-08 20:55:51.643067+00
7fed900b-e8a7-4563-a427-05d92a87c4ca	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/8498e77ea1b9498788e016e161b0fda8_ChatGPT Image Oct 6, 2025, 01_53_18 PM.png	lesson-media	image/png	2463668	742b04d352355ae76c4814ba2fddc608fc91073ac5b93b76cc2cef39bcdb196e	ChatGPT Image Oct 6, 2025, 01_53_18 PM.png	2025-10-08 20:57:53.326423+00	2025-10-08 20:57:53.326423+00
043892f3-c3a0-4e6b-9175-b287cef37c2e	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	avatars/1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6/a3b5b6eb0ad44f59bff4430be2beee54_Night Loggo.png	profile-avatars	image/png	2023974	c5f62a202843c5a8305b453e7864033ed3a6bb66477b9b87c0455bb1ea7336ac	Night Loggo.png	2025-10-08 20:58:57.105231+00	2025-10-08 20:58:57.105231+00
13660718-7143-4e77-a7c0-88045784168f	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	448bf8b9-e33c-45e0-a4fb-a871d31a74f9/8ca27fae-a1a0-416e-9593-413dd92011b2/6832f87aada943eda152fe1282cebe3d_Day.png	lesson-media	image/png	2184269	47f57ec5815f757eca795719c0dcf4438b047cd60d851bbefe54d350445606a1	Day.png	2025-10-08 21:45:16.827928+00	2025-10-08 21:45:16.827928+00
\.


--
-- Data for Name: meditations; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.meditations (id, title, description, teacher_id, media_id, audio_path, duration_seconds, is_public, created_by, created_at) FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.messages (id, channel, sender_id, recipient_id, content, created_at) FROM stdin;
\.


--
-- Data for Name: modules; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.modules (id, course_id, title, summary, "position", created_at, updated_at) FROM stdin;
44444444-4444-4444-8444-444444444444	33333333-3333-4333-8333-333333333333	Grounding Practices	Breathwork and morning check-ins to reset your nervous system.	0	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
838d6900-8d87-43af-83d4-23292de829f5	448bf8b9-e33c-45e0-a4fb-a871d31a74f9	Vem hör om du tänker?	\N	1	2025-10-08 20:25:15.851124+00	2025-10-08 20:25:15.851124+00
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.notifications (id, user_id, payload, read_at, created_at) FROM stdin;
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.orders (id, user_id, course_id, service_id, amount_cents, currency, status, stripe_checkout_id, stripe_payment_intent, metadata, created_at, updated_at) FROM stdin;
77777777-7777-4777-8777-777777777777	22222222-2222-4222-8222-222222222222	\N	66666666-6666-4666-8666-666666666666	12000	sek	paid	cs_test_seed	pi_test_seed	{"seed": true}	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
dff54ce6-7311-41b3-adb7-f495cadbffa8	1d7ef616-6c3a-452e-bcaa-bfd9b41a9c35	\N	66666666-6666-4666-8666-666666666666	12000	sek	paid	cs_test_smoke	pi_test_smoke	{"provider_id": "11111111-1111-4111-8111-111111111111", "service_title": "1:1 Integration Coaching"}	2025-10-08 18:10:39.821979+00	2025-10-08 18:10:39.82802+00
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.payments (id, order_id, provider, provider_reference, status, amount_cents, currency, metadata, raw_payload, created_at, updated_at) FROM stdin;
88888888-8888-4888-8888-888888888888	77777777-7777-4777-8777-777777777777	stripe	evt_test_seed	paid	12000	sek	{"integration_test": true}	{"stripe_event": "checkout.session.completed"}	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
d4cb2df4-cd60-495b-a296-c621528b5737	dff54ce6-7311-41b3-adb7-f495cadbffa8	stripe	pi_test_smoke	paid	12000	sek	{"event": "checkout.session.completed"}	{"currency": "sek", "metadata": {"order_id": "dff54ce6-7311-41b3-adb7-f495cadbffa8"}, "amount_total": 12000, "payment_intent": "pi_test_smoke"}	2025-10-08 18:10:39.828767+00	2025-10-08 18:10:39.828767+00
\.


--
-- Data for Name: posts; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.posts (id, author_id, content, media_paths, created_at) FROM stdin;
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.profiles (user_id, email, display_name, role, role_v2, bio, photo_url, is_admin, created_at, updated_at, avatar_media_id) FROM stdin;
11111111-1111-4111-8111-111111111111	teacher@aveli.local	Coach Aurora	teacher	teacher	Certified mindfulness coach focusing on everyday aveli.	\N	t	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00	\N
22222222-2222-4222-8222-222222222222	student@aveli.local	Seeker Nova	student	user	Curious student exploring SoulAveli practices.	\N	f	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00	\N
7ca432db-1c03-45b5-be38-54d3f6c4da4b	admin_f3bcaf18@example.com	Admin	student	user	\N	\N	f	2025-10-08 18:07:38.463013+00	2025-10-08 18:07:38.463013+00	\N
00be7360-eb04-4f39-8904-555306509417	smoke_59ded8@aveli.local	Smoke Tester	student	user	\N	\N	f	2025-10-08 18:07:38.780499+00	2025-10-08 18:07:38.780499+00	\N
c4505a51-1f7f-4c09-affd-9b91f52084b8	student_c27c8ed2@example.com	Student	student	user	\N	\N	f	2025-10-08 18:07:39.033446+00	2025-10-08 18:07:39.033446+00	\N
df22e24e-25fe-43b3-b7f2-3734019f80e8	teacher_937efb4f@example.com	Teacher	student	user	\N	\N	f	2025-10-08 18:07:39.283855+00	2025-10-08 18:07:39.283855+00	\N
3e7468d4-c413-4af4-8320-b01b9f5eb786	teacher_08b468e4@example.com	Teacher	student	user	\N	\N	f	2025-10-08 18:07:39.536914+00	2025-10-08 18:07:39.536914+00	\N
703977ae-ee67-4567-8737-2df9eafa0b4d	smoke_099477@aveli.local	Smoke Tester	student	user	\N	\N	f	2025-10-08 18:09:25.770938+00	2025-10-08 18:09:25.770938+00	\N
1d7ef616-6c3a-452e-bcaa-bfd9b41a9c35	smoke_ea8e6f@aveli.local	Smoke Tester	student	user	\N	\N	f	2025-10-08 18:10:39.804935+00	2025-10-08 18:10:39.804935+00	\N
1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	odenhjalm@outlook.com	Oden	teacher	teacher	\N	/auth/avatar/043892f3-c3a0-4e6b-9175-b287cef37c2e	f	2025-10-08 18:14:33.381913+00	2025-10-08 21:40:42.264755+00	043892f3-c3a0-4e6b-9175-b287cef37c2e
\.


--
-- Data for Name: quiz_questions; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.quiz_questions (id, course_id, quiz_id, "position", kind, prompt, options, correct, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.refresh_tokens (id, user_id, jti, token_hash, issued_at, expires_at, rotated_at, revoked_at, last_used_at) FROM stdin;
9fbc9f57-c2fa-4420-a644-28c87ac217f5	7ca432db-1c03-45b5-be38-54d3f6c4da4b	b5de0084-c020-4412-9a1c-10ba4fef5d9b	ee5aadbfe985e04c6ab65e49abd35ce7d52b2fbb6be6c9c20d494424d3c0257d	2025-10-08 18:07:38.473723+00	2025-10-09 18:07:38.473572+00	\N	\N	2025-10-08 18:07:38.473723+00
9a74ae20-663b-491c-819e-f0b1eaf01bde	00be7360-eb04-4f39-8904-555306509417	85df469b-c5df-41aa-b1c4-ad6b3fb24237	d10c60a6f6a015844966d07fe556c411c98b24986c49d15703e5b1da8c4d2323	2025-10-08 18:07:38.786553+00	2025-10-09 18:07:38.786477+00	\N	\N	2025-10-08 18:07:38.786553+00
c9e3c1f7-2f0b-4b6d-a896-bc8d8f9f5e3c	c4505a51-1f7f-4c09-affd-9b91f52084b8	adadd98a-a0fd-4f34-b5ff-2d81c6758442	f282b524ff3b80039a8370a85cadc27bb0081d3a4f77790e46490fbef383e4f8	2025-10-08 18:07:39.038724+00	2025-10-09 18:07:39.038559+00	\N	\N	2025-10-08 18:07:39.038724+00
18236a63-2f0b-41a2-8b59-d26eeaccb9e3	df22e24e-25fe-43b3-b7f2-3734019f80e8	b229ad65-6cd8-42e6-917a-b4731d97ee03	bab7fd770a96419c7fa9cd37b058c435e8fb3bfa2cce7fdb57ff0dc43d50e747	2025-10-08 18:07:39.289813+00	2025-10-09 18:07:39.289742+00	\N	\N	2025-10-08 18:07:39.289813+00
2b7e93ba-ff0e-4ea5-b585-7a789a975363	3e7468d4-c413-4af4-8320-b01b9f5eb786	1b2cd8e0-c332-4aef-933d-89241bb2610e	217d3a8c99d12e68f8f107f88e6138bb80986e008b2f9f348abeeb9fa1484ad9	2025-10-08 18:07:39.542022+00	2025-10-09 18:07:39.541951+00	\N	\N	2025-10-08 18:07:39.542022+00
dc4494ad-3b16-4740-8ff1-7b3a92bb2cb1	703977ae-ee67-4567-8737-2df9eafa0b4d	3f1c0a38-84af-46f0-b206-1c83ea85e598	6b2ad8b74e7fd56cba55025c66f358b0c798fdf4b53c7cfe40952ed995120c4b	2025-10-08 18:09:25.779262+00	2025-10-09 18:09:25.779036+00	\N	\N	2025-10-08 18:09:25.779262+00
86c33d1a-76cc-42b3-8e34-71fa97aa2941	1d7ef616-6c3a-452e-bcaa-bfd9b41a9c35	41cf59ed-c129-4c13-a7b9-9c91b0129474	1f7dd4107bb3104d95aa0892f3af2f256b61234a5f27c7415acd646f72298c54	2025-10-08 18:10:39.813465+00	2025-10-09 18:10:39.813343+00	2025-10-08 18:10:39.817203+00	\N	2025-10-08 18:10:39.817203+00
6b5907b9-7972-43c4-bdc1-ba009ab1cb06	1d7ef616-6c3a-452e-bcaa-bfd9b41a9c35	42afdda8-5524-48b0-8fb5-e90f24473548	eb248298847647ce30681a39d37b58dae84aea98efc31d61b6522aa6c4b715cc	2025-10-08 18:10:39.818497+00	2025-10-09 18:10:39.818442+00	\N	\N	2025-10-08 18:10:39.818497+00
0b5aa98c-eecf-47be-b30a-6b5c34db4c7f	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	ec83e5a7-6d8d-4666-852d-b83276ccb004	246ce7c4532d9841b8f0645a49c19c99708511dd35a64e852521d91637e2358c	2025-10-08 18:18:16.911194+00	2025-10-09 18:18:16.911042+00	2025-10-08 18:34:12.18538+00	\N	2025-10-08 18:34:12.18538+00
3dd95b32-d7de-43c4-8028-9631650340e7	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	e12d908c-daed-4137-946f-1048a4e91b69	f34638c5f5d2d57e62f7f83457efb27892c0082fa6979898e3899886c6d93266	2025-10-08 18:34:12.189718+00	2025-10-09 18:34:12.189649+00	2025-10-08 19:09:36.448819+00	\N	2025-10-08 19:09:36.448819+00
8beb1197-99ea-43a5-9f20-9259376e0b27	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	6ae7423e-223c-4f9a-84a0-25ca3f8b301d	d5c853fa718420b550cb2cc661d0e60e1701476dc8d88f2bcad4dc363b8981fd	2025-10-08 19:09:36.450603+00	2025-10-09 19:09:36.450519+00	2025-10-08 19:24:51.046069+00	\N	2025-10-08 19:24:51.046069+00
402bbb97-a0a2-43bf-9387-f071d8773fad	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	400e8941-65ea-4d3f-af45-b2dbe4bdaa2e	4a97219a5bb49d784a86aea625268312e1da93efeb4eae22024042d668a70412	2025-10-08 19:24:51.048876+00	2025-10-09 19:24:51.04879+00	2025-10-08 20:11:13.171545+00	\N	2025-10-08 20:11:13.171545+00
77b1f23f-c071-45d4-aca9-4f38f12a50f9	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	118dfdd5-03b0-4e1b-88ac-e9c78c3260e1	93f924ffdb8348287f68858902b4b4c499485f65bbaf6caf3308d87f784ef273	2025-10-08 20:11:13.174276+00	2025-10-09 20:11:13.174148+00	2025-10-08 20:33:29.023935+00	\N	2025-10-08 20:33:29.023935+00
1cbc7a9a-ac77-44e1-a01d-536fe2ec78de	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	8b7114de-c025-4cf5-ab58-0cf6df524337	ef75e9e59b2637ed09ba79cd86e4a14bf288f622c88aa14cd4c597cc8baf4c1c	2025-10-08 20:33:29.028041+00	2025-10-09 20:33:29.027956+00	\N	\N	2025-10-08 20:33:29.028041+00
3ac6ea30-24e0-43eb-924c-83cee1931a3c	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	373d8149-934c-41c2-abf8-73896a50718d	778c570ef63bb79e24fec8d5b0c7b7732cba1e2a0de1011b1f912a58e0117681	2025-10-08 20:55:35.771506+00	2025-10-09 20:55:35.771081+00	2025-10-08 21:39:17.858772+00	\N	2025-10-08 21:39:17.858772+00
6d93c021-f1fc-4790-babe-a21876c39a68	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	7e187a9f-8fd8-4a63-9de1-f2a5b9998657	3197e1d06ccc7fcd13f0203d99d91fbde61084d130e5c941dda3280c003dd36f	2025-10-08 21:39:17.861361+00	2025-10-09 21:39:17.861209+00	2025-10-08 22:03:38.443185+00	\N	2025-10-08 22:03:38.443185+00
0e151f6a-4d95-4114-8e6d-dac976b84917	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	bda23166-eb8b-4522-874c-e9bd073f41a1	34e478f47b763c7de60458183b325404cd19ce00cda9dc70db3dcfb49f8a7fda	2025-10-08 22:03:38.446132+00	2025-10-09 22:03:38.445984+00	2025-10-08 22:30:37.74555+00	\N	2025-10-08 22:30:37.74555+00
03850d6c-9f5e-484c-b751-1c8b6ad3a885	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	a16a1265-2191-4ece-96e9-d6ede4b7b0eb	672164837680e387d47337167cfb7417a1f753f41d613a1ee166a3560eb43a77	2025-10-08 22:30:37.747597+00	2025-10-09 22:30:37.747528+00	2025-10-08 22:56:37.603778+00	\N	2025-10-08 22:56:37.603778+00
f347a160-5224-436d-a6c9-7d37ac863037	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	b1397a20-523a-4ba9-92bd-d533f8a3da7c	e20670e96e403f43983de80edafbd6f006ec4232161bbe5006bdc57c9ab7077d	2025-10-08 22:56:37.605552+00	2025-10-09 22:56:37.605491+00	2025-10-08 23:47:49.86667+00	\N	2025-10-08 23:47:49.86667+00
cdf88835-7bc3-4777-9712-1d6b6b0d4ce3	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	c0d1bc08-3124-4790-8562-b98bfb851441	62118417da194a448dbe5cc271e3edc4bee7157a3ea7c7b4896b84930a5b4be5	2025-10-08 23:47:49.873165+00	2025-10-09 23:47:49.873029+00	2025-10-09 00:03:24.997737+00	\N	2025-10-09 00:03:24.997737+00
789c8b34-8382-41fa-9a84-577b559a7925	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	9326b8f3-9da9-4e5b-b70a-1a18c67a9055	5c0f21e3139777ddd62544cbd75b7081148b5deedea7ee1888d4bf2fb178c74f	2025-10-09 00:03:25.000724+00	2025-10-10 00:03:25.000653+00	\N	\N	2025-10-09 00:03:25.000724+00
\.


--
-- Data for Name: reviews; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.reviews (id, course_id, service_id, reviewer_id, rating, comment, visibility, created_at) FROM stdin;
\.


--
-- Data for Name: seminar_attendees; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.seminar_attendees (seminar_id, user_id, role, joined_at, created_at) FROM stdin;
99999999-9999-4999-8999-999999999999	22222222-2222-4222-8222-222222222222	participant	\N	2025-10-08 18:04:03.310975+00
\.


--
-- Data for Name: seminars; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.seminars (id, host_id, title, description, status, scheduled_at, duration_minutes, livekit_room, livekit_metadata, recording_url, created_at, updated_at) FROM stdin;
99999999-9999-4999-8999-999999999999	11111111-1111-4111-8111-111111111111	Morning Presence Circle	Live group practice to sync breath, intention and gratitude.	scheduled	2025-10-11 18:04:03.310975+00	45	aveli-morning-presence	{"seed": true}	\N	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
\.


--
-- Data for Name: service_reviews; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.service_reviews (id, service_id, order_id, reviewer_id, rating, comment, visibility, created_at) FROM stdin;
cccccccc-cccc-4ccc-8ccc-cccccccccccc	66666666-6666-4666-8666-666666666666	77777777-7777-4777-8777-777777777777	22222222-2222-4222-8222-222222222222	5	A grounding experience that left me energized and clear.	public	2025-10-08 18:04:03.310975+00
\.


--
-- Data for Name: services; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.services (id, provider_id, title, description, status, price_cents, currency, duration_min, requires_certification, certified_area, active, created_at, updated_at) FROM stdin;
66666666-6666-4666-8666-666666666666	11111111-1111-4111-8111-111111111111	1:1 Integration Coaching	Personalized session to integrate insights from your daily practice.	active	12000	sek	60	f	\N	t	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
\.


--
-- Data for Name: stripe_customers; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.stripe_customers (user_id, customer_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: tarot_requests; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.tarot_requests (id, requester_id, question, status, created_at) FROM stdin;
\.


--
-- Data for Name: teacher_approvals; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.teacher_approvals (id, user_id, reviewer_id, status, notes, approved_by, approved_at, created_at, updated_at) FROM stdin;
3a57f120-795a-4a1a-9e6b-8eb18369a34e	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	\N	pending	\N	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	2025-10-08 19:20:08.400835+00	2025-10-08 19:20:08.400835+00	2025-10-08 19:20:08.400835+00
\.


--
-- Data for Name: teacher_directory; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.teacher_directory (user_id, headline, specialties, rating, created_at) FROM stdin;
\.


--
-- Data for Name: teacher_payout_methods; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.teacher_payout_methods (id, teacher_id, provider, reference, details, is_default, created_at, updated_at) FROM stdin;
dddddddd-dddd-4ddd-8ddd-dddddddddddd	11111111-1111-4111-8111-111111111111	stripe_connect	acct_seed_teacher	{"account_id": "acct_seed_teacher"}	t	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
\.


--
-- Data for Name: teacher_permissions; Type: TABLE DATA; Schema: app; Owner: -
--

COPY app.teacher_permissions (profile_id, can_edit_courses, can_publish, granted_by, granted_at) FROM stdin;
1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	t	t	1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	2025-10-08 19:20:08.399349+00
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.users (id, email, encrypted_password, full_name, is_verified, created_at, updated_at) FROM stdin;
11111111-1111-4111-8111-111111111111	teacher@aveli.local	$2a$06$jNdHXJWc6cwMGDORHzgFweyCatH9zk4XBgWmKIdxiG6X3E/hcJiTq	Teacher Aveli	t	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
22222222-2222-4222-8222-222222222222	student@aveli.local	$2a$06$McY46/Blyfq91dKtDr7WCOih3s0e6A3jh49mOqoIlENf.Ip5z3QAq	Student Soul	t	2025-10-08 18:04:03.310975+00	2025-10-08 18:04:03.310975+00
7ca432db-1c03-45b5-be38-54d3f6c4da4b	admin_f3bcaf18@example.com	$2b$12$/ziR4i6ooerkew0RxGOkxutF9xAg9G5buxrKzs42ZrwdQiTwEVRR6	Admin	t	2025-10-08 18:07:38.463013+00	2025-10-08 18:07:38.463013+00
00be7360-eb04-4f39-8904-555306509417	smoke_59ded8@aveli.local	$2b$12$COkTkrX2GGI/BNVoIQSzp.TTTvAtpFWL6T4MFojNW2nWPhV3/NjSq	Smoke Tester	t	2025-10-08 18:07:38.780499+00	2025-10-08 18:07:38.780499+00
c4505a51-1f7f-4c09-affd-9b91f52084b8	student_c27c8ed2@example.com	$2b$12$6mfECLHxOy.sMS3vMoqOTuhU.neSC89ySuCR8AzpNhzYwqDkXa2R.	Student	t	2025-10-08 18:07:39.033446+00	2025-10-08 18:07:39.033446+00
df22e24e-25fe-43b3-b7f2-3734019f80e8	teacher_937efb4f@example.com	$2b$12$FiiVH6GaeL.UoiHXzYMvGeOuqMtrvXgjqCILWPzdiyd8hR6dAiQia	Teacher	t	2025-10-08 18:07:39.283855+00	2025-10-08 18:07:39.283855+00
3e7468d4-c413-4af4-8320-b01b9f5eb786	teacher_08b468e4@example.com	$2b$12$MHgFELHGn9XblMOQFPgTseEneXErGw6iiBDwzvukU9mH0WbR3pN5y	Teacher	t	2025-10-08 18:07:39.536914+00	2025-10-08 18:07:39.536914+00
703977ae-ee67-4567-8737-2df9eafa0b4d	smoke_099477@aveli.local	$2b$12$Edy7ccvkStUPpBJjP.BRpe1gz1jgrDlwGbNHtnbjzOVYvvFXteD46	Smoke Tester	t	2025-10-08 18:09:25.770938+00	2025-10-08 18:09:25.770938+00
1d7ef616-6c3a-452e-bcaa-bfd9b41a9c35	smoke_ea8e6f@aveli.local	$2b$12$eGjNYowvPiJ4lG1laXDU9.Et3DB7InA6alA4PuG7eaVdi61/PSYN.	Smoke Tester	t	2025-10-08 18:10:39.804935+00	2025-10-08 18:10:39.804935+00
1f4da975-f6e0-4d12-99f3-e8b9ee9f1bc6	odenhjalm@outlook.com	$2a$10$vFDncKIY8UZqpe45hk0FvOnIg7ffvW3n2Jc64zXTcnVMrrvWeMsKq	Oden Hjalm	t	2025-10-08 18:14:33.381913+00	2025-10-08 18:14:33.381913+00
\.


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: app_config app_config_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (id);


--
-- Name: auth_events auth_events_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.auth_events
    ADD CONSTRAINT auth_events_pkey PRIMARY KEY (id);


--
-- Name: certificates certificates_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.certificates
    ADD CONSTRAINT certificates_pkey PRIMARY KEY (id);


--
-- Name: course_quizzes course_quizzes_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.course_quizzes
    ADD CONSTRAINT course_quizzes_pkey PRIMARY KEY (id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: courses courses_slug_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.courses
    ADD CONSTRAINT courses_slug_key UNIQUE (slug);


--
-- Name: enrollments enrollments_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_user_id_course_id_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_user_id_course_id_key UNIQUE (user_id, course_id);


--
-- Name: follows follows_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.follows
    ADD CONSTRAINT follows_pkey PRIMARY KEY (follower_id, followee_id);


--
-- Name: lesson_media lesson_media_lesson_id_position_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_lesson_id_position_key UNIQUE (lesson_id, "position");


--
-- Name: lesson_media lesson_media_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_pkey PRIMARY KEY (id);


--
-- Name: lessons lessons_module_id_position_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.lessons
    ADD CONSTRAINT lessons_module_id_position_key UNIQUE (module_id, "position");


--
-- Name: lessons lessons_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.lessons
    ADD CONSTRAINT lessons_pkey PRIMARY KEY (id);


--
-- Name: media_objects media_objects_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.media_objects
    ADD CONSTRAINT media_objects_pkey PRIMARY KEY (id);


--
-- Name: media_objects media_objects_storage_path_storage_bucket_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.media_objects
    ADD CONSTRAINT media_objects_storage_path_storage_bucket_key UNIQUE (storage_path, storage_bucket);


--
-- Name: meditations meditations_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.meditations
    ADD CONSTRAINT meditations_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: modules modules_course_id_position_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.modules
    ADD CONSTRAINT modules_course_id_position_key UNIQUE (course_id, "position");


--
-- Name: modules modules_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.modules
    ADD CONSTRAINT modules_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_email_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_email_key UNIQUE (email);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (user_id);


--
-- Name: quiz_questions quiz_questions_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.quiz_questions
    ADD CONSTRAINT quiz_questions_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_jti_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.refresh_tokens
    ADD CONSTRAINT refresh_tokens_jti_key UNIQUE (jti);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: seminar_attendees seminar_attendees_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.seminar_attendees
    ADD CONSTRAINT seminar_attendees_pkey PRIMARY KEY (seminar_id, user_id);


--
-- Name: seminars seminars_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.seminars
    ADD CONSTRAINT seminars_pkey PRIMARY KEY (id);


--
-- Name: service_reviews service_reviews_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_pkey PRIMARY KEY (id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: stripe_customers stripe_customers_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.stripe_customers
    ADD CONSTRAINT stripe_customers_pkey PRIMARY KEY (user_id);


--
-- Name: tarot_requests tarot_requests_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tarot_requests
    ADD CONSTRAINT tarot_requests_pkey PRIMARY KEY (id);


--
-- Name: teacher_approvals teacher_approvals_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_pkey PRIMARY KEY (id);


--
-- Name: teacher_approvals teacher_approvals_user_id_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_user_id_key UNIQUE (user_id);


--
-- Name: teacher_directory teacher_directory_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_directory
    ADD CONSTRAINT teacher_directory_pkey PRIMARY KEY (user_id);


--
-- Name: teacher_payout_methods teacher_payout_methods_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_payout_methods
    ADD CONSTRAINT teacher_payout_methods_pkey PRIMARY KEY (id);


--
-- Name: teacher_payout_methods teacher_payout_methods_teacher_id_provider_reference_key; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_payout_methods
    ADD CONSTRAINT teacher_payout_methods_teacher_id_provider_reference_key UNIQUE (teacher_id, provider, reference);


--
-- Name: teacher_permissions teacher_permissions_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_permissions
    ADD CONSTRAINT teacher_permissions_pkey PRIMARY KEY (profile_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_activities_occurred; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_activities_occurred ON app.activities USING btree (occurred_at DESC);


--
-- Name: idx_activities_subject; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_activities_subject ON app.activities USING btree (subject_table, subject_id);


--
-- Name: idx_activities_type; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_activities_type ON app.activities USING btree (activity_type);


--
-- Name: idx_auth_events_created_at; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_auth_events_created_at ON app.auth_events USING btree (created_at DESC);


--
-- Name: idx_auth_events_user; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_auth_events_user ON app.auth_events USING btree (user_id);


--
-- Name: idx_certificates_user; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_certificates_user ON app.certificates USING btree (user_id);


--
-- Name: idx_courses_created_by; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_courses_created_by ON app.courses USING btree (created_by);


--
-- Name: idx_enrollments_course; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_enrollments_course ON app.enrollments USING btree (course_id);


--
-- Name: idx_enrollments_user; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_enrollments_user ON app.enrollments USING btree (user_id);


--
-- Name: idx_lesson_media_lesson; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_lesson_media_lesson ON app.lesson_media USING btree (lesson_id);


--
-- Name: idx_lesson_media_media; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_lesson_media_media ON app.lesson_media USING btree (media_id);


--
-- Name: idx_lessons_module; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_lessons_module ON app.lessons USING btree (module_id);


--
-- Name: idx_media_owner; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_media_owner ON app.media_objects USING btree (owner_id);


--
-- Name: idx_messages_channel; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_messages_channel ON app.messages USING btree (channel);


--
-- Name: idx_messages_recipient; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_messages_recipient ON app.messages USING btree (recipient_id);


--
-- Name: idx_modules_course; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_modules_course ON app.modules USING btree (course_id);


--
-- Name: idx_notifications_read; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_notifications_read ON app.notifications USING btree (user_id, read_at);


--
-- Name: idx_notifications_user; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_notifications_user ON app.notifications USING btree (user_id);


--
-- Name: idx_orders_course; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_orders_course ON app.orders USING btree (course_id);


--
-- Name: idx_orders_service; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_orders_service ON app.orders USING btree (service_id);


--
-- Name: idx_orders_status; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_orders_status ON app.orders USING btree (status);


--
-- Name: idx_orders_user; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_orders_user ON app.orders USING btree (user_id);


--
-- Name: idx_payments_order; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_payments_order ON app.payments USING btree (order_id);


--
-- Name: idx_payments_status; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_payments_status ON app.payments USING btree (status);


--
-- Name: idx_payout_methods_teacher; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_payout_methods_teacher ON app.teacher_payout_methods USING btree (teacher_id);


--
-- Name: idx_posts_author; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_posts_author ON app.posts USING btree (author_id);


--
-- Name: idx_quiz_questions_course; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_quiz_questions_course ON app.quiz_questions USING btree (course_id);


--
-- Name: idx_quiz_questions_quiz; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_quiz_questions_quiz ON app.quiz_questions USING btree (quiz_id);


--
-- Name: idx_refresh_tokens_user; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_refresh_tokens_user ON app.refresh_tokens USING btree (user_id);


--
-- Name: idx_reviews_course; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_reviews_course ON app.reviews USING btree (course_id);


--
-- Name: idx_reviews_reviewer; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_reviews_reviewer ON app.reviews USING btree (reviewer_id);


--
-- Name: idx_reviews_service; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_reviews_service ON app.reviews USING btree (service_id);


--
-- Name: idx_seminars_host; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_seminars_host ON app.seminars USING btree (host_id);


--
-- Name: idx_seminars_scheduled_at; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_seminars_scheduled_at ON app.seminars USING btree (scheduled_at);


--
-- Name: idx_seminars_status; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_seminars_status ON app.seminars USING btree (status);


--
-- Name: idx_service_reviews_reviewer; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_service_reviews_reviewer ON app.service_reviews USING btree (reviewer_id);


--
-- Name: idx_service_reviews_service; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_service_reviews_service ON app.service_reviews USING btree (service_id);


--
-- Name: idx_services_provider; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_services_provider ON app.services USING btree (provider_id);


--
-- Name: idx_services_status; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_services_status ON app.services USING btree (status);


--
-- Name: idx_teacher_approvals_user; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_teacher_approvals_user ON app.teacher_approvals USING btree (user_id);


--
-- Name: idx_auth_users_email_lower; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_auth_users_email_lower ON auth.users USING btree (lower(email));


--
-- Name: courses trg_courses_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_courses_touch BEFORE UPDATE ON app.courses FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: lessons trg_lessons_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_lessons_touch BEFORE UPDATE ON app.lessons FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: modules trg_modules_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_modules_touch BEFORE UPDATE ON app.modules FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: orders trg_orders_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON app.orders FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: payments trg_payments_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_payments_touch BEFORE UPDATE ON app.payments FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: seminars trg_seminars_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_seminars_touch BEFORE UPDATE ON app.seminars FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: services trg_services_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_services_touch BEFORE UPDATE ON app.services FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: teacher_payout_methods trg_teacher_payout_methods_touch; Type: TRIGGER; Schema: app; Owner: -
--

CREATE TRIGGER trg_teacher_payout_methods_touch BEFORE UPDATE ON app.teacher_payout_methods FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


--
-- Name: activities activities_actor_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.activities
    ADD CONSTRAINT activities_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: auth_events auth_events_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.auth_events
    ADD CONSTRAINT auth_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: certificates certificates_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.certificates
    ADD CONSTRAINT certificates_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL;


--
-- Name: certificates certificates_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.certificates
    ADD CONSTRAINT certificates_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: course_quizzes course_quizzes_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.course_quizzes
    ADD CONSTRAINT course_quizzes_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: course_quizzes course_quizzes_created_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.course_quizzes
    ADD CONSTRAINT course_quizzes_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: courses courses_created_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.courses
    ADD CONSTRAINT courses_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: enrollments enrollments_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: enrollments enrollments_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.enrollments
    ADD CONSTRAINT enrollments_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: follows follows_followee_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.follows
    ADD CONSTRAINT follows_followee_id_fkey FOREIGN KEY (followee_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: follows follows_follower_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.follows
    ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: lesson_media lesson_media_lesson_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES app.lessons(id) ON DELETE CASCADE;


--
-- Name: lesson_media lesson_media_media_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.lesson_media
    ADD CONSTRAINT lesson_media_media_id_fkey FOREIGN KEY (media_id) REFERENCES app.media_objects(id) ON DELETE SET NULL;


--
-- Name: lessons lessons_module_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.lessons
    ADD CONSTRAINT lessons_module_id_fkey FOREIGN KEY (module_id) REFERENCES app.modules(id) ON DELETE CASCADE;


--
-- Name: media_objects media_objects_owner_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.media_objects
    ADD CONSTRAINT media_objects_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: meditations meditations_created_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.meditations
    ADD CONSTRAINT meditations_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: meditations meditations_media_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.meditations
    ADD CONSTRAINT meditations_media_id_fkey FOREIGN KEY (media_id) REFERENCES app.media_objects(id) ON DELETE SET NULL;


--
-- Name: meditations meditations_teacher_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.meditations
    ADD CONSTRAINT meditations_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: messages messages_recipient_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.messages
    ADD CONSTRAINT messages_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: modules modules_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.modules
    ADD CONSTRAINT modules_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: orders orders_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE SET NULL;


--
-- Name: orders orders_service_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_service_id_fkey FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE SET NULL;


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: payments payments_order_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.payments
    ADD CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE CASCADE;


--
-- Name: posts posts_author_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.posts
    ADD CONSTRAINT posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: profiles profiles_avatar_media_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_avatar_media_id_fkey FOREIGN KEY (avatar_media_id) REFERENCES app.media_objects(id);


--
-- Name: profiles profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.profiles
    ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: quiz_questions quiz_questions_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.quiz_questions
    ADD CONSTRAINT quiz_questions_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: quiz_questions quiz_questions_quiz_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.quiz_questions
    ADD CONSTRAINT quiz_questions_quiz_id_fkey FOREIGN KEY (quiz_id) REFERENCES app.course_quizzes(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: reviews reviews_course_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_course_id_fkey FOREIGN KEY (course_id) REFERENCES app.courses(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: reviews reviews_service_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.reviews
    ADD CONSTRAINT reviews_service_id_fkey FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE CASCADE;


--
-- Name: seminar_attendees seminar_attendees_seminar_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.seminar_attendees
    ADD CONSTRAINT seminar_attendees_seminar_id_fkey FOREIGN KEY (seminar_id) REFERENCES app.seminars(id) ON DELETE CASCADE;


--
-- Name: seminar_attendees seminar_attendees_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.seminar_attendees
    ADD CONSTRAINT seminar_attendees_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: seminars seminars_host_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.seminars
    ADD CONSTRAINT seminars_host_id_fkey FOREIGN KEY (host_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: service_reviews service_reviews_order_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_order_id_fkey FOREIGN KEY (order_id) REFERENCES app.orders(id) ON DELETE SET NULL;


--
-- Name: service_reviews service_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id) ON DELETE SET NULL;


--
-- Name: service_reviews service_reviews_service_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.service_reviews
    ADD CONSTRAINT service_reviews_service_id_fkey FOREIGN KEY (service_id) REFERENCES app.services(id) ON DELETE CASCADE;


--
-- Name: services services_provider_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.services
    ADD CONSTRAINT services_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: stripe_customers stripe_customers_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.stripe_customers
    ADD CONSTRAINT stripe_customers_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: tarot_requests tarot_requests_requester_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tarot_requests
    ADD CONSTRAINT tarot_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_approvals teacher_approvals_approved_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES app.profiles(user_id);


--
-- Name: teacher_approvals teacher_approvals_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES app.profiles(user_id);


--
-- Name: teacher_approvals teacher_approvals_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_approvals
    ADD CONSTRAINT teacher_approvals_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_directory teacher_directory_user_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_directory
    ADD CONSTRAINT teacher_directory_user_id_fkey FOREIGN KEY (user_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_payout_methods teacher_payout_methods_teacher_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_payout_methods
    ADD CONSTRAINT teacher_payout_methods_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- Name: teacher_permissions teacher_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_permissions
    ADD CONSTRAINT teacher_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES app.profiles(user_id);


--
-- Name: teacher_permissions teacher_permissions_profile_id_fkey; Type: FK CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.teacher_permissions
    ADD CONSTRAINT teacher_permissions_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES app.profiles(user_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict UwadLlUJMIkDO97d4caafylDXxFjntglsF2yWDccNA1zSpsWiN8d7xwu7iy6JO3

