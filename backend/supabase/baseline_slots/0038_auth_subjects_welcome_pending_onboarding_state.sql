do $$
begin
  alter table app.auth_subjects
    drop constraint if exists auth_subjects_onboarding_state_check;

  alter table app.auth_subjects
    add constraint auth_subjects_onboarding_state_check
    check (
      onboarding_state in (
        'incomplete',
        'welcome_pending',
        'completed'
      )
    );
end
$$;

comment on constraint auth_subjects_onboarding_state_check on app.auth_subjects is
  'Canonical onboarding states are incomplete, welcome_pending, and completed. Create-profile moves to welcome_pending; explicit welcome confirmation completes onboarding.';

