-- Add provider fields to profiles
ALTER TABLE app.profiles
    ADD COLUMN IF NOT EXISTS provider_name text,
    ADD COLUMN IF NOT EXISTS provider_user_id text,
    ADD COLUMN IF NOT EXISTS provider_email_verified boolean,
    ADD COLUMN IF NOT EXISTS provider_avatar_url text,
    ADD COLUMN IF NOT EXISTS last_login_provider text,
    ADD COLUMN IF NOT EXISTS last_login_at timestamptz;

