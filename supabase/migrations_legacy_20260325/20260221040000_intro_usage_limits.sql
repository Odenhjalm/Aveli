begin;

create table if not exists app.intro_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  year integer not null check (year >= 2000 and year <= 9999),
  month integer not null check (month between 1 and 12),
  count integer not null default 0 check (count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, year, month)
);

create index if not exists idx_intro_usage_user_month
  on app.intro_usage(user_id, year desc, month desc);

create or replace function app.touch_intro_usage()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_intro_usage_touch on app.intro_usage;

create trigger trg_intro_usage_touch
before update on app.intro_usage
for each row execute function app.touch_intro_usage();

commit;
