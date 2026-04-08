ALTER TABLE app.profiles
  ADD COLUMN IF NOT EXISTS onboarding_state text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'profiles_onboarding_state_check'
       AND conrelid = 'app.profiles'::regclass
  ) THEN
    ALTER TABLE app.profiles
      ADD CONSTRAINT profiles_onboarding_state_check
      CHECK (
        onboarding_state IS NULL OR onboarding_state IN (
          'registered_unverified',
          'verified_unpaid',
          'access_active_profile_incomplete',
          'access_active_profile_complete',
          'welcomed'
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_onboarding_state
  ON app.profiles (onboarding_state);

UPDATE app.profiles
   SET onboarding_state = 'welcomed'
 WHERE user_id IN (
   SELECT user_id
     FROM app.memberships
    WHERE status IN ('active', 'trialing', 'referral')
 );

UPDATE app.profiles
   SET onboarding_state = 'verified_unpaid'
 WHERE onboarding_state IS NULL
   AND user_id IN (
     SELECT id
       FROM auth.users
      WHERE email_confirmed_at IS NOT NULL
   );

UPDATE app.profiles
   SET onboarding_state = 'registered_unverified'
 WHERE onboarding_state IS NULL;
