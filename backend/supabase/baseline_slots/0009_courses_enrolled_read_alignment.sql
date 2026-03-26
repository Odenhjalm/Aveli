create policy "courses_enrolled_read"
on "app"."courses"
as permissive
for select
to authenticated
using (
  exists (
    select 1
    from app.enrollments e
    where e.course_id = courses.id
      and e.user_id = auth.uid()
  )
);
