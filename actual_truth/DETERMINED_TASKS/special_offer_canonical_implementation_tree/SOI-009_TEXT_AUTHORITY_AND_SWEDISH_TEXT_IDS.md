# SOI-009 TEXT AUTHORITY AND SWEDISH TEXT IDS

- TASK_ID: `SOI-009`
- TYPE: `OWNER`
- GROUP: `TEXT AUTHORITY INTEGRATION`

## Purpose

Define and integrate the backend-owned text IDs required for special-offer
generation status, regenerate confirmation, and failure handling, while keeping
exact user-facing copy under Swedish-only text authority.

## Contract References

- `actual_truth/contracts/backend_text_catalog_contract.md`
- `actual_truth/contracts/special_offer_composite_image_contract.md`
- `actual_truth/contracts/special_offer_execution_contract.md`

## DEPENDS_ON

- `SOI-006`
- `SOI-007`
- `SOI-008`

## Dependency Requirements

- exact product copy remains under backend text authority
- product-visible text values are Swedish-only
- special-offer execution surfaces must carry text IDs or text-authority-owned
  projections, not ad hoc English strings

## Exact Scope

- define required special-offer text IDs for:
  - overwrite confirmation
  - generation failure
  - generation status
- wire execution-visible states to backend text authority
- keep identifiers non-user-facing and stable

## Verification Criteria

- required special-offer text IDs exist under backend text authority
- no execution surface hardcodes English user-facing product copy
- frontend does not invent fallback strings for overwrite, failure, or status
- exact warning copy remains text-authority-owned rather than contract-owned

## GO Condition

Go when all special-offer user-facing text surfaces are backed by stable backend
text IDs and Swedish-only product copy rules.

## BLOCKED Condition

Stop if any implementation renders English copy, frontend-local fallback text,
or raw backend exception text as product messaging.

## Out Of Scope

- frontend dialog behavior
- image bytes
- commerce copy
