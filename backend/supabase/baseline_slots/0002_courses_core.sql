create table app.courses (
  id uuid not null,
  title text not null,
  slug text not null,
  course_group_id uuid not null,
  step app.course_step not null,
  price_amount_cents integer,
  drip_enabled boolean not null,
  drip_interval_days integer,
  cover_media_id uuid,
  constraint courses_pkey primary key (id),
  constraint courses_slug_key unique (slug),
  constraint courses_course_group_id_step_key unique (course_group_id, step),
  constraint courses_step_price_check check (
    (
      step = 'intro'
      and price_amount_cents is null
    )
    or (
      step in ('step1', 'step2', 'step3')
      and price_amount_cents > 0
    )
  ),
  constraint courses_drip_interval_check check (
    (
      drip_enabled = true
      and drip_interval_days is not null
    )
    or (
      drip_enabled = false
      and drip_interval_days is null
    )
  )
);
