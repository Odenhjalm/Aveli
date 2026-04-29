alter table app.courses
  add column if not exists price_currency text not null default 'sek';

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where connamespace = 'app'::regnamespace
       and conrelid = 'app.courses'::regclass
       and conname = 'courses_price_currency_check'
  ) then
    alter table app.courses
      add constraint courses_price_currency_check
      check (
        price_currency = lower(price_currency)
        and char_length(price_currency) = 3
        and price_currency ~ '^[a-z]{3}$'
      );
  end if;
end $$;

comment on column app.courses.price_currency is
  'Canonical learner-facing course price currency. Lowercase 3-letter currency code for backend-authored pricing projections.';
