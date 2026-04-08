-- 008_rls_app_policies.sql
-- Hardened RLS policies for app tables with owner/admin/public handling.

begin;

-- Helpers -------------------------------------------------------------------
create or replace function app.is_admin(p_user uuid)
returns boolean
language sql
as $$
  select exists (
    select 1 from app.profiles
    where user_id = p_user and is_admin = true
  );
$$;

-- Profiles ------------------------------------------------------------------
alter table app.profiles enable row level security;

drop policy if exists service_role_full_access on app.profiles;
create policy service_role_full_access on app.profiles
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists profiles_self_read on app.profiles;
create policy profiles_self_read on app.profiles
  for select using (auth.uid() = user_id or app.is_admin(auth.uid()));

drop policy if exists profiles_self_write on app.profiles;
create policy profiles_self_write on app.profiles
  for update to authenticated
  using (auth.uid() = user_id or app.is_admin(auth.uid()))
  with check (auth.uid() = user_id or app.is_admin(auth.uid()));

-- Courses -------------------------------------------------------------------
alter table app.courses enable row level security;

drop policy if exists courses_service_role on app.courses;
create policy courses_service_role on app.courses
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists courses_public_read on app.courses;
create policy courses_public_read on app.courses
  for select to public
  using (
    is_published = true
    or created_by = auth.uid()
    or app.is_admin(auth.uid())
  );

drop policy if exists courses_owner_write on app.courses;
create policy courses_owner_write on app.courses
  for all to authenticated
  using (created_by = auth.uid() or app.is_admin(auth.uid()))
  with check (created_by = auth.uid() or app.is_admin(auth.uid()));

-- Modules -------------------------------------------------------------------
alter table app.modules enable row level security;

