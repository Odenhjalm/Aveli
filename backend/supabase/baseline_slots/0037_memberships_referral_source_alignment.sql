do $$
begin
  alter table app.memberships
    drop constraint if exists memberships_source_supported_check;

  alter table app.memberships
    add constraint memberships_source_supported_check
    check (
      source is not null
      and btrim(source) <> ''
      and source in (
        'purchase',
        'referral',
        'coupon'
      )
    );
end
$$;

do $$
begin
  alter table app.memberships
    drop constraint if exists memberships_invite_expires_at_check;

  alter table app.memberships
    add constraint memberships_referral_expires_at_check
    check (
      source <> 'referral'
      or expires_at is not null
    );
end
$$;

comment on table app.memberships is
  'Canonical global app-entry membership authority. Active grants entry; canceled requires future expires_at in runtime; all other supported statuses deny entry. Referral is the canonical non-purchase grant source for this onboarding path.';

comment on constraint memberships_source_supported_check on app.memberships is
  'Baseline fail-closed source shape for canonical membership authority. Supported sources are purchase, referral, and coupon.';

comment on constraint memberships_referral_expires_at_check on app.memberships is
  'Referral membership grants must be time-bounded with non-null expires_at.';
