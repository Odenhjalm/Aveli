-- Deterministic local playback/access fixtures.
-- Fixture password (for auth.users.encrypted_password):
--   FixturePass123!

INSERT INTO auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
SELECT
  '11111111-1111-4111-8111-111111111111'::uuid,
  'authenticated',
  'authenticated',
  'playback.fixture@aveli.local',
  '$bcrypt-sha256$v=2,t=2b,r=12$nY1BFBijN4DekQp2awrK6u$rMKiQTj5ALz.aqDcRrCzff.BPMqS2CC',
  timezone('utc', now()),
  jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
  jsonb_build_object('display_name', 'Playback Fixture User'),
  timezone('utc', now()),
  timezone('utc', now()),
  false,
  false
WHERE NOT EXISTS (
  SELECT 1
  FROM auth.users
  WHERE id = '11111111-1111-4111-8111-111111111111'::uuid
     OR lower(email) = lower('playback.fixture@aveli.local')
);

INSERT INTO app.profiles (
  user_id,
  email,
  display_name,
  role,
  role_v2,
  is_admin,
  created_at,
  updated_at,
  onboarding_state
)
SELECT
  '11111111-1111-4111-8111-111111111111'::uuid,
  'playback.fixture@aveli.local',
  'Playback Fixture User',
  'student'::app.profile_role,
  'user'::app.user_role,
  false,
  timezone('utc', now()),
  timezone('utc', now()),
  'access_active_profile_complete'
WHERE EXISTS (
  SELECT 1
  FROM auth.users
  WHERE id = '11111111-1111-4111-8111-111111111111'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM app.profiles
  WHERE user_id = '11111111-1111-4111-8111-111111111111'::uuid
     OR lower(email) = lower('playback.fixture@aveli.local')
);

INSERT INTO app.media_objects (
  id,
  owner_id,
  storage_path,
  storage_bucket,
  content_type,
  byte_size,
  checksum,
  original_name,
  created_at,
  updated_at
)
SELECT
  '44444444-4444-4444-8444-444444444444'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  'fixtures/playback/audio.mp3',
  'lesson-media',
  'audio/mpeg',
  12345,
  'fixture-audio-checksum',
  'audio.mp3',
  timezone('utc', now()),
  timezone('utc', now())
WHERE EXISTS (
  SELECT 1
  FROM app.profiles
  WHERE user_id = '11111111-1111-4111-8111-111111111111'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM app.media_objects
  WHERE id = '44444444-4444-4444-8444-444444444444'::uuid
     OR (storage_path = 'fixtures/playback/audio.mp3' AND storage_bucket = 'lesson-media')
);

INSERT INTO app.courses (
  id,
  slug,
  title,
  description,
  is_free_intro,
  price_cents,
  currency,
  is_published,
  created_by,
  created_at,
  updated_at,
  price_amount_cents,
  journey_step,
  is_test,
  test_session_id
)
SELECT
  '22222222-2222-4222-8222-222222222222'::uuid,
  'playback-fixture-course',
  'Playback Fixture Course',
  'Deterministic course fixture for playback enforcement tests.',
  false,
  0,
  'sek',
  true,
  '11111111-1111-4111-8111-111111111111'::uuid,
  timezone('utc', now()),
  timezone('utc', now()),
  0,
  'intro',
  false,
  NULL
WHERE EXISTS (
  SELECT 1
  FROM app.profiles
  WHERE user_id = '11111111-1111-4111-8111-111111111111'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM app.courses
  WHERE id = '22222222-2222-4222-8222-222222222222'::uuid
     OR slug = 'playback-fixture-course'
);

INSERT INTO app.lessons (
  id,
  title,
  content_markdown,
  duration_seconds,
  is_intro,
  "position",
  created_at,
  updated_at,
  price_amount_cents,
  price_currency,
  course_id,
  is_test,
  test_session_id
)
SELECT
  '33333333-3333-4333-8333-333333333333'::uuid,
  'Playback Fixture Lesson',
  'Deterministic lesson fixture.',
  60,
  false,
  1,
  timezone('utc', now()),
  timezone('utc', now()),
  0,
  'sek',
  '22222222-2222-4222-8222-222222222222'::uuid,
  false,
  NULL
WHERE EXISTS (
  SELECT 1
  FROM app.courses
  WHERE id = '22222222-2222-4222-8222-222222222222'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM app.lessons
  WHERE id = '33333333-3333-4333-8333-333333333333'::uuid
);

INSERT INTO app.lesson_media (
  id,
  lesson_id,
  kind,
  media_id,
  duration_seconds,
  "position",
  created_at,
  media_asset_id,
  is_test,
  test_session_id
)
SELECT
  '55555555-5555-4555-8555-555555555555'::uuid,
  '33333333-3333-4333-8333-333333333333'::uuid,
  'audio',
  '44444444-4444-4444-8444-444444444444'::uuid,
  60,
  1,
  timezone('utc', now()),
  NULL,
  false,
  NULL
WHERE EXISTS (
  SELECT 1
  FROM app.lessons
  WHERE id = '33333333-3333-4333-8333-333333333333'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM app.lesson_media
  WHERE id = '55555555-5555-4555-8555-555555555555'::uuid
     OR (lesson_id = '33333333-3333-4333-8333-333333333333'::uuid AND "position" = 1)
);

INSERT INTO app.runtime_media (
  id,
  lesson_media_id,
  home_player_upload_id,
  media_asset_id,
  media_object_id,
  lesson_id,
  course_id,
  teacher_id,
  reference_type,
  auth_scope,
  fallback_policy,
  active,
  is_test,
  test_session_id,
  created_at,
  updated_at
)
SELECT
  '66666666-6666-4666-8666-666666666666'::uuid,
  '55555555-5555-4555-8555-555555555555'::uuid,
  NULL,
  NULL,
  '44444444-4444-4444-8444-444444444444'::uuid,
  '33333333-3333-4333-8333-333333333333'::uuid,
  '22222222-2222-4222-8222-222222222222'::uuid,
  NULL,
  'lesson_media'::app.runtime_media_reference_type,
  'lesson_course'::app.runtime_media_auth_scope,
  'never'::app.runtime_media_fallback_policy,
  true,
  false,
  NULL,
  timezone('utc', now()),
  timezone('utc', now())
WHERE EXISTS (
  SELECT 1
  FROM app.lesson_media
  WHERE id = '55555555-5555-4555-8555-555555555555'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM app.runtime_media
  WHERE id = '66666666-6666-4666-8666-666666666666'::uuid
     OR (lesson_media_id = '55555555-5555-4555-8555-555555555555'::uuid AND active = true)
);

INSERT INTO app.entitlements (
  id,
  user_id,
  course_id,
  source,
  stripe_session_id,
  created_at
)
SELECT
  '77777777-7777-4777-8777-777777777777'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '22222222-2222-4222-8222-222222222222'::uuid,
  'manual',
  NULL,
  timezone('utc', now())
WHERE EXISTS (
  SELECT 1
  FROM app.courses
  WHERE id = '22222222-2222-4222-8222-222222222222'::uuid
)
AND EXISTS (
  SELECT 1
  FROM app.profiles
  WHERE user_id = '11111111-1111-4111-8111-111111111111'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM app.entitlements
  WHERE id = '77777777-7777-4777-8777-777777777777'::uuid
     OR (
       user_id = '11111111-1111-4111-8111-111111111111'::uuid
       AND course_id = '22222222-2222-4222-8222-222222222222'::uuid
     )
);
