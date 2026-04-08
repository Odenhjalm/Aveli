# AOI-008 FAILURE CONTRACT ALIGNMENT

TYPE: `OWNER`  
TASK_TYPE: `BACKEND_ALIGNMENT`  
DEPENDS_ON: `["AOI-003", "AOI-004", "AOI-005", "AOI-006", "AOI-007"]`

## Goal

Apply the canonical Auth + Onboarding failure envelope and language policy to all kept backend surfaces.

## Required Outputs

- error envelope fields limited to `status`, `error_code`, `message`, `field_errors`
- Swedish user-facing messages on canonical backend responses
- removal of `detail` and `error` ambiguity on covered surfaces

## Forbidden

- mixed legacy error shapes
- English user-facing backend messages on covered surfaces
- route-specific ad hoc error payloads

## Exit Criteria

- every covered error response matches the failure contract
- frontend can rely on a single envelope shape
