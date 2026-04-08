## Recommended Decision Set

### Recommended Combined Set

The strongest recommended combined decision set is:

1. **Source entity name**
   - `app.profile_media_placements`

2. **Shared vs separate source model**
   - Use one profile-media source model.
   - Community surfaces consume the same source model through backend read composition.
   - Community does not become a separate source-truth domain in this decision set.

3. **Authored subject-binding model**
   - Use `subject_user_id` as a soft external subject reference on `app.profile_media_placements`.
   - It is semantically aligned to the same canonical subject identity carried by `auth_subjects.user_id`.
   - `auth_subjects` does not own profile-media feature authority.

4. **Publication-state fields and invariants**
   - Required field: `visibility`
   - Allowed values: `draft | published`
   - No implicit default
   - Invalid input must fail explicitly
   - Only `published` rows may feed `runtime_media`
   - `visibility` does not replace media readiness, access, or frontend representation authority

5. **Profile/community-specific media purpose**
   - Add one new `media_purpose` value: `profile_media`

6. **Append-only authority path into runtime_media**
   - Add the new purpose value append-only
   - Add `app.profile_media_placements` append-only above baseline core
   - Extend `app.runtime_media` append-only so published profile-media placements can contribute runtime rows
   - Keep backend read composition as the only frontend media representation authority for all profile/community mounted surfaces

## Why This Combined Set Is Recommended

This set is recommended because it is the smallest explicit decision set that:

- matches the feature-domain name already declared in canonical decisions
- preserves one media doctrine
- keeps non-core feature truth out of baseline core tables
- avoids broadening `auth_subjects` beyond its declared authority
- gives a deterministic append-only path into unified `runtime_media`
- minimizes future migration debt

## Minimum Decisions Required To Unblock Canonical Truth

The minimum decisions required to unblock canonical truth are exactly these:

1. choose the source entity name
2. choose shared vs separate source truth
3. choose the authored subject-binding model
4. choose the publication-state model
5. choose the purpose taxonomy
6. choose the append-only path that feeds runtime truth into `runtime_media`

Without all six, the profile/community media contract cannot safely become active truth.

## Best Long-Term Canonical Shape

The strongest long-term canonical shape is:

- one explicit active contract for the profile-media feature domain
- one explicit feature-specific authored-placement source entity
- one explicit feature-specific purpose value
- one explicit publication field model
- one append-only runtime projection path into `runtime_media`
- one backend read-composition rule for all mounted profile/community surfaces

This shape keeps the system aligned with:

- single-path media authority
- append-only baseline evolution
- non-core feature separation from baseline core
- future task generation that remains deterministic and implementation-safe

## Why The Main Alternatives Were Not Recommended

### Shared family name `profile_community_media_placements`

This was not chosen because the current canonical source set names `profile media` explicitly, not `profile/community media` as a separate feature domain.

### Separate `profile` and `community` source models

This was not chosen because it introduces more schema and more authority surface than the current target model needs, without strong present doctrinal support.

### `teacher_user_id` as the authored binding

This was not chosen because it narrows the feature to teachers prematurely and is less future-proof than a generic subject binding.

### Two separate purpose values

This was not chosen because it adds taxonomy earlier than needed and risks fragmenting the unified media domain.
