# AOI-002 ADMIN BOOTSTRAP OPERATOR SURFACE SLOT

TYPE: `OWNER`  
TASK_TYPE: `BASELINE_SLOT`  
DEPENDS_ON: `["AOI-001"]`

## Goal

Create append-only baseline slot `0024_admin_bootstrap_operator_surface.sql` to materialize one-time operator-controlled first-admin bootstrap authority.

## Required Outputs

- table `app.admin_bootstrap_state`
- function `app.bootstrap_first_admin(target_user_id uuid)`

## Forbidden

- adding any public app-runtime route for admin bootstrap
- seeding a hardcoded first admin in baseline
- introducing non-operator bootstrap fallbacks

## Exit Criteria

- bootstrap availability is owned by `app.admin_bootstrap_state`
- first-admin mutation is owned only by `app.bootstrap_first_admin(target_user_id uuid)`
- the slot is append-only and depends only on prior baseline truth
