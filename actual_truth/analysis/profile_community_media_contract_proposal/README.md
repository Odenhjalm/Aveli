## Profile/Community Media Contract Proposal

This directory contains a no-code canonical analysis of the profile/community media blocker that stopped `BCP-043`.

### Purpose

The goal of this analysis is to derive the strongest possible structured contract candidate for profile/community media from the current canonical source set, then verify whether that candidate is fully canonical, dependency-valid, and aligned with the Aveli target model.

### Scope

This analysis covers only:

- profile/community media source-boundary requirements
- the relationship between profile/community media and unified `runtime_media`
- backend read-composition implications for mounted profile/community surfaces
- baseline-scope implications

This analysis does not include:

- implementation
- SQL or schema mutation
- task generation
- task execution
- baseline mutation

### Final Outcome

The strongest candidate derived from the canonical source set is **not fully canonical yet**.

- Proposal candidate status: `CANONICAL_BUT_PARTIAL`
- Final decision status: `BLOCKED_BY_INSUFFICIENCY`

### Why It Is Not Fully Canonical Yet

The canonical source set clearly requires:

- unified media authority through `runtime_media`
- an explicit structured contract for profile media
- separation of non-core feature truth from baseline core

However, the canonical source set does **not** yet fully define:

- the exact profile/community source entity or entities
- the exact authored identity shape
- the allowed purpose values for profile/community media
- whether profile and community share one physical source model or require separate source models

### Files

- `PROFILE_COMMUNITY_MEDIA_CONTRACT_PROPOSAL.md`
- `VERIFICATION_AGAINST_CANONICAL_SOURCES.md`
- `DECISION_STATUS.md`
