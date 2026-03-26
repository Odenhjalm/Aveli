alter table app.profiles
  add column if not exists stripe_customer_id text;

create index if not exists profiles_stripe_customer_idx
  on app.profiles using btree ((lower(stripe_customer_id)));
