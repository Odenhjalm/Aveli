begin;

alter table if exists app.app_config
  drop column if exists free_course_limit;

commit;
