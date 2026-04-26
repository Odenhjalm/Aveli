alter table app.course_public_content
  add column description text not null default '';

comment on column app.course_public_content.description is
  'Canonical full public course description. Backend read composition owns runtime delivery; description.md is ingestion/source material only and is not runtime authority.';

comment on table app.course_public_content is
  'Sibling public content surface for course short and full descriptions. Does not control course visibility.';