drop policy if exists modules_service_role on app.modules;
create policy modules_service_role on app.modules
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists modules_course_owner on app.modules;
create policy modules_course_owner on app.modules
  for all to authenticated
  using (
    exists (
      select 1 from app.courses c
      where c.id = course_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from app.courses c
      where c.id = course_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

-- Lessons -------------------------------------------------------------------
alter table app.lessons enable row level security;

drop policy if exists lessons_service_role on app.lessons;
create policy lessons_service_role on app.lessons
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists lessons_select on app.lessons;
create policy lessons_select on app.lessons
  for select to authenticated
  using (
    exists (
      select 1 from app.modules m
      join app.courses c on c.id = m.course_id
      where m.id = module_id
        and (
          c.created_by = auth.uid()
          or app.is_admin(auth.uid())
          or (c.is_published and is_intro = true)
          or exists (
            select 1 from app.enrollments e
            where e.course_id = c.id
              and e.user_id = auth.uid()
          )
        )
    )
  );

drop policy if exists lessons_write on app.lessons;
create policy lessons_write on app.lessons
  for all to authenticated
  using (
    exists (
      select 1 from app.modules m
      join app.courses c on c.id = m.course_id
      where m.id = module_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from app.modules m
      join app.courses c on c.id = m.course_id
      where m.id = module_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

-- Media objects -------------------------------------------------------------
alter table app.media_objects enable row level security;

drop policy if exists media_service_role on app.media_objects;
create policy media_service_role on app.media_objects
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists media_owner_rw on app.media_objects;
create policy media_owner_rw on app.media_objects
  for all to authenticated
  using (owner_id = auth.uid() or app.is_admin(auth.uid()))
  with check (owner_id = auth.uid() or app.is_admin(auth.uid()));

-- Lesson media --------------------------------------------------------------
alter table app.lesson_media enable row level security;

drop policy if exists lesson_media_service on app.lesson_media;
create policy lesson_media_service on app.lesson_media
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists lesson_media_select on app.lesson_media;
create policy lesson_media_select on app.lesson_media
  for select to authenticated
  using (
    exists (
      select 1
      from app.lessons l
      join app.modules m on m.id = l.module_id
      join app.courses c on c.id = m.course_id
      where l.id = lesson_id
        and (
          c.created_by = auth.uid()
          or app.is_admin(auth.uid())
          or (c.is_published and l.is_intro = true)
          or exists (
            select 1 from app.enrollments e
            where e.course_id = c.id
              and e.user_id = auth.uid()
          )
        )
    )
  );

drop policy if exists lesson_media_write on app.lesson_media;
create policy lesson_media_write on app.lesson_media
  for all to authenticated
  using (
    exists (
      select 1
      from app.lessons l
      join app.modules m on m.id = l.module_id
      join app.courses c on c.id = m.course_id
      where l.id = lesson_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  )
  with check (
    exists (
      select 1
      from app.lessons l
      join app.modules m on m.id = l.module_id
      join app.courses c on c.id = m.course_id
      where l.id = lesson_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

-- Enrollments ---------------------------------------------------------------
alter table app.enrollments enable row level security;

drop policy if exists enrollments_service on app.enrollments;
create policy enrollments_service on app.enrollments
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists enrollments_user on app.enrollments;
create policy enrollments_user on app.enrollments
  for all to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.courses c where c.id = course_id and c.created_by = auth.uid()
    )
  )
  with check (user_id = auth.uid() or app.is_admin(auth.uid()));

-- Services ------------------------------------------------------------------
alter table app.services enable row level security;

drop policy if exists services_service on app.services;
create policy services_service on app.services
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists services_public_read on app.services;
create policy services_public_read on app.services
  for select to public
  using (status = 'active' and active = true);

drop policy if exists services_owner_rw on app.services;
create policy services_owner_rw on app.services
  for all to authenticated
  using (provider_id = auth.uid() or app.is_admin(auth.uid()))
  with check (provider_id = auth.uid() or app.is_admin(auth.uid()));

-- Orders --------------------------------------------------------------------
alter table app.orders enable row level security;

drop policy if exists orders_service on app.orders;
create policy orders_service on app.orders
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists orders_user_read on app.orders;
create policy orders_user_read on app.orders
  for select to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.services s
      where s.id = service_id and s.provider_id = auth.uid()
    )
  );

drop policy if exists orders_user_write on app.orders;
create policy orders_user_write on app.orders
  for insert to authenticated
  with check (user_id = auth.uid() or app.is_admin(auth.uid()));

-- Payments ------------------------------------------------------------------
alter table app.payments enable row level security;

drop policy if exists payments_service on app.payments;
create policy payments_service on app.payments
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists payments_read on app.payments;
create policy payments_read on app.payments
  for select to authenticated
  using (
    exists (
      select 1 from app.orders o
      where o.id = order_id
        and (
          o.user_id = auth.uid()
          or app.is_admin(auth.uid())
          or exists (
            select 1 from app.services s
            where s.id = o.service_id and s.provider_id = auth.uid()
          )
        )
    )
  );

-- Teacher payout methods ----------------------------------------------------
alter table app.teacher_payout_methods enable row level security;

drop policy if exists payout_service on app.teacher_payout_methods;
create policy payout_service on app.teacher_payout_methods
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists payout_teacher on app.teacher_payout_methods;
create policy payout_teacher on app.teacher_payout_methods
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

-- Seminars ------------------------------------------------------------------
alter table app.seminars enable row level security;

drop policy if exists seminars_service on app.seminars;
create policy seminars_service on app.seminars
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists seminars_public_read on app.seminars;
create policy seminars_public_read on app.seminars
  for select to public
  using (
    status in ('scheduled','live','ended')
    or host_id = auth.uid()
    or app.is_admin(auth.uid())
  );

drop policy if exists seminars_host_rw on app.seminars;
create policy seminars_host_rw on app.seminars
  for all to authenticated
  using (host_id = auth.uid() or app.is_admin(auth.uid()))
  with check (host_id = auth.uid() or app.is_admin(auth.uid()));

-- Seminar attendees ---------------------------------------------------------
alter table app.seminar_attendees enable row level security;

drop policy if exists attendees_service on app.seminar_attendees;
create policy attendees_service on app.seminar_attendees
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists attendees_read on app.seminar_attendees;
create policy attendees_read on app.seminar_attendees
  for select to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.seminars s where s.id = seminar_id and s.host_id = auth.uid()
    )
  );

drop policy if exists attendees_write on app.seminar_attendees;
create policy attendees_write on app.seminar_attendees
  for all to authenticated
  using (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.seminars s where s.id = seminar_id and s.host_id = auth.uid()
    )
  )
  with check (
    user_id = auth.uid()
    or app.is_admin(auth.uid())
    or exists (
      select 1 from app.seminars s where s.id = seminar_id and s.host_id = auth.uid()
    )
  );

