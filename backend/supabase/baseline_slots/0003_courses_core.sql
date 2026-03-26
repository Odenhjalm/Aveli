create table "app"."courses" (
  "id" uuid not null default gen_random_uuid(),
  "slug" text not null,
  "title" text not null,
  "description" text,
  "cover_url" text,
  "video_url" text,
  "branch" text,
  "is_free_intro" boolean not null default false,
  "price_cents" integer not null default 0,
  "currency" text not null default 'sek'::text,
  "is_published" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "stripe_product_id" text,
  "stripe_price_id" text,
  "price_amount_cents" integer not null default 0,
  "cover_media_id" uuid,
  "journey_step" text default 'intro'::text
);

alter table "app"."courses" enable row level security;

create unique index "courses_pkey" on "app"."courses" using btree ("id");

create unique index "courses_slug_key" on "app"."courses" using btree ("slug");

create index "idx_courses_cover_media" on "app"."courses" using btree ("cover_media_id");

create index "idx_courses_created_by" on "app"."courses" using btree ("created_by");

alter table "app"."courses"
  add constraint "courses_pkey" primary key using index "courses_pkey";

alter table "app"."courses"
  add constraint "courses_created_by_fkey"
  foreign key ("created_by") references "app"."profiles" ("user_id") on delete set null not valid;

alter table "app"."courses"
  validate constraint "courses_created_by_fkey";

alter table "app"."courses"
  add constraint "courses_journey_step_check"
  check (("journey_step" = any (array['intro'::text, 'step1'::text, 'step2'::text, 'step3'::text]))) not valid;

alter table "app"."courses"
  validate constraint "courses_journey_step_check";

alter table "app"."courses"
  add constraint "courses_slug_key" unique using index "courses_slug_key";

create trigger "trg_courses_touch"
before update on "app"."courses"
for each row
execute function "app"."set_updated_at"();

grant delete on table "app"."courses" to "anon";
grant insert on table "app"."courses" to "anon";
grant select on table "app"."courses" to "anon";
grant update on table "app"."courses" to "anon";
grant delete on table "app"."courses" to "authenticated";
grant insert on table "app"."courses" to "authenticated";
grant select on table "app"."courses" to "authenticated";
grant update on table "app"."courses" to "authenticated";
grant delete on table "app"."courses" to "service_role";
grant insert on table "app"."courses" to "service_role";
grant select on table "app"."courses" to "service_role";
grant update on table "app"."courses" to "service_role";

create policy "courses_owner_write"
on "app"."courses"
as permissive
for all
to authenticated
using (((created_by = auth.uid()) or app.is_admin(auth.uid())))
with check (((created_by = auth.uid()) or app.is_admin(auth.uid())));

create policy "courses_public_read"
on "app"."courses"
as permissive
for select
to public
using (((is_published = true) or (created_by = auth.uid()) or app.is_admin(auth.uid())));

create policy "courses_service_role"
on "app"."courses"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "service_role_full_access"
on "app"."courses"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
