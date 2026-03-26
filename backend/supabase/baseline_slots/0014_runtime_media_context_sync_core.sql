create or replace function app.sync_runtime_media_course_context_trigger()
returns trigger
language plpgsql
as $function$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  join app.lessons l on l.id = lm.lesson_id
  where l.course_id = new.id;

  return new;
end;
$function$;


create or replace function app.sync_runtime_media_lesson_context_trigger()
returns trigger
language plpgsql
as $function$
begin
  perform app.upsert_runtime_media_for_lesson_media(lm.id)
  from app.lesson_media lm
  where lm.lesson_id = new.id;

  return new;
end;
$function$;


create trigger trg_runtime_media_sync_course_context
after update of created_by
on app.courses
for each row
execute function app.sync_runtime_media_course_context_trigger();


create trigger trg_runtime_media_sync_lesson_context
after update of course_id
on app.lessons
for each row
execute function app.sync_runtime_media_lesson_context_trigger();
