# Schema Drift Report

## Schema drift (auth/app)
- Issues: auth.users: extra columns in DB -> aud, banned_until, confirmation_sent_at, confirmation_token, confirmed_at, created_at, deleted_at, email, email_change, email_change_confirm_status, email_change_sent_at, email_change_token_current, email_change_token_new, email_confirmed_at, encrypted_password, id, instance_id, invited_at, is_anonymous, is_sso_user, is_super_admin, last_sign_in_at, phone, phone_change, phone_change_sent_at, phone_change_token, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, reauthentication_sent_at, reauthentication_token, recovery_sent_at, recovery_token, role, updated_at; app.profiles: extra columns in DB -> avatar_media_id, bio, created_at, display_name, email, is_admin, photo_url, role, role_v2, stripe_customer_id, updated_at, user_id
- Actions: Proposed migration: /home/oden/Aveli/supabase/migrations/autofix_auth_20251203_010737.sql

```json
{
  "expected_columns": {
    "app.profiles": {},
    "auth.users": {}
  },
  "db_columns": {
    "auth.users": {
      "instance_id": "uuid",
      "id": "uuid",
      "aud": "character varying",
      "role": "character varying",
      "email": "character varying",
      "encrypted_password": "character varying",
      "email_confirmed_at": "timestamp with time zone",
      "invited_at": "timestamp with time zone",
      "confirmation_token": "character varying",
      "confirmation_sent_at": "timestamp with time zone",
      "recovery_token": "character varying",
      "recovery_sent_at": "timestamp with time zone",
      "email_change_token_new": "character varying",
      "email_change": "character varying",
      "email_change_sent_at": "timestamp with time zone",
      "last_sign_in_at": "timestamp with time zone",
      "raw_app_meta_data": "jsonb",
      "raw_user_meta_data": "jsonb",
      "is_super_admin": "boolean",
      "created_at": "timestamp with time zone",
      "updated_at": "timestamp with time zone",
      "phone": "text",
      "phone_confirmed_at": "timestamp with time zone",
      "phone_change": "text",
      "phone_change_token": "character varying",
      "phone_change_sent_at": "timestamp with time zone",
      "confirmed_at": "timestamp with time zone",
      "email_change_token_current": "character varying",
      "email_change_confirm_status": "smallint",
      "banned_until": "timestamp with time zone",
      "reauthentication_token": "character varying",
      "reauthentication_sent_at": "timestamp with time zone",
      "is_sso_user": "boolean",
      "deleted_at": "timestamp with time zone",
      "is_anonymous": "boolean"
    },
    "app.profiles": {
      "user_id": "uuid",
      "email": "text",
      "display_name": "text",
      "role": "USER-DEFINED",
      "role_v2": "USER-DEFINED",
      "bio": "text",
      "photo_url": "text",
      "is_admin": "boolean",
      "created_at": "timestamp with time zone",
      "updated_at": "timestamp with time zone",
      "avatar_media_id": "uuid",
      "stripe_customer_id": "text"
    }
  }
}
```
