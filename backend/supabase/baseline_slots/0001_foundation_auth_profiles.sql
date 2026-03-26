create schema if not exists "app";

create type "app"."profile_role" as enum ('student', 'teacher', 'admin');

create type "app"."user_role" as enum ('user', 'professional', 'teacher');

create table "app"."profiles" (
  "user_id" uuid not null,
  "email" text not null,
  "display_name" text,
  "role" app.profile_role not null default 'student'::app.profile_role,
  "role_v2" app.user_role not null default 'user'::app.user_role,
  "bio" text,
  "photo_url" text,
  "is_admin" boolean not null default false,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "avatar_media_id" uuid,
  "stripe_customer_id" text,
  "provider_name" text,
  "provider_user_id" text,
  "provider_email_verified" boolean,
  "provider_avatar_url" text,
  "last_login_provider" text,
  "last_login_at" timestamp with time zone
);

alter table "app"."profiles" enable row level security;

create table "app"."auth_events" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid,
  "email" text,
  "event" text not null,
  "ip_address" inet,
  "user_agent" text,
  "metadata" jsonb,
  "created_at" timestamp with time zone not null default now()
);

alter table "app"."auth_events" enable row level security;

create table "app"."refresh_tokens" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "jti" uuid not null,
  "token_hash" text not null,
  "issued_at" timestamp with time zone not null default now(),
  "expires_at" timestamp with time zone not null,
  "rotated_at" timestamp with time zone,
  "revoked_at" timestamp with time zone,
  "last_used_at" timestamp with time zone
);

alter table "app"."refresh_tokens" enable row level security;

create unique index "auth_events_pkey" on "app"."auth_events" using btree ("id");

create unique index "profiles_pkey" on "app"."profiles" using btree ("user_id");

create unique index "profiles_email_key" on "app"."profiles" using btree ("email");

create index "profiles_stripe_customer_idx" on "app"."profiles" using btree (lower("stripe_customer_id"));

create unique index "refresh_tokens_pkey" on "app"."refresh_tokens" using btree ("id");

create unique index "refresh_tokens_jti_key" on "app"."refresh_tokens" using btree ("jti");

alter table "app"."auth_events"
  add constraint "auth_events_pkey" primary key using index "auth_events_pkey";

alter table "app"."profiles"
  add constraint "profiles_pkey" primary key using index "profiles_pkey";

alter table "app"."profiles"
  add constraint "profiles_email_key" unique using index "profiles_email_key";

alter table "app"."refresh_tokens"
  add constraint "refresh_tokens_pkey" primary key using index "refresh_tokens_pkey";

alter table "app"."refresh_tokens"
  add constraint "refresh_tokens_jti_key" unique using index "refresh_tokens_jti_key";

alter table "app"."profiles"
  add constraint "profiles_user_id_fkey"
  foreign key ("user_id") references "auth"."users" ("id") on delete cascade not valid;

alter table "app"."profiles"
  validate constraint "profiles_user_id_fkey";

alter table "app"."auth_events"
  add constraint "auth_events_user_id_fkey"
  foreign key ("user_id") references "app"."profiles" ("user_id") on delete cascade not valid;

alter table "app"."auth_events"
  validate constraint "auth_events_user_id_fkey";

alter table "app"."refresh_tokens"
  add constraint "refresh_tokens_user_id_fkey"
  foreign key ("user_id") references "app"."profiles" ("user_id") on delete cascade not valid;

alter table "app"."refresh_tokens"
  validate constraint "refresh_tokens_user_id_fkey";

create or replace function "app"."set_updated_at"()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

create trigger "trg_profiles_touch"
before update on "app"."profiles"
for each row
execute function "app"."set_updated_at"();

grant delete on table "app"."auth_events" to "anon";
grant insert on table "app"."auth_events" to "anon";
grant select on table "app"."auth_events" to "anon";
grant update on table "app"."auth_events" to "anon";
grant delete on table "app"."auth_events" to "authenticated";
grant insert on table "app"."auth_events" to "authenticated";
grant select on table "app"."auth_events" to "authenticated";
grant update on table "app"."auth_events" to "authenticated";
grant delete on table "app"."auth_events" to "service_role";
grant insert on table "app"."auth_events" to "service_role";
grant select on table "app"."auth_events" to "service_role";
grant update on table "app"."auth_events" to "service_role";

grant delete on table "app"."profiles" to "anon";
grant insert on table "app"."profiles" to "anon";
grant select on table "app"."profiles" to "anon";
grant update on table "app"."profiles" to "anon";
grant delete on table "app"."profiles" to "authenticated";
grant insert on table "app"."profiles" to "authenticated";
grant select on table "app"."profiles" to "authenticated";
grant update on table "app"."profiles" to "authenticated";
grant delete on table "app"."profiles" to "service_role";
grant insert on table "app"."profiles" to "service_role";
grant select on table "app"."profiles" to "service_role";
grant update on table "app"."profiles" to "service_role";

grant delete on table "app"."refresh_tokens" to "anon";
grant insert on table "app"."refresh_tokens" to "anon";
grant select on table "app"."refresh_tokens" to "anon";
grant update on table "app"."refresh_tokens" to "anon";
grant delete on table "app"."refresh_tokens" to "authenticated";
grant insert on table "app"."refresh_tokens" to "authenticated";
grant select on table "app"."refresh_tokens" to "authenticated";
grant update on table "app"."refresh_tokens" to "authenticated";
grant delete on table "app"."refresh_tokens" to "service_role";
grant insert on table "app"."refresh_tokens" to "service_role";
grant select on table "app"."refresh_tokens" to "service_role";
grant update on table "app"."refresh_tokens" to "service_role";

create policy "auth_events_service"
on "app"."auth_events"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "service_role_full_access"
on "app"."auth_events"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "service_role_full_access"
on "app"."profiles"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "refresh_tokens_service"
on "app"."refresh_tokens"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "service_role_full_access"
on "app"."refresh_tokens"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
