-- 0005_policies.sql
-- Hardened RLS policies for app tables.

begin;

-- Profiles ------------------------------------------------------------------
drop policy if exists profiles_self_read on app.profiles;
create policy profiles_self_read on app.profiles
  for select using (auth.uid() = user_id or app.is_admin(auth.uid()));

drop policy if exists profiles_self_write on app.profiles;
create policy profiles_self_write on app.profiles
  for update to authenticated
  using (auth.uid() = user_id or app.is_admin(auth.uid()))
  with check (auth.uid() = user_id or app.is_admin(auth.uid()));

-- Courses -------------------------------------------------------------------
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
drop policy if exists media_owner_rw on app.media_objects;
create policy media_owner_rw on app.media_objects
  for all to authenticated
  using (owner_id = auth.uid() or app.is_admin(auth.uid()))
  with check (owner_id = auth.uid() or app.is_admin(auth.uid()));

-- Lesson media --------------------------------------------------------------
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
drop policy if exists payout_teacher on app.teacher_payout_methods;
create policy payout_teacher on app.teacher_payout_methods
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

-- Seminars ------------------------------------------------------------------
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
drop policy if exists seminar_sessions_host on app.seminar_sessions;
create policy seminar_sessions_host on app.seminar_sessions
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
  );

drop policy if exists seminar_recordings_read on app.seminar_recordings;
create policy seminar_recordings_read on app.seminar_recordings
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
  );

-- Activities ----------------------------------------------------------------
drop policy if exists activities_read on app.activities;
create policy activities_read on app.activities
  for select to authenticated
  using (true);

-- Posts / notifications / follows / messages --------------------------------
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
  with check (sender_id = auth.uid() or recipient_id = auth.uid() or app.is_admin(auth.uid()));

-- Teacher catalog & profile media -------------------------------------------
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

drop policy if exists teachers_owner on app.teachers;
create policy teachers_owner on app.teachers
  for all to authenticated
  using (profile_id = auth.uid() or app.is_admin(auth.uid()))
  with check (profile_id = auth.uid() or app.is_admin(auth.uid()));

-- Sessions & slots ----------------------------------------------------------
drop policy if exists sessions_public_read on app.sessions;
create policy sessions_public_read on app.sessions
  for select to public
  using (visibility = 'published' or teacher_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists sessions_owner on app.sessions;
create policy sessions_owner on app.sessions
  for all to authenticated
  using (teacher_id = auth.uid() or app.is_admin(auth.uid()))
  with check (teacher_id = auth.uid() or app.is_admin(auth.uid()));

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

-- Memberships ---------------------------------------------------------------
drop policy if exists memberships_self on app.memberships;
create policy memberships_self on app.memberships
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

-- Reviews -------------------------------------------------------------------
drop policy if exists reviews_user on app.reviews;
create policy reviews_user on app.reviews
  for all to authenticated
  using (reviewer_id = auth.uid() or app.is_admin(auth.uid()))
  with check (reviewer_id = auth.uid() or app.is_admin(auth.uid()));

-- Course bundles ------------------------------------------------------------
drop policy if exists course_bundles_public_read on app.course_bundles;
create policy course_bundles_public_read on app.course_bundles
  for select
  using (is_active = true);

drop policy if exists course_bundles_owner_write on app.course_bundles;
create policy course_bundles_owner_write on app.course_bundles
  for all
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

drop policy if exists course_bundle_courses_owner on app.course_bundle_courses;
create policy course_bundle_courses_owner on app.course_bundle_courses
  for all
  using (auth.uid() in (
    select teacher_id from app.course_bundles where id = bundle_id
  ))
  with check (auth.uid() in (
    select teacher_id from app.course_bundles where id = bundle_id
  ));

-- Course entitlements -------------------------------------------------------
drop policy if exists course_entitlements_self_read on app.course_entitlements;
create policy course_entitlements_self_read on app.course_entitlements
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

-- Course products -----------------------------------------------------------
drop policy if exists course_products_owner on app.course_products;
create policy course_products_owner on app.course_products
  for all to authenticated
  using (
    exists (
      select 1 from app.courses c
      where c.id = course_products.course_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from app.courses c
      where c.id = course_products.course_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

-- Entitlements --------------------------------------------------------------
drop policy if exists entitlements_student on app.entitlements;
create policy entitlements_student on app.entitlements
  for select to authenticated
  using (user_id = auth.uid() or app.is_admin(auth.uid()));

drop policy if exists entitlements_teacher on app.entitlements;
create policy entitlements_teacher on app.entitlements
  for select to authenticated
  using (
    exists (
      select 1 from app.courses c
      where c.id = entitlements.course_id
        and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
    )
  );

-- Purchases -----------------------------------------------------------------
drop policy if exists purchases_owner_read on app.purchases;
create policy purchases_owner_read on app.purchases
  for select to authenticated
  using (user_id = auth.uid());

commit;