-- Seminar sessions & recordings --------------------------------------------
-- Guard late-created tables so replay doesn't fail before those migrations run.
-- Use distinct dollar-quote tags to avoid nested parsing collisions.
do $do$
begin
  if to_regclass('app.seminar_sessions') is null then
    raise notice 'Skipping missing table app.seminar_sessions';
  else
    execute $sql$alter table app.seminar_sessions enable row level security$sql$;

    execute $sql$drop policy if exists seminar_sessions_service on app.seminar_sessions$sql$;
    execute $sql$create policy seminar_sessions_service on app.seminar_sessions
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role')$sql$;

    execute $sql$drop policy if exists seminar_sessions_host on app.seminar_sessions$sql$;
    execute $sql$create policy seminar_sessions_host on app.seminar_sessions
      for all to authenticated
      using (
        exists (
          select 1 from app.seminars s
          where s.id = seminar_id
            and (s.host_id = auth.uid() or app.is_admin(auth.uid()))
        )
      )
      with check (
        exists (
          select 1 from app.seminars s
          where s.id = seminar_id
            and (s.host_id = auth.uid() or app.is_admin(auth.uid()))
        )
      )$sql$;
  end if;

  if to_regclass('app.seminar_recordings') is null then
    raise notice 'Skipping missing table app.seminar_recordings';
  else
    execute $sql$alter table app.seminar_recordings enable row level security$sql$;

    execute $sql$drop policy if exists seminar_recordings_service on app.seminar_recordings$sql$;
    execute $sql$create policy seminar_recordings_service on app.seminar_recordings
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role')$sql$;

    execute $sql$drop policy if exists seminar_recordings_read on app.seminar_recordings$sql$;
    execute $sql$create policy seminar_recordings_read on app.seminar_recordings
      for select to authenticated
      using (
        exists (
          select 1 from app.seminars s
          where s.id = seminar_id
            and (
              s.host_id = auth.uid()
              or app.is_admin(auth.uid())
              or s.status in ('live','ended')
            )
        )
      )$sql$;
  end if;
end$do$;

-- Activities ---------------------------------------------------------------
alter table app.activities enable row level security;

drop policy if exists activities_service on app.activities;
create policy activities_service on app.activities
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists activities_read on app.activities;
create policy activities_read on app.activities
  for select to authenticated
  using (true); -- feed is derived data; filtered via service role or frontend logic

-- Refresh tokens / auth events ---------------------------------------------
alter table app.refresh_tokens enable row level security;
alter table app.auth_events enable row level security;

drop policy if exists refresh_tokens_service on app.refresh_tokens;
create policy refresh_tokens_service on app.refresh_tokens
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists auth_events_service on app.auth_events;
create policy auth_events_service on app.auth_events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- Posts / notifications / follows / messages -------------------------------
alter table app.posts enable row level security;
alter table app.notifications enable row level security;
alter table app.follows enable row level security;
alter table app.messages enable row level security;

