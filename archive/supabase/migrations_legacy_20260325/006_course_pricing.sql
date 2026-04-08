alter table app.courses
  add column if not exists stripe_product_id text,
  add column if not exists stripe_price_id text,
  add column if not exists price_amount_cents integer not null default 0,
  add column if not exists currency text not null default 'sek';

update app.courses
   set price_amount_cents = price_cents
 where price_cents is not null;

create index if not exists courses_slug_idx on app.courses (slug);
