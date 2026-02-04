-- Fix course price scaling for legacy rows.
--
-- Some paid courses were accidentally stored as kronor in `price_amount_cents`
-- (e.g. 490 instead of 49000), causing a /100 undercharge in both UI and Stripe.
--
-- We conservatively treat any published, paid course priced under 100 SEK
-- (i.e. < 10000 öre) as mis-scaled and multiply by 100.
--
-- Stripe prices are immutable; clear `stripe_price_id` so the backend recreates a
-- new price with the corrected amount on the next checkout.

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'courses'
      and column_name = 'price_amount_cents'
  ) then
    update app.courses
       set price_amount_cents = price_amount_cents * 100,
           stripe_price_id = null,
           updated_at = now()
     where is_free_intro is false
       and is_published is true
       and price_amount_cents > 0
       and price_amount_cents < 10000;
  end if;
end $$;