drop policy if exists posts_service on app.posts;
create policy posts_service on app.posts
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists posts_author on app.posts;
create policy posts_author on app.posts
  for all to authenticated
  using (author_id = auth.uid() or app.is_admin(auth.uid()))
  with check (author_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists notifications_user on app.notifications;
create policy notifications_user on app.notifications
  for all to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()))
  with check (user_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists follows_user on app.follows;
create policy follows_user on app.follows
  for all to authenticated
  using (follower_id = auth.uid() or app.is_admin(auth.uid()))
  with check (follower_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists messages_user on app.messages;
create policy messages_user on app.messages
  for all to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid() or app.is_admin(auth.uid()))
  with check (sender_id = auth.uid() or app.is_admin(auth.uid()));

-- Stripe customers ---------------------------------------------------------
alter table app.stripe_customers enable row level security;

drop policy if exists stripe_customers_service on app.stripe_customers;
create policy stripe_customers_service on app.stripe_customers
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- Teacher permissions/directory/approvals ----------------------------------
alter table app.teacher_permissions enable row level security;
alter table app.teacher_directory enable row level security;
alter table app.teacher_approvals enable row level security;

drop policy if exists teacher_meta_service on app.teacher_permissions;
create policy teacher_meta_service on app.teacher_permissions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists teacher_directory_service on app.teacher_directory;
create policy teacher_directory_service on app.teacher_directory
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists teacher_approvals_service on app.teacher_approvals;
create policy teacher_approvals_service on app.teacher_approvals
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- Certificates / quizzes / meditations / tarot / reviews -------------------
alter table app.certificates enable row level security;
alter table app.course_quizzes enable row level security;
alter table app.quiz_questions enable row level security;
alter table app.meditations enable row level security;
alter table app.tarot_requests enable row level security;
alter table app.reviews enable row level security;

drop policy if exists certificates_service on app.certificates;
create policy certificates_service on app.certificates
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists quizzes_service on app.course_quizzes;
create policy quizzes_service on app.course_quizzes
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists quiz_questions_service on app.quiz_questions;
create policy quiz_questions_service on app.quiz_questions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists meditations_service on app.meditations;
create policy meditations_service on app.meditations
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists tarot_service on app.tarot_requests;
create policy tarot_service on app.tarot_requests
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists reviews_service on app.reviews;
create policy reviews_service on app.reviews
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists reviews_user on app.reviews;
create policy reviews_user on app.reviews
  for all to authenticated
  using (reviewer_id = auth.uid() or app.is_admin(auth.uid()))
  with check (reviewer_id = auth.uid() or app.is_admin(auth.uid()));

-- Teacher catalog & profile media -----------------------------------------
alter table app.course_display_priorities enable row level security;
alter table app.teacher_profile_media enable row level security;
alter table app.teachers enable row level security;

drop policy if exists course_display_service on app.course_display_priorities;
create policy course_display_service on app.course_display_priorities
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists course_display_owner on app.course_display_priorities;
create policy course_display_owner on app.course_display_priorities
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists tpm_teacher on app.teacher_profile_media;
create policy tpm_teacher on app.teacher_profile_media
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists tpm_public_read on app.teacher_profile_media;
create policy tpm_public_read on app.teacher_profile_media
  for select to public
  using (is_published = true);

drop policy if exists teachers_service on app.teachers;
create policy teachers_service on app.teachers
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists teachers_owner on app.teachers;
create policy teachers_owner on app.teachers
  for all to authenticated
  using (profile_id = auth.uid() or app.is_admin(auth.uid()))
  with check (profile_id = auth.uid() or app.is_admin(auth.uid()));

-- Sessions & slots ---------------------------------------------------------
alter table app.sessions enable row level security;
alter table app.session_slots enable row level security;

drop policy if exists sessions_service on app.sessions;
create policy sessions_service on app.sessions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists sessions_public_read on app.sessions;
create policy sessions_public_read on app.sessions
  for select to public
  using (visibility = 'published' or teacher_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists sessions_owner on app.sessions;
create policy sessions_owner on app.sessions
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists session_slots_service on app.session_slots;
create policy session_slots_service on app.session_slots
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists session_slots_owner on app.session_slots;
create policy session_slots_owner on app.session_slots
  for all to authenticated
  using (
    exists (
      select 1 from app.sessions s
      where s.id = session_id
        and (s.teacher_id = auth.uid() or app.is_admin(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from app.sessions s
      where s.id = session_id
        and (s.teacher_id = auth.uid() or app.is_admin(auth.uid()))
    )
  );

-- Memberships / billing ----------------------------------------------------
alter table app.memberships enable row level security;
alter table app.payment_events enable row level security;
alter table app.billing_logs enable row level security;

drop policy if exists memberships_service on app.memberships;
create policy memberships_service on app.memberships
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists memberships_self on app.memberships;
create policy memberships_self on app.memberships
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists payment_events_service on app.payment_events;
create policy payment_events_service on app.payment_events
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

drop policy if exists billing_logs_service on app.billing_logs;
create policy billing_logs_service on app.billing_logs
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- LiveKit webhook jobs -----------------------------------------------------
-- Guard late-created table so replay doesn't fail before the table exists.
do $do$
begin
  if to_regclass('app.livekit_webhook_jobs') is null then
    raise notice 'Skipping missing table app.livekit_webhook_jobs';
  else
    execute $sql$alter table app.livekit_webhook_jobs enable row level security$sql$;

    execute $sql$drop policy if exists livekit_jobs_service on app.livekit_webhook_jobs$sql$;
    execute $sql$create policy livekit_jobs_service on app.livekit_webhook_jobs
      for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role')$sql$;
  end if;
end$do$;

commit;
