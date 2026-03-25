-- 20260114_91010_backfill_purchases_entitlements_rls.sql
-- RLS policies for backfilled purchase/claim/entitlements tables.

begin;

-- Course products -----------------------------------------------------------
do $$
begin
  if to_regclass('app.course_products') is null then
    raise notice 'Skipping missing table app.course_products';
  else
    alter table app.course_products enable row level security;

    drop policy if exists course_products_service_role on app.course_products;
    create policy course_products_service_role on app.course_products
      for all using (auth.role() = 'service_role'::text)
      with check (auth.role() = 'service_role'::text);

    drop policy if exists course_products_owner on app.course_products;
    create policy course_products_owner on app.course_products
      for all to authenticated
      using (
        exists (
          select 1 from app.courses c
          where c.id = course_products.course_id
            and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
        )
      )
      with check (
        exists (
          select 1 from app.courses c
          where c.id = course_products.course_id
            and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
        )
      );
  end if;
end$$;

-- Entitlements --------------------------------------------------------------
do $$
begin
  if to_regclass('app.entitlements') is null then
    raise notice 'Skipping missing table app.entitlements';
  else
    alter table app.entitlements enable row level security;

    drop policy if exists entitlements_service_role on app.entitlements;
    create policy entitlements_service_role on app.entitlements
      for all using (auth.role() = 'service_role'::text)
      with check (auth.role() = 'service_role'::text);

    drop policy if exists entitlements_student on app.entitlements;
    create policy entitlements_student on app.entitlements
      for select to authenticated
      using (user_id = auth.uid() or app.is_admin(auth.uid()));

    drop policy if exists entitlements_teacher on app.entitlements;
    create policy entitlements_teacher on app.entitlements
      for select to authenticated
      using (
        exists (
          select 1 from app.courses c
          where c.id = entitlements.course_id
            and (c.created_by = auth.uid() or app.is_admin(auth.uid()))
        )
      );
  end if;
end$$;

-- Guest claim tokens --------------------------------------------------------
do $$
begin
  if to_regclass('app.guest_claim_tokens') is null then
    raise notice 'Skipping missing table app.guest_claim_tokens';
  else
    alter table app.guest_claim_tokens enable row level security;

    drop policy if exists guest_claim_tokens_service_role on app.guest_claim_tokens;
    create policy guest_claim_tokens_service_role on app.guest_claim_tokens
      for all using (auth.role() = 'service_role'::text)
      with check (auth.role() = 'service_role'::text);
  end if;
end$$;

-- Purchases -----------------------------------------------------------------
do $$
begin
  if to_regclass('app.purchases') is null then
    raise notice 'Skipping missing table app.purchases';
  else
    alter table app.purchases enable row level security;

    drop policy if exists purchases_service_role on app.purchases;
    create policy purchases_service_role on app.purchases
      for all using (auth.role() = 'service_role'::text)
      with check (auth.role() = 'service_role'::text);

    drop policy if exists purchases_owner_read on app.purchases;
    create policy purchases_owner_read on app.purchases
      for select to authenticated
      using (user_id = auth.uid());
  end if;
end$$;

commit;
