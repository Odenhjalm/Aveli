create table "app"."teacher_approvals" (
  "id" uuid not null default gen_random_uuid(),
  "user_id" uuid not null,
  "reviewer_id" uuid,
  "status" text not null default 'pending'::text,
  "notes" text,
  "approved_by" uuid,
  "approved_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

alter table "app"."teacher_approvals" enable row level security;

create table "app"."teacher_permissions" (
  "profile_id" uuid not null,
  "can_edit_courses" boolean not null default false,
  "can_publish" boolean not null default false,
  "granted_by" uuid,
  "granted_at" timestamp with time zone not null default now()
);

alter table "app"."teacher_permissions" enable row level security;

create index "idx_teacher_approvals_user" on "app"."teacher_approvals" using btree ("user_id");

create unique index "teacher_approvals_pkey" on "app"."teacher_approvals" using btree ("id");

create unique index "teacher_approvals_user_id_key" on "app"."teacher_approvals" using btree ("user_id");

create unique index "teacher_permissions_pkey" on "app"."teacher_permissions" using btree ("profile_id");

alter table "app"."teacher_approvals"
  add constraint "teacher_approvals_pkey" primary key using index "teacher_approvals_pkey";

alter table "app"."teacher_permissions"
  add constraint "teacher_permissions_pkey" primary key using index "teacher_permissions_pkey";

alter table "app"."teacher_approvals"
  add constraint "teacher_approvals_approved_by_fkey"
  foreign key ("approved_by") references "app"."profiles" ("user_id") not valid;

alter table "app"."teacher_approvals"
  validate constraint "teacher_approvals_approved_by_fkey";

alter table "app"."teacher_approvals"
  add constraint "teacher_approvals_reviewer_id_fkey"
  foreign key ("reviewer_id") references "app"."profiles" ("user_id") not valid;

alter table "app"."teacher_approvals"
  validate constraint "teacher_approvals_reviewer_id_fkey";

alter table "app"."teacher_approvals"
  add constraint "teacher_approvals_user_id_fkey"
  foreign key ("user_id") references "app"."profiles" ("user_id") on delete cascade not valid;

alter table "app"."teacher_approvals"
  validate constraint "teacher_approvals_user_id_fkey";

alter table "app"."teacher_approvals"
  add constraint "teacher_approvals_user_id_key" unique using index "teacher_approvals_user_id_key";

alter table "app"."teacher_permissions"
  add constraint "teacher_permissions_granted_by_fkey"
  foreign key ("granted_by") references "app"."profiles" ("user_id") not valid;

alter table "app"."teacher_permissions"
  validate constraint "teacher_permissions_granted_by_fkey";

alter table "app"."teacher_permissions"
  add constraint "teacher_permissions_profile_id_fkey"
  foreign key ("profile_id") references "app"."profiles" ("user_id") on delete cascade not valid;

alter table "app"."teacher_permissions"
  validate constraint "teacher_permissions_profile_id_fkey";

create or replace function "app"."is_admin"("p_user" uuid)
returns boolean
language sql
as $function$
  select exists (
    select 1 from app.profiles
    where user_id = p_user and is_admin = true
  );
$function$;

create or replace function "app"."is_teacher"("p_user" uuid)
returns boolean
language sql
as $function$
  select
    app.is_admin(p_user)
    or exists (
      select 1
      from app.profiles p
      where p.user_id = p_user
        and coalesce(p.role_v2, 'user')::text in ('teacher', 'admin')
    )
    or exists (
      select 1
      from app.teacher_permissions tp
      where tp.profile_id = p_user
        and (tp.can_edit_courses = true or tp.can_publish = true)
    )
    or exists (
      select 1
      from app.teacher_approvals ta
      where ta.user_id = p_user
        and ta.approved_at is not null
    );
$function$;

create trigger "trg_teacher_approvals_touch"
before update on "app"."teacher_approvals"
for each row
execute function "app"."set_updated_at"();

grant delete on table "app"."teacher_approvals" to "anon";
grant insert on table "app"."teacher_approvals" to "anon";
grant select on table "app"."teacher_approvals" to "anon";
grant update on table "app"."teacher_approvals" to "anon";
grant delete on table "app"."teacher_approvals" to "authenticated";
grant insert on table "app"."teacher_approvals" to "authenticated";
grant select on table "app"."teacher_approvals" to "authenticated";
grant update on table "app"."teacher_approvals" to "authenticated";
grant delete on table "app"."teacher_approvals" to "service_role";
grant insert on table "app"."teacher_approvals" to "service_role";
grant select on table "app"."teacher_approvals" to "service_role";
grant update on table "app"."teacher_approvals" to "service_role";

grant delete on table "app"."teacher_permissions" to "anon";
grant insert on table "app"."teacher_permissions" to "anon";
grant select on table "app"."teacher_permissions" to "anon";
grant update on table "app"."teacher_permissions" to "anon";
grant delete on table "app"."teacher_permissions" to "authenticated";
grant insert on table "app"."teacher_permissions" to "authenticated";
grant select on table "app"."teacher_permissions" to "authenticated";
grant update on table "app"."teacher_permissions" to "authenticated";
grant delete on table "app"."teacher_permissions" to "service_role";
grant insert on table "app"."teacher_permissions" to "service_role";
grant select on table "app"."teacher_permissions" to "service_role";
grant update on table "app"."teacher_permissions" to "service_role";

create policy "profiles_self_read"
on "app"."profiles"
as permissive
for select
to public
using (((auth.uid() = user_id) or app.is_admin(auth.uid())));

create policy "profiles_self_write"
on "app"."profiles"
as permissive
for update
to authenticated
using (((auth.uid() = user_id) or app.is_admin(auth.uid())))
with check (((auth.uid() = user_id) or app.is_admin(auth.uid())));

create policy "service_role_full_access"
on "app"."teacher_approvals"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "teacher_approvals_service"
on "app"."teacher_approvals"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "service_role_full_access"
on "app"."teacher_permissions"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));

create policy "teacher_meta_service"
on "app"."teacher_permissions"
as permissive
for all
to public
using ((auth.role() = 'service_role'::text))
with check ((auth.role() = 'service_role'::text));
