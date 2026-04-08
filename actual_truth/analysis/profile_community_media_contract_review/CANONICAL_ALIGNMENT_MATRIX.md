## Canonical Alignment Matrix

### Canonical Core Of The Document

The following parts of the current document are already strong and should remain in some form:

- profile/community media is a governed media usage
- `runtime_media` remains the only runtime truth layer
- backend read composition remains the only frontend media representation authority
- storage-native truth must not cross the contract boundary
- profile/community media must not introduce a second resolver system
- profile/community feature truth must remain outside baseline core unless explicitly modeled
- the document must not drive implementation unless unresolved source-shape decisions are actually declared

## Section-Level Review

| Document part | Current status | Review classification | Why | Baseline interaction | Recommended action |
| --- | --- | --- | --- | --- | --- |
| Title + `STATUS: CANDIDATE (PENDING CANONICAL VALIDATION)` | Explicit candidate status | Partially aligned, but structurally risky | The document correctly signals incompleteness, but it sits inside the authoritative contract set where unresolved truth is dangerous | The baseline has no profile/community authority layer yet, so a candidate in active-contract form can be misread as implementation authority | Rewrite the document role and status so it records doctrine plus unresolved decisions, not pseudo-active contract truth |
| Section 1. Candidate Authority Statement | Broadly correct caution language | Partially aligned | The section correctly says the document is not truth until validated, but it does not fully protect readers from treating the later source-shape choices as active guidance | Current baseline and task state still lack the source model needed by `BCP-043` | Rewrite to state that only already-declared doctrine in this file is normative; unresolved source-shape choices remain decision placeholders |
| Section 2. Purpose | Strong | Already canonically aligned | The section accurately reflects unified media law, non-core separation, and legacy-field prohibition | Fully consistent with current baseline scope | Keep and slightly strengthen |
| Section 3. Canonical Scope | Strong | Already canonically aligned | The exclusions are correct and preserve authority boundaries | Matches `memberships`, `auth_subjects`, and lesson-content separation in the current baseline | Keep |
| Section 4. Candidate Source Entity | Mixed | Canonically plausible, but too specific | The requirement for a separate feature-specific source model is canonical; the explicit shared entity name and one-model choice are not declared elsewhere | No baseline slot currently materializes any profile/community source model | Split into declared doctrine plus unresolved decisions |
| Section 5. Authored Identity | Mixed | Partially aligned and too specific | It is safe to say media identity remains canonical media identity, but `app.auth_subjects.user_id` as the authored subject binding is not declared for this feature domain | `0014_auth_subjects_core.sql` only declares onboarding/role/admin authority | Rewrite to keep only declared identity doctrine and downgrade the exact subject-binding shape to an unresolved decision |
| Section 6. Allowed Purpose Values | Overreaches | Unsupported and too specific | The canonical source set does not yet declare `profile_media` or `community_media` as `media_purpose` values | `0001_canonical_foundation.sql` defines only `course_cover` and `lesson_media`; `0018_runtime_media_home_player.sql` adds only `home_player_audio` | Remove the chosen values and convert this section into an explicit unresolved decision register |
| Section 7. Relation To Unified `runtime_media` | Strong doctrine, weak timing language | Partially aligned | The chain is correct, but the wording is too close to present-tense authority even though no current baseline path exists | `0017` and `0018` do not include profile/community runtime rows | Rewrite in future-conditional terms and add current baseline status |
| Section 8. Backend Read-Composition Boundary | Strong | Already canonically aligned, but still underpowered | The core rule is correct, but the section should mirror the stronger repository/route prohibitions already declared elsewhere | The current blocker is exactly about mounted runtime paths not inventing their own media payloads | Strengthen with direct doctrine from the active media contract |
| Section 9. Forbidden Legacy Fields And Payload Shapes | Strong | Already aligned, but incomplete | The listed fields are correct, but the list is narrower than the already-declared forbidden media field set | Current baseline and active doctrine already reject broader fallback and URL truth patterns | Keep and extend |
| Section 10. Mounted Surface Implications | Mixed | Aligned doctrine, but too specific in examples | The general rule is correct, but named surface examples are drawn from blocker/runtime context rather than canonical declarations | Baseline does not canonically enumerate profile/community surfaces yet | Rewrite using generic mounted-surface wording only |
| Section 11. Baseline Dependency Boundary | Strong direction | Partially aligned and too vague | The non-core boundary is right, but the section should explicitly mention the current accepted baseline state | `0013`-`0018` show no profile/community source truth or purpose coverage | Strengthen with precise current-baseline statements |
| Section 12. Canonical Acceptance Rule | Correct direction | Partially aligned | The section correctly requires future support, but it should be transformed into an explicit unresolved-decision and activation-criteria section | The current blocker exists because those decisions are still missing | Rewrite as a formal activation gate plus unresolved decision list |

## Cross-Source Comparison Notes

### Already Declared Elsewhere

The following rules are already declared outside the candidate document and can be safely strengthened inside it:

- `runtime_media` is the only runtime truth layer
- backend read composition is the sole frontend representation authority
- profile/community media must not create a second resolver system
- storage-derived truth, signed URLs, and fallback fields are forbidden
- profile/community media is a non-core feature domain requiring an explicit structured contract

### Not Yet Declared Elsewhere

The following candidate claims are not locked by the current source set:

- the exact source entity name `profile_community_media`
- the decision to use one shared source model
- the authored subject-binding choice `app.auth_subjects.user_id`
- the purpose values `profile_media` and `community_media`

### Why Baseline Status Matters

The current baseline is especially important for this review because it proves what is materially accepted now:

- `auth_subjects` is narrow subject authority, not a general feature-domain ownership registry
- `runtime_media` currently covers lesson media, course cover, and home-player media only
- no accepted baseline slot yet materializes profile/community authored-placement truth

Those facts do not reject a future profile/community contract, but they do make the current source-shape choices premature.
