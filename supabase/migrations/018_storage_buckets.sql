-- Ensure required Supabase Storage buckets exist for media flows.
begin;

insert into storage.buckets (id, name, public)
values ('public-media', 'public-media', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('course-media', 'course-media', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('lesson-media', 'lesson-media', false)
on conflict (id) do nothing;

commit;
