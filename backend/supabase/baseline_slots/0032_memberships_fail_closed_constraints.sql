do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'memberships_status_supported_check'
  ) then
    alter table app.memberships
      add constraint memberships_status_supported_check
      check (
        status in (
          'active',
          'canceled',
          'inactive',
          'past_due',
          'expired'
        )
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'memberships_source_supported_check'
  ) then
    alter table app.memberships
      add constraint memberships_source_supported_check
      check (
        source is not null
        and btrim(source) <> ''
        and source in (
          'purchase',
          'invite',
          'coupon'
        )
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'memberships_invite_expires_at_check'
  ) then
    alter table app.memberships
      add constraint memberships_invite_expires_at_check
      check (
        source <> 'invite'
        or expires_at is not null
      );
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'memberships_canceled_expires_at_check'
  ) then
    alter table app.memberships
      add constraint memberships_canceled_expires_at_check
      check (
        status <> 'canceled'
        or expires_at is not null
      );
  end if;
end
$$;

create index if not exists idx_memberships_app_entry_candidates
  on app.memberships (user_id, status, expires_at);

comment on table app.memberships is
  'Canonical global app-entry membership authority. Active grants entry; canceled requires future expires_at in runtime; all other supported statuses deny entry.';

comment on constraint memberships_status_supported_check on app.memberships is
  'Baseline fail-closed status shape for canonical membership authority.';

comment on constraint memberships_source_supported_check on app.memberships is
  'Baseline fail-closed source shape for canonical membership authority. Referral is not a membership source.';

comment on constraint memberships_invite_expires_at_check on app.memberships is
  'Invite membership grants must be time-bounded with non-null expires_at.';
