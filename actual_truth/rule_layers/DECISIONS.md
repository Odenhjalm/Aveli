SECTION: DECISIONS RULES

RULE_ID: DECISIONS_0001
SOURCE_FILE: Aveli_System_Decisions.md:5
CATEGORY: DECISIONS
EXACT TEXT:
- Aveli is a social learning platform with courses and lessons as the core runtime learning model, plus live lesson/session experiences and a marketplace for cultivated knowledge.

RULE_ID: DECISIONS_0002
SOURCE_FILE: Aveli_System_Decisions.md:6
CATEGORY: DECISIONS
EXACT TEXT:
- Aveli is for teachers and learners, including course/lesson interactions, checkout/onboarding flows, session-level experiences, and guided app access.

RULE_ID: DECISIONS_0003
SOURCE_FILE: Aveli_System_Decisions.md:7
CATEGORY: DECISIONS
EXACT TEXT:
- Teachers use Aveli to create, manage, publish, and refine learning experiences, media-rich course content, home-player tracks, and cultivated knowledge offers.

RULE_ID: DECISIONS_0004
SOURCE_FILE: Aveli_System_Decisions.md:8
CATEGORY: DECISIONS
EXACT TEXT:
- Learners use Aveli to onboard, access the app through membership, discover courses and lesson structure without course enrollment, access `lesson_content_surface` through explicit course enrollment and `current_unlock_position`, and progress through repeated learning experiences.

RULE_ID: DECISIONS_0005
SOURCE_FILE: Aveli_System_Decisions.md:9
CATEGORY: DECISIONS
EXACT TEXT:
- The user actions explicitly represented in the approved product framing are:

RULE_ID: DECISIONS_0006
SOURCE_FILE: Aveli_System_Decisions.md:10
CATEGORY: DECISIONS
EXACT TEXT:
  - onboard into the trusted teacher/learner journey

RULE_ID: DECISIONS_0007
SOURCE_FILE: Aveli_System_Decisions.md:11
CATEGORY: DECISIONS
EXACT TEXT:
  - enter the app through valid membership access

RULE_ID: DECISIONS_0008
SOURCE_FILE: Aveli_System_Decisions.md:12
CATEGORY: DECISIONS
EXACT TEXT:
  - learn via structured course/editor content

RULE_ID: DECISIONS_0009
SOURCE_FILE: Aveli_System_Decisions.md:13
CATEGORY: DECISIONS
EXACT TEXT:
  - access course content through `canonical_protected_course_content_access`

RULE_ID: DECISIONS_0010
SOURCE_FILE: Aveli_System_Decisions.md:14
CATEGORY: DECISIONS
EXACT TEXT:
  - access curated home-player experiences through the home-player pipeline

RULE_ID: DECISIONS_0011
SOURCE_FILE: Aveli_System_Decisions.md:15
CATEGORY: DECISIONS
EXACT TEXT:
  - progress through repeated, persistent learning experiences

RULE_ID: DECISIONS_0012
SOURCE_FILE: Aveli_System_Decisions.md:16
CATEGORY: DECISIONS
EXACT TEXT:
- Activities, posts, messages, and notifications remain future-facing surfaces unless current runtime evidence explicitly promotes them into baseline truth.

RULE_ID: DECISIONS_0013
SOURCE_FILE: Aveli_System_Decisions.md:17
CATEGORY: DECISIONS
EXACT TEXT:
- The decisions in this file intentionally keep technical choices aligned to these usage intents.

RULE_ID: DECISIONS_0014
SOURCE_FILE: Aveli_System_Decisions.md:21
CATEGORY: DECISIONS
EXACT TEXT:
- Aveli is:

RULE_ID: DECISIONS_0015
SOURCE_FILE: Aveli_System_Decisions.md:22
CATEGORY: DECISIONS
EXACT TEXT:
  - relationship-driven (not content-first)

RULE_ID: DECISIONS_0016
SOURCE_FILE: Aveli_System_Decisions.md:23
CATEGORY: DECISIONS
EXACT TEXT:
  - experience-driven (not file-driven)

RULE_ID: DECISIONS_0017
SOURCE_FILE: Aveli_System_Decisions.md:24
CATEGORY: DECISIONS
EXACT TEXT:
  - progression-based (not static)

RULE_ID: DECISIONS_0018
SOURCE_FILE: Aveli_System_Decisions.md:25
CATEGORY: DECISIONS
EXACT TEXT:
- The system should optimize user trust, continuity, and repeatable workflows before feature surface expansion.

RULE_ID: DECISIONS_0019
SOURCE_FILE: Aveli_System_Decisions.md:26
CATEGORY: DECISIONS
EXACT TEXT:
- Stabilization tasks are allowed only when they preserve these three properties.

RULE_ID: DECISIONS_0020
SOURCE_FILE: Aveli_System_Decisions.md:27
CATEGORY: DECISIONS
EXACT TEXT:
- Semantic precision is mandatory. Aveli must not rely on overlapping names for different authorities.

RULE_ID: DECISIONS_0021
SOURCE_FILE: Aveli_System_Decisions.md:31
CATEGORY: DECISIONS
EXACT TEXT:
- New features must attach to the system via new canonical entities.

RULE_ID: DECISIONS_0022
SOURCE_FILE: Aveli_System_Decisions.md:32
CATEGORY: DECISIONS
EXACT TEXT:
- Core domain entities must remain stable and represent only canonical domain truth.

RULE_ID: DECISIONS_0023
SOURCE_FILE: Aveli_System_Decisions.md:33
CATEGORY: DECISIONS
EXACT TEXT:
- Feature logic must not be embedded into:

RULE_ID: DECISIONS_0024
SOURCE_FILE: Aveli_System_Decisions.md:34
CATEGORY: DECISIONS
EXACT TEXT:
  - `courses`

RULE_ID: DECISIONS_0025
SOURCE_FILE: Aveli_System_Decisions.md:35
CATEGORY: DECISIONS
EXACT TEXT:
  - `lessons`

RULE_ID: DECISIONS_0026
SOURCE_FILE: Aveli_System_Decisions.md:36
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_enrollments`

RULE_ID: DECISIONS_0027
SOURCE_FILE: Aveli_System_Decisions.md:37
CATEGORY: DECISIONS
EXACT TEXT:
  - `media_assets`

RULE_ID: DECISIONS_0028
SOURCE_FILE: Aveli_System_Decisions.md:38
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_media`

RULE_ID: DECISIONS_0029
SOURCE_FILE: Aveli_System_Decisions.md:39
CATEGORY: DECISIONS
EXACT TEXT:
- Feature expansion must happen via new entities such as `live_sessions`, `notifications`, or `marketplace_products`.

RULE_ID: DECISIONS_0030
SOURCE_FILE: Aveli_System_Decisions.md:40
CATEGORY: DECISIONS
EXACT TEXT:
- Mutation of core domain entities to support new features is forbidden.

RULE_ID: DECISIONS_0031
SOURCE_FILE: Aveli_System_Decisions.md:44
CATEGORY: DECISIONS
EXACT TEXT:
- Studio core means only:

RULE_ID: DECISIONS_0032
SOURCE_FILE: Aveli_System_Decisions.md:45
CATEGORY: DECISIONS
EXACT TEXT:
  - course metadata

RULE_ID: DECISIONS_0033
SOURCE_FILE: Aveli_System_Decisions.md:46
CATEGORY: DECISIONS
EXACT TEXT:
  - lesson metadata

RULE_ID: DECISIONS_0034
SOURCE_FILE: Aveli_System_Decisions.md:47
CATEGORY: DECISIONS
EXACT TEXT:
  - lesson content

RULE_ID: DECISIONS_0035
SOURCE_FILE: Aveli_System_Decisions.md:48
CATEGORY: DECISIONS
EXACT TEXT:
- Studio core explicitly excludes:

RULE_ID: DECISIONS_0036
SOURCE_FILE: Aveli_System_Decisions.md:49
CATEGORY: DECISIONS
EXACT TEXT:
  - lesson-media payloads

RULE_ID: DECISIONS_0037
SOURCE_FILE: Aveli_System_Decisions.md:50
CATEGORY: DECISIONS
EXACT TEXT:
  - profile media

RULE_ID: DECISIONS_0038
SOURCE_FILE: Aveli_System_Decisions.md:51
CATEGORY: DECISIONS
EXACT TEXT:
  - studio sessions

RULE_ID: DECISIONS_0039
SOURCE_FILE: Aveli_System_Decisions.md:52
CATEGORY: DECISIONS
EXACT TEXT:
- Studio core must use canonical course and lesson contracts directly.

RULE_ID: DECISIONS_0040
SOURCE_FILE: Aveli_System_Decisions.md:53
CATEGORY: DECISIONS
EXACT TEXT:
- Studio core must not depend on shared legacy `Course` models, raw maps, or legacy lesson aliases.

RULE_ID: DECISIONS_0041
SOURCE_FILE: Aveli_System_Decisions.md:57
CATEGORY: DECISIONS
EXACT TEXT:
- Non-core features must define explicit canonical contracts before they are treated as stable runtime truth.

RULE_ID: DECISIONS_0042
SOURCE_FILE: Aveli_System_Decisions.md:58
CATEGORY: DECISIONS
EXACT TEXT:
- Profile media is a separate feature domain and must use an explicit structured contract.

RULE_ID: DECISIONS_0043
SOURCE_FILE: Aveli_System_Decisions.md:59
CATEGORY: DECISIONS
EXACT TEXT:
- Profile media must not use metadata blobs, map-based identity, or fallback fields as runtime truth.

RULE_ID: DECISIONS_0044
SOURCE_FILE: Aveli_System_Decisions.md:60
CATEGORY: DECISIONS
EXACT TEXT:
- Studio sessions are a separate feature domain and must use a single canonical contract.

RULE_ID: DECISIONS_0045
SOURCE_FILE: Aveli_System_Decisions.md:61
CATEGORY: DECISIONS
EXACT TEXT:
- Studio sessions must not use fallback/default values to hide missing data.

RULE_ID: DECISIONS_0046
SOURCE_FILE: Aveli_System_Decisions.md:62
CATEGORY: DECISIONS
EXACT TEXT:
- Invalid non-core feature input must be rejected explicitly rather than normalized silently.

RULE_ID: DECISIONS_0047
SOURCE_FILE: Aveli_System_Decisions.md:63
CATEGORY: DECISIONS
EXACT TEXT:
- Landing and other external consumers must consume typed contracts.

RULE_ID: DECISIONS_0048
SOURCE_FILE: Aveli_System_Decisions.md:64
CATEGORY: DECISIONS
EXACT TEXT:
- Landing must not consume studio raw data or `Map<String, dynamic>` as runtime truth.

RULE_ID: DECISIONS_0049
SOURCE_FILE: Aveli_System_Decisions.md:68
CATEGORY: DECISIONS
EXACT TEXT:
- A transition layer exists only when canonical backend truth and active consumers still mismatch.

RULE_ID: DECISIONS_0050
SOURCE_FILE: Aveli_System_Decisions.md:69
CATEGORY: DECISIONS
EXACT TEXT:
- A transition layer is allowed only as an explicit, temporary, scoped layer above canonical truth.

RULE_ID: DECISIONS_0051
SOURCE_FILE: Aveli_System_Decisions.md:70
CATEGORY: DECISIONS
EXACT TEXT:
- A transition layer must define:

RULE_ID: DECISIONS_0052
SOURCE_FILE: Aveli_System_Decisions.md:71
CATEGORY: DECISIONS
EXACT TEXT:
  - producer shape

RULE_ID: DECISIONS_0053
SOURCE_FILE: Aveli_System_Decisions.md:72
CATEGORY: DECISIONS
EXACT TEXT:
  - consumer expectation

RULE_ID: DECISIONS_0054
SOURCE_FILE: Aveli_System_Decisions.md:73
CATEGORY: DECISIONS
EXACT TEXT:
  - explicit mapping

RULE_ID: DECISIONS_0055
SOURCE_FILE: Aveli_System_Decisions.md:74
CATEGORY: DECISIONS
EXACT TEXT:
  - removal condition

RULE_ID: DECISIONS_0056
SOURCE_FILE: Aveli_System_Decisions.md:75
CATEGORY: DECISIONS
EXACT TEXT:
- A transition layer must never:

RULE_ID: DECISIONS_0057
SOURCE_FILE: Aveli_System_Decisions.md:76
CATEGORY: DECISIONS
EXACT TEXT:
  - introduce fallback

RULE_ID: DECISIONS_0058
SOURCE_FILE: Aveli_System_Decisions.md:77
CATEGORY: DECISIONS
EXACT TEXT:
  - hide missing data

RULE_ID: DECISIONS_0059
SOURCE_FILE: Aveli_System_Decisions.md:78
CATEGORY: DECISIONS
EXACT TEXT:
  - silently correct invalid input or output

RULE_ID: DECISIONS_0060
SOURCE_FILE: Aveli_System_Decisions.md:79
CATEGORY: DECISIONS
EXACT TEXT:
  - preserve legacy aliases as runtime truth

RULE_ID: DECISIONS_0061
SOURCE_FILE: Aveli_System_Decisions.md:80
CATEGORY: DECISIONS
EXACT TEXT:
  - redefine canonical field names

RULE_ID: DECISIONS_0062
SOURCE_FILE: Aveli_System_Decisions.md:81
CATEGORY: DECISIONS
EXACT TEXT:
- Transition layers are migration mechanisms, not semantic truth.

RULE_ID: DECISIONS_0063
SOURCE_FILE: Aveli_System_Decisions.md:85
CATEGORY: DECISIONS
EXACT TEXT:
- Media is an EXPERIENCE, not a file.

RULE_ID: DECISIONS_0064
SOURCE_FILE: Aveli_System_Decisions.md:86
CATEGORY: DECISIONS
EXACT TEXT:
  - Media routes, identifiers, and control points must remain aligned to user-facing media behavior.

RULE_ID: DECISIONS_0065
SOURCE_FILE: Aveli_System_Decisions.md:87
CATEGORY: DECISIONS
EXACT TEXT:
- Auth is a RELATIONSHIP ENTRY, not a login endpoint.

RULE_ID: DECISIONS_0066
SOURCE_FILE: Aveli_System_Decisions.md:88
CATEGORY: DECISIONS
EXACT TEXT:
  - Auth-related structure is not to be redesigned in this phase.

RULE_ID: DECISIONS_0067
SOURCE_FILE: Aveli_System_Decisions.md:89
CATEGORY: DECISIONS
EXACT TEXT:
- API must reflect REAL system behavior, not hypothetical design.

RULE_ID: DECISIONS_0068
SOURCE_FILE: Aveli_System_Decisions.md:90
CATEGORY: DECISIONS
EXACT TEXT:
  - Canonical API truth remains the audit catalog + usage-diff evidence, but audit evidence describes observed reality and does not itself legitimize legacy behavior.

RULE_ID: DECISIONS_0069
SOURCE_FILE: Aveli_System_Decisions.md:91
CATEGORY: DECISIONS
EXACT TEXT:
- Planned features MUST NOT be removed during stabilization.

RULE_ID: DECISIONS_0070
SOURCE_FILE: Aveli_System_Decisions.md:92
CATEGORY: DECISIONS
EXACT TEXT:
  - Planned and control-plane components are preserved unless explicitly canceled by a documented process outside this phase.

RULE_ID: DECISIONS_0071
SOURCE_FILE: Aveli_System_Decisions.md:93
CATEGORY: DECISIONS
EXACT TEXT:
- Legacy behavior MUST NOT survive through fallback.

RULE_ID: DECISIONS_0072
SOURCE_FILE: Aveli_System_Decisions.md:94
CATEGORY: DECISIONS
EXACT TEXT:
  - If canonical replacement exists, legacy must be removed rather than silently tolerated.

RULE_ID: DECISIONS_0073
SOURCE_FILE: Aveli_System_Decisions.md:95
CATEGORY: DECISIONS
EXACT TEXT:
- Legacy removal requires a clear replacement.

RULE_ID: DECISIONS_0074
SOURCE_FILE: Aveli_System_Decisions.md:96
CATEGORY: DECISIONS
EXACT TEXT:
  - No legacy endpoint, authority, or shortcut may be deleted unless a canonical replacement path is explicitly defined.

RULE_ID: DECISIONS_0075
SOURCE_FILE: Aveli_System_Decisions.md:97
CATEGORY: DECISIONS
EXACT TEXT:
- Map-based contracts and metadata blobs must not become semantic truth.

RULE_ID: DECISIONS_0076
SOURCE_FILE: Aveli_System_Decisions.md:98
CATEGORY: DECISIONS
EXACT TEXT:
- Default values must not hide missing required data.

RULE_ID: DECISIONS_0077
SOURCE_FILE: Aveli_System_Decisions.md:99
CATEGORY: DECISIONS
EXACT TEXT:
- Implicit parsing and silent correction are forbidden.

RULE_ID: DECISIONS_0078
SOURCE_FILE: Aveli_System_Decisions.md:103
CATEGORY: DECISIONS
EXACT TEXT:
- Aveli is the documented system for social learning, course/editor workflows, media delivery, checkout/onboarding support, membership-gated app access, course catalog and lesson structure exposed via explicit read surface, course content accessible through defined API surface only when `course_enrollments` AND `lesson.position <= current_unlock_position`, home-player curation, and marketplace expansion with dedicated API governance, auth/security controls, and control-plane/observability surfaces.

RULE_ID: DECISIONS_0079
SOURCE_FILE: Aveli_System_Decisions.md:104
CATEGORY: DECISIONS
EXACT TEXT:
- Evidence:

RULE_ID: DECISIONS_0080
SOURCE_FILE: Aveli_System_Decisions.md:105
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/README.md

RULE_ID: DECISIONS_0081
SOURCE_FILE: Aveli_System_Decisions.md:106
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/architecture/aveli_editor_architecture_v2.md

RULE_ID: DECISIONS_0082
SOURCE_FILE: Aveli_System_Decisions.md:107
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/verification_mcp.md

RULE_ID: DECISIONS_0083
SOURCE_FILE: Aveli_System_Decisions.md:108
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/WORKFLOW.md

RULE_ID: DECISIONS_0084
SOURCE_FILE: Aveli_System_Decisions.md:112
CATEGORY: DECISIONS
EXACT TEXT:
- `Aveli_System_Decisions.md` is the semantic truth layer.

RULE_ID: DECISIONS_0085
SOURCE_FILE: Aveli_System_Decisions.md:113
CATEGORY: DECISIONS
EXACT TEXT:
- `aveli_system_manifest.json` is the execution-rule layer.

RULE_ID: DECISIONS_0086
SOURCE_FILE: Aveli_System_Decisions.md:114
CATEGORY: DECISIONS
EXACT TEXT:
- If the two documents must be interpreted together:

RULE_ID: DECISIONS_0087
SOURCE_FILE: Aveli_System_Decisions.md:115
CATEGORY: DECISIONS
EXACT TEXT:
  - semantic meaning is governed by decisions

RULE_ID: DECISIONS_0088
SOURCE_FILE: Aveli_System_Decisions.md:116
CATEGORY: DECISIONS
EXACT TEXT:
  - execution and enforcement policy is governed by manifest

RULE_ID: DECISIONS_0089
SOURCE_FILE: Aveli_System_Decisions.md:117
CATEGORY: DECISIONS
EXACT TEXT:
- API audit artifacts describe observed runtime reality and are used for verification and mismatch tracking.

RULE_ID: DECISIONS_0090
SOURCE_FILE: Aveli_System_Decisions.md:118
CATEGORY: DECISIONS
EXACT TEXT:
- Observed runtime reality does NOT automatically become canonical truth.

RULE_ID: DECISIONS_0091
SOURCE_FILE: Aveli_System_Decisions.md:122
CATEGORY: DECISIONS
EXACT TEXT:
- `backend/supabase/baseline_v2_slots` is the canonical baseline source of truth.
- `backend/supabase/baseline_v2_slots.lock.json` is the canonical slot order,
  slot hash, substrate interface, execution profile, and app-owned schema
  verification marker.
- Baseline V2 slots are app-owned schema only.
- Hosted Supabase owns physical `auth` and `storage`; production replay must
  verify those substrate interfaces and must not create them.
- Local development may replay only the locked minimal substrate recorded by
  the V2 lock before app-owned schema replay.

RULE_ID: DECISIONS_0092
SOURCE_FILE: Aveli_System_Decisions.md:123
CATEGORY: DECISIONS
EXACT TEXT:
- Historical baseline slots and legacy DB state are reference-only inputs and MUST NOT redefine canonical media authority.

RULE_ID: DECISIONS_0093
SOURCE_FILE: Aveli_System_Decisions.md:127
CATEGORY: DECISIONS
EXACT TEXT:
- `membership` is the canonical term for app-access authority.

RULE_ID: DECISIONS_0094
SOURCE_FILE: Aveli_System_Decisions.md:128
CATEGORY: DECISIONS
EXACT TEXT:
- `course_enrollment` / `course_enrollments` is the canonical term for `canonical_protected_course_content_access` authority.

RULE_ID: DECISIONS_0095
SOURCE_FILE: Aveli_System_Decisions.md:129
CATEGORY: DECISIONS
EXACT TEXT:
- Canonical data categories are:

RULE_ID: DECISIONS_0096
SOURCE_FILE: Aveli_System_Decisions.md:130
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_identity`

RULE_ID: DECISIONS_0097
SOURCE_FILE: Aveli_System_Decisions.md:131
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_display`

RULE_ID: DECISIONS_0098
SOURCE_FILE: Aveli_System_Decisions.md:132
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_grouping`

RULE_ID: DECISIONS_0099
SOURCE_FILE: Aveli_System_Decisions.md:133
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_pricing`

RULE_ID: DECISIONS_0100
SOURCE_FILE: Aveli_System_Decisions.md:134
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_identity`

RULE_ID: DECISIONS_0101
SOURCE_FILE: Aveli_System_Decisions.md:135
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_structure`

RULE_ID: DECISIONS_0102
SOURCE_FILE: Aveli_System_Decisions.md:136
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_content`

RULE_ID: DECISIONS_0103
SOURCE_FILE: Aveli_System_Decisions.md:137
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_media`

RULE_ID: DECISIONS_0104
SOURCE_FILE: Aveli_System_Decisions.md:138
CATEGORY: DECISIONS
EXACT TEXT:
- Category definitions are semantic law, not fixed field lists. Future fields must map into these categories without changing surface rules.

RULE_ID: DECISIONS_0105
SOURCE_FILE: Aveli_System_Decisions.md:139
CATEGORY: DECISIONS
EXACT TEXT:
- `course_discovery_surface` is the canonical term for a surface that allows only `course_identity`, `course_display`, `course_grouping`, and `course_pricing`.

RULE_ID: DECISIONS_0106
SOURCE_FILE: Aveli_System_Decisions.md:140
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_structure_surface` is the canonical term for a surface that allows only `lesson_identity` and `lesson_structure`.

RULE_ID: DECISIONS_0107
SOURCE_FILE: Aveli_System_Decisions.md:141
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_content_surface` is the canonical term for a surface that allows only `lesson_identity`, `lesson_structure`, `lesson_content`, and `lesson_media`, and requires `course_enrollments` AND `lesson.position <= current_unlock_position`.

RULE_ID: DECISIONS_0108
SOURCE_FILE: Aveli_System_Decisions.md:142
CATEGORY: DECISIONS
EXACT TEXT:
- For learner/public surfaces, `lesson_media` exists only inside `lesson_content_surface`.

RULE_ID: DECISIONS_0109
SOURCE_FILE: Aveli_System_Decisions.md:143
CATEGORY: DECISIONS
EXACT TEXT:
- No independent lesson-media surface exists for learner/public surfaces.

RULE_ID: DECISIONS_0110
SOURCE_FILE: Aveli_System_Decisions.md:144
CATEGORY: DECISIONS
EXACT TEXT:
- Studio authoring may manage `lesson_media` as authored placement, but it must not introduce a second media-resolution or frontend-representation authority.

RULE_ID: DECISIONS_0111
SOURCE_FILE: Aveli_System_Decisions.md:145
CATEGORY: DECISIONS
EXACT TEXT:
- `media_assets` never defines access.

RULE_ID: DECISIONS_0112
SOURCE_FILE: Aveli_System_Decisions.md:146
CATEGORY: DECISIONS
EXACT TEXT:
- No rule referring to visibility may be interpreted as permission for raw table access.

RULE_ID: DECISIONS_0113
SOURCE_FILE: Aveli_System_Decisions.md:147
CATEGORY: DECISIONS
EXACT TEXT:
- `subscription` is NOT a canonical Aveli runtime term.

RULE_ID: DECISIONS_0114
SOURCE_FILE: Aveli_System_Decisions.md:148
CATEGORY: DECISIONS
EXACT TEXT:
  - It may appear only in legacy, migration, audit, or historical references.

RULE_ID: DECISIONS_0115
SOURCE_FILE: Aveli_System_Decisions.md:149
CATEGORY: DECISIONS
EXACT TEXT:
- `module` is NOT a valid Aveli system term.

RULE_ID: DECISIONS_0116
SOURCE_FILE: Aveli_System_Decisions.md:150
CATEGORY: DECISIONS
EXACT TEXT:
  - It is forbidden in runtime/domain language and may appear only in historical or legacy references.

RULE_ID: DECISIONS_0117
SOURCE_FILE: Aveli_System_Decisions.md:151
CATEGORY: DECISIONS
EXACT TEXT:
- Terms that imply duplicate authority for app access or `canonical_protected_course_content_access` must not be introduced.

RULE_ID: DECISIONS_0118
SOURCE_FILE: Aveli_System_Decisions.md:155
CATEGORY: DECISIONS
EXACT TEXT:
- course contains lessons directly

RULE_ID: DECISIONS_0119
SOURCE_FILE: Aveli_System_Decisions.md:156
CATEGORY: DECISIONS
EXACT TEXT:
- `course.group_position` is the only canonical progression field

RULE_ID: DECISIONS_0120
SOURCE_FILE: Aveli_System_Decisions.md:157
CATEGORY: DECISIONS
EXACT TEXT:
- `course.course_group_id` is the only canonical grouping field

RULE_ID: DECISIONS_0121
SOURCE_FILE: Aveli_System_Decisions.md:158
CATEGORY: DECISIONS
EXACT TEXT:
- `course.drip_enabled` and `course.drip_interval_days` are the only canonical drip-configuration fields

RULE_ID: DECISIONS_0122
SOURCE_FILE: Aveli_System_Decisions.md:159
CATEGORY: DECISIONS
EXACT TEXT:
- `course.course_group_id` represents a progression set of courses

RULE_ID: DECISIONS_0123
SOURCE_FILE: Aveli_System_Decisions.md:160
CATEGORY: DECISIONS
EXACT TEXT:
- courses within the same `course_group_id` belong to the same product progression

RULE_ID: DECISIONS_0124
SOURCE_FILE: Aveli_System_Decisions.md:161
CATEGORY: DECISIONS
EXACT TEXT:
- progression within a `course_group_id` is strictly ordered by `course.group_position`

RULE_ID: DECISIONS_0125
SOURCE_FILE: Aveli_System_Decisions.md:162
CATEGORY: DECISIONS
EXACT TEXT:
- `course.course_group_id` is used only for progression linkage and UI sequencing

RULE_ID: DECISIONS_0126
SOURCE_FILE: Aveli_System_Decisions.md:163
CATEGORY: DECISIONS
EXACT TEXT:
- `course.course_group_id` must not be used for categories, tags, or arbitrary grouping

RULE_ID: DECISIONS_0127
SOURCE_FILE: Aveli_System_Decisions.md:164
CATEGORY: DECISIONS
EXACT TEXT:
- drip behavior is course-level configuration only and must not be inferred from course type or enrollment source

RULE_ID: DECISIONS_0128
SOURCE_FILE: Aveli_System_Decisions.md:165
CATEGORY: DECISIONS
EXACT TEXT:
- lessons are ordered via position

RULE_ID: DECISIONS_0129
SOURCE_FILE: Aveli_System_Decisions.md:166
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson.lesson_title` is the canonical lesson display name

RULE_ID: DECISIONS_0130
SOURCE_FILE: Aveli_System_Decisions.md:167
CATEGORY: DECISIONS
EXACT TEXT:
- lesson runtime alias `title` is forbidden

RULE_ID: DECISIONS_0131
SOURCE_FILE: Aveli_System_Decisions.md:168
CATEGORY: DECISIONS
EXACT TEXT:
- `lessons` stores lesson identity and structure only

RULE_ID: DECISIONS_0132
SOURCE_FILE: Aveli_System_Decisions.md:169
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_contents` stores lesson body content only

RULE_ID: DECISIONS_0133
SOURCE_FILE: Aveli_System_Decisions.md:170
CATEGORY: DECISIONS
EXACT TEXT:
- `content_markdown` is canonical only on `lesson_contents`

RULE_ID: DECISIONS_0134
SOURCE_FILE: Aveli_System_Decisions.md:171
CATEGORY: DECISIONS
EXACT TEXT:
- no module abstraction exists

RULE_ID: DECISIONS_0135
SOURCE_FILE: Aveli_System_Decisions.md:172
CATEGORY: DECISIONS
EXACT TEXT:
- any module-like grouping is NOT valid system truth

RULE_ID: DECISIONS_0136
SOURCE_FILE: Aveli_System_Decisions.md:173
CATEGORY: DECISIONS
EXACT TEXT:
- explicit course grouping via `course_group_id` is valid system truth

RULE_ID: DECISIONS_0137
SOURCE_FILE: Aveli_System_Decisions.md:174
CATEGORY: DECISIONS
EXACT TEXT:
- modules are not persisted, exposed, simulated, inferred, or tolerated as runtime/domain truth

RULE_ID: DECISIONS_0138
SOURCE_FILE: Aveli_System_Decisions.md:175
CATEGORY: DECISIONS
EXACT TEXT:
- `module_id` is not part of the canonical course domain model

RULE_ID: DECISIONS_0139
SOURCE_FILE: Aveli_System_Decisions.md:176
CATEGORY: DECISIONS
EXACT TEXT:
- remaining legacy module references in backend/frontend code or docs are implementation debt and must not be used to redefine system truth

RULE_ID: DECISIONS_0140
SOURCE_FILE: Aveli_System_Decisions.md:180
CATEGORY: DECISIONS
EXACT TEXT:
- Media authority model = `identity_runtime_truth_and_backend_representation`

RULE_ID: DECISIONS_0141
SOURCE_FILE: Aveli_System_Decisions.md:181
CATEGORY: DECISIONS
EXACT TEXT:
- App-access authority = `memberships`

RULE_ID: DECISIONS_0142
SOURCE_FILE: Aveli_System_Decisions.md:182
CATEGORY: DECISIONS
EXACT TEXT:
- Canonical course-content access authority = `course_enrollments`

RULE_ID: DECISIONS_0143
SOURCE_FILE: Aveli_System_Decisions.md:183
CATEGORY: DECISIONS
EXACT TEXT:
- Execution authority = `worker`

RULE_ID: DECISIONS_0144
SOURCE_FILE: Aveli_System_Decisions.md:184
CATEGORY: DECISIONS
EXACT TEXT:
- `course_discovery_surface` exposure is not governed by `course_enrollments`

RULE_ID: DECISIONS_0145
SOURCE_FILE: Aveli_System_Decisions.md:185
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_structure_surface` exposure is not governed by `course_enrollments`

RULE_ID: DECISIONS_0146
SOURCE_FILE: Aveli_System_Decisions.md:186
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_content_surface` access must not be derived from membership alone

RULE_ID: DECISIONS_0147
SOURCE_FILE: Aveli_System_Decisions.md:187
CATEGORY: DECISIONS
EXACT TEXT:
- Media identity authority = `app.media_assets`

RULE_ID: DECISIONS_0148
SOURCE_FILE: Aveli_System_Decisions.md:188
CATEGORY: DECISIONS
EXACT TEXT:
- Media authored-placement authority = `app.lesson_media`

RULE_ID: DECISIONS_0149
SOURCE_FILE: Aveli_System_Decisions.md:189
CATEGORY: DECISIONS
EXACT TEXT:
- Runtime truth authority = `runtime_media`

RULE_ID: DECISIONS_0150
SOURCE_FILE: Aveli_System_Decisions.md:190
CATEGORY: DECISIONS
EXACT TEXT:
- Frontend representation authority = `backend_read_composition`

RULE_ID: DECISIONS_0151
SOURCE_FILE: Aveli_System_Decisions.md:191
CATEGORY: DECISIONS
EXACT TEXT:
- Media intent authority = `control_plane`

RULE_ID: DECISIONS_0152
SOURCE_FILE: Aveli_System_Decisions.md:192
CATEGORY: DECISIONS
EXACT TEXT:
- Media lifecycle observability authority = `control_plane`

RULE_ID: DECISIONS_0153
SOURCE_FILE: Aveli_System_Decisions.md:193
CATEGORY: DECISIONS
EXACT TEXT:
- Shape authority = `database`

RULE_ID: DECISIONS_0154
SOURCE_FILE: Aveli_System_Decisions.md:197
CATEGORY: DECISIONS
EXACT TEXT:
- `app.media_assets` is media identity.

RULE_ID: DECISIONS_0155
SOURCE_FILE: Aveli_System_Decisions.md:198
CATEGORY: DECISIONS
EXACT TEXT:
- `app.lesson_media` is authored placement.

RULE_ID: DECISIONS_0156
SOURCE_FILE: Aveli_System_Decisions.md:199
CATEGORY: DECISIONS
EXACT TEXT:
- `app.runtime_media` is the runtime truth layer for media state and resolution eligibility.

RULE_ID: DECISIONS_0157
SOURCE_FILE: Aveli_System_Decisions.md:200
CATEGORY: DECISIONS
EXACT TEXT:
- `runtime_media` is NOT the final frontend representation.

RULE_ID: DECISIONS_0158
SOURCE_FILE: Aveli_System_Decisions.md:201
CATEGORY: DECISIONS
EXACT TEXT:
- The backend read composition layer constructs the frontend-facing media object only as `media = { media_id, state, resolved_url } | null`.

RULE_ID: DECISIONS_0159
SOURCE_FILE: Aveli_System_Decisions.md:203-205
CATEGORY: DECISIONS
EXACT TEXT:
runtime_media provides canonical runtime truth.
The backend read composition layer is the sole authority for media representation to frontend.
Frontend must render only and must not resolve or construct media.

RULE_ID: DECISIONS_0160
SOURCE_FILE: Aveli_System_Decisions.md:209
CATEGORY: DECISIONS
EXACT TEXT:
- `control_plane` is the only authority for:

RULE_ID: DECISIONS_0161
SOURCE_FILE: Aveli_System_Decisions.md:210
CATEGORY: DECISIONS
EXACT TEXT:
  - media intent

RULE_ID: DECISIONS_0162
SOURCE_FILE: Aveli_System_Decisions.md:211
CATEGORY: DECISIONS
EXACT TEXT:
  - pipeline expectations

RULE_ID: DECISIONS_0163
SOURCE_FILE: Aveli_System_Decisions.md:212
CATEGORY: DECISIONS
EXACT TEXT:
  - lifecycle interpretation

RULE_ID: DECISIONS_0164
SOURCE_FILE: Aveli_System_Decisions.md:213
CATEGORY: DECISIONS
EXACT TEXT:
- `control_plane` lifecycle observability classifications are:

RULE_ID: DECISIONS_0165
SOURCE_FILE: Aveli_System_Decisions.md:214
CATEGORY: DECISIONS
EXACT TEXT:
  - `valid` when canonical media state can produce deterministic `runtime_media` truth and the read layer can emit the canonical media object without fallback

RULE_ID: DECISIONS_0166
SOURCE_FILE: Aveli_System_Decisions.md:215
CATEGORY: DECISIONS
EXACT TEXT:
  - `broken` when canonical media state should resolve but runtime truth cannot produce the canonical media object

RULE_ID: DECISIONS_0167
SOURCE_FILE: Aveli_System_Decisions.md:216
CATEGORY: DECISIONS
EXACT TEXT:
  - `stuck` when `state = processing` with no progress

RULE_ID: DECISIONS_0168
SOURCE_FILE: Aveli_System_Decisions.md:217
CATEGORY: DECISIONS
EXACT TEXT:
  - `invalid` when canonical format or identity rules are violated

RULE_ID: DECISIONS_0169
SOURCE_FILE: Aveli_System_Decisions.md:218
CATEGORY: DECISIONS
EXACT TEXT:
- Lifecycle classification must be derived from existing canonical state only.

RULE_ID: DECISIONS_0170
SOURCE_FILE: Aveli_System_Decisions.md:219
CATEGORY: DECISIONS
EXACT TEXT:
- Lifecycle classification must not introduce additional state fields.

RULE_ID: DECISIONS_0171
SOURCE_FILE: Aveli_System_Decisions.md:220
CATEGORY: DECISIONS
EXACT TEXT:
- Lifecycle classification must not depend on runtime or frontend logic.

RULE_ID: DECISIONS_0172
SOURCE_FILE: Aveli_System_Decisions.md:221
CATEGORY: DECISIONS
EXACT TEXT:
- `control_plane` does NOT:

RULE_ID: DECISIONS_0173
SOURCE_FILE: Aveli_System_Decisions.md:222
CATEGORY: DECISIONS
EXACT TEXT:
  - execute media processing

RULE_ID: DECISIONS_0174
SOURCE_FILE: Aveli_System_Decisions.md:223
CATEGORY: DECISIONS
EXACT TEXT:
  - mutate media state

RULE_ID: DECISIONS_0175
SOURCE_FILE: Aveli_System_Decisions.md:224
CATEGORY: DECISIONS
EXACT TEXT:
  - perform runtime-media resolution

RULE_ID: DECISIONS_0176
SOURCE_FILE: Aveli_System_Decisions.md:225
CATEGORY: DECISIONS
EXACT TEXT:
  - construct frontend media representation

RULE_ID: DECISIONS_0177
SOURCE_FILE: Aveli_System_Decisions.md:226
CATEGORY: DECISIONS
EXACT TEXT:
  - perform media delivery

RULE_ID: DECISIONS_0178
SOURCE_FILE: Aveli_System_Decisions.md:227
CATEGORY: DECISIONS
EXACT TEXT:
  - enforce DB constraints

RULE_ID: DECISIONS_0179
SOURCE_FILE: Aveli_System_Decisions.md:228
CATEGORY: DECISIONS
EXACT TEXT:
- Worker is the only execution authority.

RULE_ID: DECISIONS_0180
SOURCE_FILE: Aveli_System_Decisions.md:229
CATEGORY: DECISIONS
EXACT TEXT:
- Worker owns media transformations and canonical state transitions only through the canonical worker function.

RULE_ID: DECISIONS_0181
SOURCE_FILE: Aveli_System_Decisions.md:230
CATEGORY: DECISIONS
EXACT TEXT:
- Worker does NOT define media intent, runtime truth, or frontend representation rules.

RULE_ID: DECISIONS_0182
SOURCE_FILE: Aveli_System_Decisions.md:231
CATEGORY: DECISIONS
EXACT TEXT:
- `runtime_media` is the only runtime truth layer for governed media surfaces.

RULE_ID: DECISIONS_0183
SOURCE_FILE: Aveli_System_Decisions.md:232
CATEGORY: DECISIONS
EXACT TEXT:
- Runtime owns media state and resolution eligibility only and may reject invalid runtime state.

RULE_ID: DECISIONS_0184
SOURCE_FILE: Aveli_System_Decisions.md:233
CATEGORY: DECISIONS
EXACT TEXT:
- Runtime does NOT define frontend representation, validate pipeline rules outside canonical state, access ingest identity as public truth, or perform transformation.

RULE_ID: DECISIONS_0185
SOURCE_FILE: Aveli_System_Decisions.md:234
CATEGORY: DECISIONS
EXACT TEXT:
- Database is the only shape authority.

RULE_ID: DECISIONS_0186
SOURCE_FILE: Aveli_System_Decisions.md:235
CATEGORY: DECISIONS
EXACT TEXT:
- Database enforces schema shape and invariants only.

RULE_ID: DECISIONS_0187
SOURCE_FILE: Aveli_System_Decisions.md:236
CATEGORY: DECISIONS
EXACT TEXT:
- Database does NOT define behavior or infer meaning.

RULE_ID: DECISIONS_0188
SOURCE_FILE: Aveli_System_Decisions.md:240
CATEGORY: DECISIONS
EXACT TEXT:
- `membership` is required to pass landing and enter the app.

RULE_ID: DECISIONS_0189
SOURCE_FILE: Aveli_System_Decisions.md:241
CATEGORY: DECISIONS
EXACT TEXT:
- `membership` is global platform access, not creator-scoped.

RULE_ID: DECISIONS_0190
SOURCE_FILE: Aveli_System_Decisions.md:242
CATEGORY: DECISIONS
EXACT TEXT:
- `course_discovery_surface` is separate from `lesson_content_surface`.

RULE_ID: DECISIONS_0191
SOURCE_FILE: Aveli_System_Decisions.md:243
CATEGORY: DECISIONS
EXACT TEXT:
- `course_discovery_surface` allows only:

RULE_ID: DECISIONS_0192
SOURCE_FILE: Aveli_System_Decisions.md:244
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_identity`

RULE_ID: DECISIONS_0193
SOURCE_FILE: Aveli_System_Decisions.md:245
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_display`

RULE_ID: DECISIONS_0194
SOURCE_FILE: Aveli_System_Decisions.md:246
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_grouping`

RULE_ID: DECISIONS_0195
SOURCE_FILE: Aveli_System_Decisions.md:247
CATEGORY: DECISIONS
EXACT TEXT:
  - `course_pricing`

RULE_ID: DECISIONS_0196
SOURCE_FILE: Aveli_System_Decisions.md:248
CATEGORY: DECISIONS
EXACT TEXT:
- Forbidden categories must never appear on `course_discovery_surface`:

RULE_ID: DECISIONS_0197
SOURCE_FILE: Aveli_System_Decisions.md:249
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_content`

RULE_ID: DECISIONS_0198
SOURCE_FILE: Aveli_System_Decisions.md:250
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_media`

RULE_ID: DECISIONS_0199
SOURCE_FILE: Aveli_System_Decisions.md:251
CATEGORY: DECISIONS
EXACT TEXT:
  - `enrollment_state`

RULE_ID: DECISIONS_0200
SOURCE_FILE: Aveli_System_Decisions.md:252
CATEGORY: DECISIONS
EXACT TEXT:
  - `unlock_state`

RULE_ID: DECISIONS_0201
SOURCE_FILE: Aveli_System_Decisions.md:253
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_structure_surface` allows only:

RULE_ID: DECISIONS_0202
SOURCE_FILE: Aveli_System_Decisions.md:254
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_identity`

RULE_ID: DECISIONS_0203
SOURCE_FILE: Aveli_System_Decisions.md:255
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_structure`

RULE_ID: DECISIONS_0204
SOURCE_FILE: Aveli_System_Decisions.md:256
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_structure_surface` maps to `lessons` only.

RULE_ID: DECISIONS_0205
SOURCE_FILE: Aveli_System_Decisions.md:257
CATEGORY: DECISIONS
EXACT TEXT:
- Forbidden categories must never appear on `lesson_structure_surface`:

RULE_ID: DECISIONS_0206
SOURCE_FILE: Aveli_System_Decisions.md:258
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_content`

RULE_ID: DECISIONS_0207
SOURCE_FILE: Aveli_System_Decisions.md:259
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_media`

RULE_ID: DECISIONS_0208
SOURCE_FILE: Aveli_System_Decisions.md:260
CATEGORY: DECISIONS
EXACT TEXT:
  - `enrollment_state`

RULE_ID: DECISIONS_0209
SOURCE_FILE: Aveli_System_Decisions.md:261
CATEGORY: DECISIONS
EXACT TEXT:
  - `unlock_state`

RULE_ID: DECISIONS_0210
SOURCE_FILE: Aveli_System_Decisions.md:262
CATEGORY: DECISIONS
EXACT TEXT:
- `course_enrollments` is the only canonical authority for `canonical_protected_course_content_access`.

RULE_ID: DECISIONS_0211
SOURCE_FILE: Aveli_System_Decisions.md:263
CATEGORY: DECISIONS
EXACT TEXT:
- `canonical_protected_course_content_access` means a lesson is accessible if and only if:

RULE_ID: DECISIONS_0212
SOURCE_FILE: Aveli_System_Decisions.md:264
CATEGORY: DECISIONS
EXACT TEXT:
  - a `course_enrollments` row exists for `(user_id, course_id)`

RULE_ID: DECISIONS_0213
SOURCE_FILE: Aveli_System_Decisions.md:265
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson.position <= current_unlock_position`

RULE_ID: DECISIONS_0214
SOURCE_FILE: Aveli_System_Decisions.md:266
CATEGORY: DECISIONS
EXACT TEXT:
- `current_unlock_position` is stored on `course_enrollments`.

RULE_ID: DECISIONS_0215
SOURCE_FILE: Aveli_System_Decisions.md:267
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_content_surface` allows only `lesson_identity`, `lesson_structure`, `lesson_content`, and `lesson_media`.

RULE_ID: DECISIONS_0216
SOURCE_FILE: Aveli_System_Decisions.md:268
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_content_surface` maps to `lessons` + `lesson_contents` + `lesson_media`.

RULE_ID: DECISIONS_0217
SOURCE_FILE: Aveli_System_Decisions.md:269
CATEGORY: DECISIONS
EXACT TEXT:
- For learner/public surfaces, `lesson_media` exists only inside `lesson_content_surface`.

RULE_ID: DECISIONS_0218
SOURCE_FILE: Aveli_System_Decisions.md:270
CATEGORY: DECISIONS
EXACT TEXT:
- Intro courses require `course_enrollments` rows with `source = intro_enrollment`, and `lesson_content_surface` still requires `lesson.position <= current_unlock_position`.

RULE_ID: DECISIONS_0219
SOURCE_FILE: Aveli_System_Decisions.md:271
CATEGORY: DECISIONS
EXACT TEXT:
- No lesson content or lesson media access exists outside `course_enrollments` AND `lesson.position <= current_unlock_position`.

RULE_ID: DECISIONS_0220
SOURCE_FILE: Aveli_System_Decisions.md:272
CATEGORY: DECISIONS
EXACT TEXT:
- `media_assets` never defines access.

RULE_ID: DECISIONS_0221
SOURCE_FILE: Aveli_System_Decisions.md:273
CATEGORY: DECISIONS
EXACT TEXT:
- No rule referring to visibility may be interpreted as permission for raw table access.

RULE_ID: DECISIONS_0222
SOURCE_FILE: Aveli_System_Decisions.md:274
CATEGORY: DECISIONS
EXACT TEXT:
- Checkout may canonically produce:

RULE_ID: DECISIONS_0223
SOURCE_FILE: Aveli_System_Decisions.md:275
CATEGORY: DECISIONS
EXACT TEXT:
  - membership

RULE_ID: DECISIONS_0224
SOURCE_FILE: Aveli_System_Decisions.md:276
CATEGORY: DECISIONS
EXACT TEXT:
  - course_enrollment

RULE_ID: DECISIONS_0225
SOURCE_FILE: Aveli_System_Decisions.md:277
CATEGORY: DECISIONS
EXACT TEXT:
  - both

RULE_ID: DECISIONS_0226
SOURCE_FILE: Aveli_System_Decisions.md:278
CATEGORY: DECISIONS
EXACT TEXT:
- Checkout outcome is product-dependent, not guessed from legacy terminology.

RULE_ID: DECISIONS_0227
SOURCE_FILE: Aveli_System_Decisions.md:282
CATEGORY: DECISIONS
EXACT TEXT:
- `GET /courses` is `course_discovery_surface`.

RULE_ID: DECISIONS_0228
SOURCE_FILE: Aveli_System_Decisions.md:283
CATEGORY: DECISIONS
EXACT TEXT:
- `GET /courses/{course_id}` is a course-detail endpoint composed of `course_discovery_surface` and `lesson_structure_surface` and must not require enrollment.

RULE_ID: DECISIONS_0229
SOURCE_FILE: Aveli_System_Decisions.md:284
CATEGORY: DECISIONS
EXACT TEXT:
- `GET /courses/by-slug/{slug}` is a course-detail endpoint composed of `course_discovery_surface` and `lesson_structure_surface` and must not require enrollment.

RULE_ID: DECISIONS_0230
SOURCE_FILE: Aveli_System_Decisions.md:285
CATEGORY: DECISIONS
EXACT TEXT:
- Course-detail endpoints may return lessons only as `LessonSummary[]` on `lesson_structure_surface`.

RULE_ID: DECISIONS_0231
SOURCE_FILE: Aveli_System_Decisions.md:286
CATEGORY: DECISIONS
EXACT TEXT:
- `LessonSummary` is the `lesson_structure_surface` shape and allows only:

RULE_ID: DECISIONS_0232
SOURCE_FILE: Aveli_System_Decisions.md:287
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_identity`

RULE_ID: DECISIONS_0233
SOURCE_FILE: Aveli_System_Decisions.md:288
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_structure`

RULE_ID: DECISIONS_0234
SOURCE_FILE: Aveli_System_Decisions.md:289
CATEGORY: DECISIONS
EXACT TEXT:
- `LessonSummary` is sourced from `lessons` only.

RULE_ID: DECISIONS_0235
SOURCE_FILE: Aveli_System_Decisions.md:290
CATEGORY: DECISIONS
EXACT TEXT:
- Forbidden categories must never appear in `LessonSummary`:

RULE_ID: DECISIONS_0236
SOURCE_FILE: Aveli_System_Decisions.md:291
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_content`

RULE_ID: DECISIONS_0237
SOURCE_FILE: Aveli_System_Decisions.md:292
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_media`

RULE_ID: DECISIONS_0238
SOURCE_FILE: Aveli_System_Decisions.md:293
CATEGORY: DECISIONS
EXACT TEXT:
  - `enrollment_state`

RULE_ID: DECISIONS_0239
SOURCE_FILE: Aveli_System_Decisions.md:294
CATEGORY: DECISIONS
EXACT TEXT:
  - `unlock_state`

RULE_ID: DECISIONS_0240
SOURCE_FILE: Aveli_System_Decisions.md:295
CATEGORY: DECISIONS
EXACT TEXT:
- `GET /courses/lessons/{lesson_id}` is `lesson_content_surface`.

RULE_ID: DECISIONS_0241
SOURCE_FILE: Aveli_System_Decisions.md:296
CATEGORY: DECISIONS
EXACT TEXT:
- `LessonContent` is the `lesson_content_surface` shape and allows only:

RULE_ID: DECISIONS_0242
SOURCE_FILE: Aveli_System_Decisions.md:297
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_identity`

RULE_ID: DECISIONS_0243
SOURCE_FILE: Aveli_System_Decisions.md:298
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_structure`

RULE_ID: DECISIONS_0244
SOURCE_FILE: Aveli_System_Decisions.md:299
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_content`

RULE_ID: DECISIONS_0245
SOURCE_FILE: Aveli_System_Decisions.md:300
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_media`

RULE_ID: DECISIONS_0246
SOURCE_FILE: Aveli_System_Decisions.md:301
CATEGORY: DECISIONS
EXACT TEXT:
- `LessonContent` is sourced from canonical `lessons` + `lesson_contents` + `lesson_media`.

RULE_ID: DECISIONS_0247
SOURCE_FILE: Aveli_System_Decisions.md:302
CATEGORY: DECISIONS
EXACT TEXT:
- `LessonContent` requires `course_enrollments` AND `lesson.position <= current_unlock_position`.

RULE_ID: DECISIONS_0248
SOURCE_FILE: Aveli_System_Decisions.md:303
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_media` exists only inside `LessonContent`.

RULE_ID: DECISIONS_0249
SOURCE_FILE: Aveli_System_Decisions.md:304
CATEGORY: DECISIONS
EXACT TEXT:
- No endpoint may return `lesson_content` or `lesson_media` without `course_enrollments` AND `lesson.position <= current_unlock_position`.

RULE_ID: DECISIONS_0250
SOURCE_FILE: Aveli_System_Decisions.md:305
CATEGORY: DECISIONS
EXACT TEXT:
- No rule referring to visibility may be interpreted as permission for raw table access.

RULE_ID: DECISIONS_0251
SOURCE_FILE: Aveli_System_Decisions.md:306
CATEGORY: DECISIONS
EXACT TEXT:
- `app.lessons` must remain structure-only and `app.lesson_contents` must remain content-only.

RULE_ID: DECISIONS_0252
SOURCE_FILE: Aveli_System_Decisions.md:307
CATEGORY: DECISIONS
EXACT TEXT:
- `app.lessons` and `app.lesson_contents` must not be collapsed into one raw-table lesson access surface that bypasses canonical surface boundaries.

RULE_ID: DECISIONS_0253
SOURCE_FILE: Aveli_System_Decisions.md:311
CATEGORY: DECISIONS
EXACT TEXT:
- Runtime contracts must be typed and explicit.

RULE_ID: DECISIONS_0254
SOURCE_FILE: Aveli_System_Decisions.md:312
CATEGORY: DECISIONS
EXACT TEXT:
- `Map<String, dynamic>` must not be used as runtime truth.

RULE_ID: DECISIONS_0255
SOURCE_FILE: Aveli_System_Decisions.md:313
CATEGORY: DECISIONS
EXACT TEXT:
- Metadata blobs must not act as identity, authority, or compatibility contract surfaces.

RULE_ID: DECISIONS_0256
SOURCE_FILE: Aveli_System_Decisions.md:314
CATEGORY: DECISIONS
EXACT TEXT:
- Landing must consume typed contracts rather than studio raw payloads.

RULE_ID: DECISIONS_0257
SOURCE_FILE: Aveli_System_Decisions.md:315
CATEGORY: DECISIONS
EXACT TEXT:
- Lesson naming law is global:

RULE_ID: DECISIONS_0258
SOURCE_FILE: Aveli_System_Decisions.md:316
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson_title` is canonical everywhere

RULE_ID: DECISIONS_0259
SOURCE_FILE: Aveli_System_Decisions.md:317
CATEGORY: DECISIONS
EXACT TEXT:
  - `title` is forbidden as a runtime lesson alias

RULE_ID: DECISIONS_0260
SOURCE_FILE: Aveli_System_Decisions.md:321
CATEGORY: DECISIONS
EXACT TEXT:
- Drip is a course-level configuration.

RULE_ID: DECISIONS_0261
SOURCE_FILE: Aveli_System_Decisions.md:322
CATEGORY: DECISIONS
EXACT TEXT:
- Drip is not tied to enrollment source.

RULE_ID: DECISIONS_0262
SOURCE_FILE: Aveli_System_Decisions.md:323
CATEGORY: DECISIONS
EXACT TEXT:
- Teacher controls:

RULE_ID: DECISIONS_0263
SOURCE_FILE: Aveli_System_Decisions.md:324
CATEGORY: DECISIONS
EXACT TEXT:
  - `drip_enabled`

RULE_ID: DECISIONS_0264
SOURCE_FILE: Aveli_System_Decisions.md:325
CATEGORY: DECISIONS
EXACT TEXT:
  - `drip_interval_days`

RULE_ID: DECISIONS_0265
SOURCE_FILE: Aveli_System_Decisions.md:326
CATEGORY: DECISIONS
EXACT TEXT:
- `course_enrollments` is the only source of `canonical_protected_course_content_access` truth.

RULE_ID: DECISIONS_0266
SOURCE_FILE: Aveli_System_Decisions.md:327
CATEGORY: DECISIONS
EXACT TEXT:
- Intro courses require explicit enrollment with `source = intro_enrollment`, and `lesson_content_surface` access still requires `lesson.position <= current_unlock_position`.

RULE_ID: DECISIONS_0267
SOURCE_FILE: Aveli_System_Decisions.md:328
CATEGORY: DECISIONS
EXACT TEXT:
- Paid courses require explicit enrollment with `source = purchase`, and `lesson_content_surface` access still requires `lesson.position <= current_unlock_position`.

RULE_ID: DECISIONS_0268
SOURCE_FILE: Aveli_System_Decisions.md:329
CATEGORY: DECISIONS
EXACT TEXT:
- Enrollment stores state only.

RULE_ID: DECISIONS_0269
SOURCE_FILE: Aveli_System_Decisions.md:330
CATEGORY: DECISIONS
EXACT TEXT:
- Enrollment always stores `drip_started_at` and `current_unlock_position`.

RULE_ID: DECISIONS_0270
SOURCE_FILE: Aveli_System_Decisions.md:331
CATEGORY: DECISIONS
EXACT TEXT:
- Enrollment source records access origin and does not define drip behavior.

RULE_ID: DECISIONS_0271
SOURCE_FILE: Aveli_System_Decisions.md:332
CATEGORY: DECISIONS
EXACT TEXT:
- The system must not assume default drip behavior.

RULE_ID: DECISIONS_0272
SOURCE_FILE: Aveli_System_Decisions.md:333
CATEGORY: DECISIONS
EXACT TEXT:
- The system must not infer drip from course type.

RULE_ID: DECISIONS_0273
SOURCE_FILE: Aveli_System_Decisions.md:334
CATEGORY: DECISIONS
EXACT TEXT:
- Drip progression is stored state, not derived state.

RULE_ID: DECISIONS_0274
SOURCE_FILE: Aveli_System_Decisions.md:335
CATEGORY: DECISIONS
EXACT TEXT:
- On creation of any enrollment, `drip_started_at = granted_at`.

RULE_ID: DECISIONS_0275
SOURCE_FILE: Aveli_System_Decisions.md:336
CATEGORY: DECISIONS
EXACT TEXT:
- On creation of an enrollment for a course with `drip_enabled = true`:

RULE_ID: DECISIONS_0276
SOURCE_FILE: Aveli_System_Decisions.md:337
CATEGORY: DECISIONS
EXACT TEXT:
  - if the course has at least one lesson, `current_unlock_position = 1`

RULE_ID: DECISIONS_0277
SOURCE_FILE: Aveli_System_Decisions.md:338
CATEGORY: DECISIONS
EXACT TEXT:
  - if the course has zero lessons, `current_unlock_position = 0`

RULE_ID: DECISIONS_0278
SOURCE_FILE: Aveli_System_Decisions.md:339
CATEGORY: DECISIONS
EXACT TEXT:
- On creation of an enrollment for a course with `drip_enabled = false`:

RULE_ID: DECISIONS_0279
SOURCE_FILE: Aveli_System_Decisions.md:340
CATEGORY: DECISIONS
EXACT TEXT:
  - if the course has at least one lesson, `current_unlock_position = max_lesson_position`

RULE_ID: DECISIONS_0280
SOURCE_FILE: Aveli_System_Decisions.md:341
CATEGORY: DECISIONS
EXACT TEXT:
  - if the course has zero lessons, `current_unlock_position = 0`

RULE_ID: DECISIONS_0281
SOURCE_FILE: Aveli_System_Decisions.md:342
CATEGORY: DECISIONS
EXACT TEXT:
- Drip progression is advanced only by a worker process.

RULE_ID: DECISIONS_0282
SOURCE_FILE: Aveli_System_Decisions.md:343
CATEGORY: DECISIONS
EXACT TEXT:
- The worker runs on a fixed cron-based interval.

RULE_ID: DECISIONS_0283
SOURCE_FILE: Aveli_System_Decisions.md:344
CATEGORY: DECISIONS
EXACT TEXT:
- The worker evaluates enrollments only for courses where `drip_enabled = true`.

RULE_ID: DECISIONS_0284
SOURCE_FILE: Aveli_System_Decisions.md:345
CATEGORY: DECISIONS
EXACT TEXT:
- Worker-based scheduling is the canonical way to advance drip progression.

RULE_ID: DECISIONS_0285
SOURCE_FILE: Aveli_System_Decisions.md:346
CATEGORY: DECISIONS
EXACT TEXT:
- No lazy evaluation of unlock state is allowed in runtime.

RULE_ID: DECISIONS_0286
SOURCE_FILE: Aveli_System_Decisions.md:347
CATEGORY: DECISIONS
EXACT TEXT:
- Runtime requests must never advance drip state.

RULE_ID: DECISIONS_0287
SOURCE_FILE: Aveli_System_Decisions.md:348
CATEGORY: DECISIONS
EXACT TEXT:
- Frontend must never compute unlock state.

RULE_ID: DECISIONS_0288
SOURCE_FILE: Aveli_System_Decisions.md:349
CATEGORY: DECISIONS
EXACT TEXT:
- UI must reflect drip configuration consistently in course cards and course views.

RULE_ID: DECISIONS_0289
SOURCE_FILE: Aveli_System_Decisions.md:350
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson.position` is the canonical progression index.

RULE_ID: DECISIONS_0290
SOURCE_FILE: Aveli_System_Decisions.md:351
CATEGORY: DECISIONS
EXACT TEXT:
- `current_unlock_position` is the canonical persisted highest accessible `lesson.position`.

RULE_ID: DECISIONS_0291
SOURCE_FILE: Aveli_System_Decisions.md:352
CATEGORY: DECISIONS
EXACT TEXT:
- Worker progression updates are determined by:

RULE_ID: DECISIONS_0292
SOURCE_FILE: Aveli_System_Decisions.md:353
CATEGORY: DECISIONS
EXACT TEXT:
  - `drip_started_at`

RULE_ID: DECISIONS_0293
SOURCE_FILE: Aveli_System_Decisions.md:354
CATEGORY: DECISIONS
EXACT TEXT:
  - `lesson.position`

RULE_ID: DECISIONS_0294
SOURCE_FILE: Aveli_System_Decisions.md:355
CATEGORY: DECISIONS
EXACT TEXT:
  - `course.drip_interval_days`

RULE_ID: DECISIONS_0295
SOURCE_FILE: Aveli_System_Decisions.md:356
CATEGORY: DECISIONS
EXACT TEXT:
- Canonical worker formula:

RULE_ID: DECISIONS_0296
SOURCE_FILE: Aveli_System_Decisions.md:357
CATEGORY: DECISIONS
EXACT TEXT:
  - `unlocked_count = 1 + floor((now - drip_started_at) / (course.drip_interval_days days))`

RULE_ID: DECISIONS_0297
SOURCE_FILE: Aveli_System_Decisions.md:358
CATEGORY: DECISIONS
EXACT TEXT:
  - `computed_unlock_position = min(max_lesson_position, unlocked_count)`

RULE_ID: DECISIONS_0298
SOURCE_FILE: Aveli_System_Decisions.md:359
CATEGORY: DECISIONS
EXACT TEXT:
- `current_unlock_position` must never exceed the highest existing `lesson.position` in the course.

RULE_ID: DECISIONS_0299
SOURCE_FILE: Aveli_System_Decisions.md:360
CATEGORY: DECISIONS
EXACT TEXT:
- If `current_unlock_position` already equals `max_lesson_position`, worker execution must be a no-op.

RULE_ID: DECISIONS_0300
SOURCE_FILE: Aveli_System_Decisions.md:361
CATEGORY: DECISIONS
EXACT TEXT:
- Worker runs must be deterministic.

RULE_ID: DECISIONS_0301
SOURCE_FILE: Aveli_System_Decisions.md:362
CATEGORY: DECISIONS
EXACT TEXT:
- Repeated worker executions in the same cron window must produce the same persisted result.

RULE_ID: DECISIONS_0302
SOURCE_FILE: Aveli_System_Decisions.md:363
CATEGORY: DECISIONS
EXACT TEXT:
- Worker may only update when `computed_unlock_position > current_unlock_position`.

RULE_ID: DECISIONS_0303
SOURCE_FILE: Aveli_System_Decisions.md:364
CATEGORY: DECISIONS
EXACT TEXT:
- Worker must never decrease `current_unlock_position`.

RULE_ID: DECISIONS_0304
SOURCE_FILE: Aveli_System_Decisions.md:368
CATEGORY: DECISIONS
EXACT TEXT:
- All audio must pass the worker pipeline.

RULE_ID: DECISIONS_0305
SOURCE_FILE: Aveli_System_Decisions.md:369
CATEGORY: DECISIONS
EXACT TEXT:
- WAV must become MP3 before `ready`.

RULE_ID: DECISIONS_0306
SOURCE_FILE: Aveli_System_Decisions.md:370
CATEGORY: DECISIONS
EXACT TEXT:
- Audio `ready` requires `media_assets.playback_format = mp3`.

RULE_ID: DECISIONS_0307
SOURCE_FILE: Aveli_System_Decisions.md:371
CATEGORY: DECISIONS
EXACT TEXT:
- No direct `ready` writes are allowed for audio.

RULE_ID: DECISIONS_0308
SOURCE_FILE: Aveli_System_Decisions.md:372
CATEGORY: DECISIONS
EXACT TEXT:
- Canonical worker mutation authority for media readiness is a single security-definer function.

RULE_ID: DECISIONS_0309
SOURCE_FILE: Aveli_System_Decisions.md:373
CATEGORY: DECISIONS
EXACT TEXT:
- Media readiness mutation must occur only through the canonical worker function.

RULE_ID: DECISIONS_0310
SOURCE_FILE: Aveli_System_Decisions.md:374
CATEGORY: DECISIONS
EXACT TEXT:
- The canonical worker function is the only allowed mutation boundary for audio state transitions that lead to `media_assets.state = ready`.

RULE_ID: DECISIONS_0311
SOURCE_FILE: Aveli_System_Decisions.md:375
CATEGORY: DECISIONS
EXACT TEXT:
- The canonical worker function assigns `media_assets.playback_format = mp3` during canonical audio processing.

RULE_ID: DECISIONS_0312
SOURCE_FILE: Aveli_System_Decisions.md:376
CATEGORY: DECISIONS
EXACT TEXT:
- Direct `UPDATE` to `media_assets.state = ready` is forbidden.

RULE_ID: DECISIONS_0313
SOURCE_FILE: Aveli_System_Decisions.md:377
CATEGORY: DECISIONS
EXACT TEXT:
- No API path, migration path, trigger path, or ad-hoc SQL path may mark audio `ready` outside the canonical worker function.

RULE_ID: DECISIONS_0314
SOURCE_FILE: Aveli_System_Decisions.md:378
CATEGORY: DECISIONS
EXACT TEXT:
- There is no alternate media-readiness mutation path.

RULE_ID: DECISIONS_0315
SOURCE_FILE: Aveli_System_Decisions.md:382
CATEGORY: DECISIONS
EXACT TEXT:
- Home player is part of the same media domain.

RULE_ID: DECISIONS_0316
SOURCE_FILE: Aveli_System_Decisions.md:383
CATEGORY: DECISIONS
EXACT TEXT:
- Home player has:

RULE_ID: DECISIONS_0317
SOURCE_FILE: Aveli_System_Decisions.md:384
CATEGORY: DECISIONS
EXACT TEXT:
  - its own upload pipeline

RULE_ID: DECISIONS_0318
SOURCE_FILE: Aveli_System_Decisions.md:385
CATEGORY: DECISIONS
EXACT TEXT:
  - its own frontend management surface

RULE_ID: DECISIONS_0319
SOURCE_FILE: Aveli_System_Decisions.md:386
CATEGORY: DECISIONS
EXACT TEXT:
  - teacher-controlled active/inactive curation

RULE_ID: DECISIONS_0320
SOURCE_FILE: Aveli_System_Decisions.md:387
CATEGORY: DECISIONS
EXACT TEXT:
- Home player curation is controlled by `control_plane`.

RULE_ID: DECISIONS_0321
SOURCE_FILE: Aveli_System_Decisions.md:388
CATEGORY: DECISIONS
EXACT TEXT:
- Home-player runtime truth is still owned by `runtime_media`.

RULE_ID: DECISIONS_0322
SOURCE_FILE: Aveli_System_Decisions.md:389
CATEGORY: DECISIONS
EXACT TEXT:
- Home player does not create a separate media authority, alternate resolver, or separate media domain.

RULE_ID: DECISIONS_0323
SOURCE_FILE: Aveli_System_Decisions.md:390
CATEGORY: DECISIONS
EXACT TEXT:
- Home player must not introduce special-case frontend representation, direct storage delivery, or bypass paths around `runtime_media` and backend read composition.

RULE_ID: DECISIONS_0324
SOURCE_FILE: Aveli_System_Decisions.md:394
CATEGORY: DECISIONS
EXACT TEXT:
- `auth.users`

RULE_ID: DECISIONS_0325
SOURCE_FILE: Aveli_System_Decisions.md:395
CATEGORY: DECISIONS
EXACT TEXT:
- `storage.objects`

RULE_ID: DECISIONS_0326
SOURCE_FILE: Aveli_System_Decisions.md:396
CATEGORY: DECISIONS
EXACT TEXT:
- `storage.buckets`

RULE_ID: DECISIONS_0327
SOURCE_FILE: Aveli_System_Decisions.md:397
CATEGORY: DECISIONS
EXACT TEXT:
- These remain external dependencies and are not baseline-owned schema.

RULE_ID: DECISIONS_0328
SOURCE_FILE: Aveli_System_Decisions.md:398
CATEGORY: DECISIONS
EXACT TEXT:
- Local scratch verification may require a minimal local storage substrate when storage-backed workers are enabled.

RULE_ID: DECISIONS_0329
SOURCE_FILE: Aveli_System_Decisions.md:402
CATEGORY: DECISIONS
EXACT TEXT:
- Fields referencing external systems (for example `auth.users.id`) MUST NOT use database foreign key constraints.

RULE_ID: DECISIONS_0330
SOURCE_FILE: Aveli_System_Decisions.md:403
CATEGORY: DECISIONS
EXACT TEXT:
- `user_id` is a soft reference to `auth.users(id)`.

RULE_ID: DECISIONS_0331
SOURCE_FILE: Aveli_System_Decisions.md:404
CATEGORY: DECISIONS
EXACT TEXT:
- Validity is enforced at:

RULE_ID: DECISIONS_0332
SOURCE_FILE: Aveli_System_Decisions.md:405
CATEGORY: DECISIONS
EXACT TEXT:
  - auth layer (token validation)

RULE_ID: DECISIONS_0333
SOURCE_FILE: Aveli_System_Decisions.md:406
CATEGORY: DECISIONS
EXACT TEXT:
  - backend services (creation and mutation checks)

RULE_ID: DECISIONS_0334
SOURCE_FILE: Aveli_System_Decisions.md:407
CATEGORY: DECISIONS
EXACT TEXT:
- Reads MUST be tolerant of missing external records and MUST NOT hard crash because an external record is absent.

RULE_ID: DECISIONS_0335
SOURCE_FILE: Aveli_System_Decisions.md:408
CATEGORY: DECISIONS
EXACT TEXT:
- Database MUST NOT enforce foreign key constraints for external dependencies.

RULE_ID: DECISIONS_0336
SOURCE_FILE: Aveli_System_Decisions.md:412
CATEGORY: DECISIONS
EXACT TEXT:
- Legacy tables, endpoints, and compatibility behaviors remain only while their intended functionality is still needed by live systems.

RULE_ID: DECISIONS_0337
SOURCE_FILE: Aveli_System_Decisions.md:413
CATEGORY: DECISIONS
EXACT TEXT:
- Once canonical authorities cover that functionality, legacy must migrate out rather than persist as competing truth.

RULE_ID: DECISIONS_0338
SOURCE_FILE: Aveli_System_Decisions.md:414
CATEGORY: DECISIONS
EXACT TEXT:
- Legacy must not survive through fallback behavior.

RULE_ID: DECISIONS_0339
SOURCE_FILE: Aveli_System_Decisions.md:415
CATEGORY: DECISIONS
EXACT TEXT:
- Legacy removal must proceed in this order:

RULE_ID: DECISIONS_0340
SOURCE_FILE: Aveli_System_Decisions.md:416
CATEGORY: DECISIONS
EXACT TEXT:
  - canonical replacement exists

RULE_ID: DECISIONS_0341
SOURCE_FILE: Aveli_System_Decisions.md:417
CATEGORY: DECISIONS
EXACT TEXT:
  - legacy surface is identified and marked

RULE_ID: DECISIONS_0342
SOURCE_FILE: Aveli_System_Decisions.md:418
CATEGORY: DECISIONS
EXACT TEXT:
  - legacy surface is blocked and/or logged where appropriate

RULE_ID: DECISIONS_0343
SOURCE_FILE: Aveli_System_Decisions.md:419
CATEGORY: DECISIONS
EXACT TEXT:
  - legacy surface is removed

RULE_ID: DECISIONS_0344
SOURCE_FILE: Aveli_System_Decisions.md:423
CATEGORY: DECISIONS
EXACT TEXT:
- lesson editor

RULE_ID: DECISIONS_0345
SOURCE_FILE: Aveli_System_Decisions.md:424
CATEGORY: DECISIONS
EXACT TEXT:
- lesson view

RULE_ID: DECISIONS_0346
SOURCE_FILE: Aveli_System_Decisions.md:425
CATEGORY: DECISIONS
EXACT TEXT:
- Stripe checkout

RULE_ID: DECISIONS_0347
SOURCE_FILE: Aveli_System_Decisions.md:426
CATEGORY: DECISIONS
EXACT TEXT:
- onboarding

RULE_ID: DECISIONS_0348
SOURCE_FILE: Aveli_System_Decisions.md:427
CATEGORY: DECISIONS
EXACT TEXT:
- membership-gated app entry

RULE_ID: DECISIONS_0349
SOURCE_FILE: Aveli_System_Decisions.md:428
CATEGORY: DECISIONS
EXACT TEXT:
- canonical_protected_course_content_access

RULE_ID: DECISIONS_0350
SOURCE_FILE: Aveli_System_Decisions.md:429
CATEGORY: DECISIONS
EXACT TEXT:
- home-player curation and unified media-authority compliance

RULE_ID: DECISIONS_0351
SOURCE_FILE: Aveli_System_Decisions.md:433
CATEGORY: DECISIONS
EXACT TEXT:
- Resolution chain:

RULE_ID: DECISIONS_0352
SOURCE_FILE: Aveli_System_Decisions.md:434
CATEGORY: DECISIONS
EXACT TEXT:
  - canonical media identity and attachment pointers

RULE_ID: DECISIONS_0353
SOURCE_FILE: Aveli_System_Decisions.md:435
CATEGORY: DECISIONS
EXACT TEXT:
  - `control_plane`

RULE_ID: DECISIONS_0354
SOURCE_FILE: Aveli_System_Decisions.md:436
CATEGORY: DECISIONS
EXACT TEXT:
  - `runtime_media`

RULE_ID: DECISIONS_0355
SOURCE_FILE: Aveli_System_Decisions.md:437
CATEGORY: DECISIONS
EXACT TEXT:
  - backend read composition layer

RULE_ID: DECISIONS_0356
SOURCE_FILE: Aveli_System_Decisions.md:438
CATEGORY: DECISIONS
EXACT TEXT:
  - API response

RULE_ID: DECISIONS_0357
SOURCE_FILE: Aveli_System_Decisions.md:439
CATEGORY: DECISIONS
EXACT TEXT:
  - frontend render

RULE_ID: DECISIONS_0358
SOURCE_FILE: Aveli_System_Decisions.md:440
CATEGORY: DECISIONS
EXACT TEXT:
- `app.media_assets` defines media identity.

RULE_ID: DECISIONS_0359
SOURCE_FILE: Aveli_System_Decisions.md:441
CATEGORY: DECISIONS
EXACT TEXT:
- `app.lesson_media` defines authored placement.

RULE_ID: DECISIONS_0360
SOURCE_FILE: Aveli_System_Decisions.md:442
CATEGORY: DECISIONS
EXACT TEXT:
- `app.runtime_media` defines runtime truth for state and resolution eligibility.

RULE_ID: DECISIONS_0361
SOURCE_FILE: Aveli_System_Decisions.md:443
CATEGORY: DECISIONS
EXACT TEXT:
- `runtime_media` is not the final frontend representation.

RULE_ID: DECISIONS_0362
SOURCE_FILE: Aveli_System_Decisions.md:445-447
CATEGORY: DECISIONS
EXACT TEXT:
runtime_media provides canonical runtime truth.
The backend read composition layer is the sole authority for media representation to frontend.
Frontend must render only and must not resolve or construct media.

RULE_ID: DECISIONS_0363
SOURCE_FILE: Aveli_System_Decisions.md:448
CATEGORY: DECISIONS
EXACT TEXT:
- `storage.objects` is an external physical-storage dependency and is never a valid media authority or delivery source.

RULE_ID: DECISIONS_0364
SOURCE_FILE: Aveli_System_Decisions.md:449
CATEGORY: DECISIONS
EXACT TEXT:
- `control_plane` defines media intent and lifecycle interpretation, not execution, runtime truth, or frontend representation.

RULE_ID: DECISIONS_0365
SOURCE_FILE: Aveli_System_Decisions.md:450
CATEGORY: DECISIONS
EXACT TEXT:
- No layer may bypass `runtime_media`.

RULE_ID: DECISIONS_0366
SOURCE_FILE: Aveli_System_Decisions.md:451
CATEGORY: DECISIONS
EXACT TEXT:
- No layer may bypass backend read composition when constructing frontend-facing media.

RULE_ID: DECISIONS_0367
SOURCE_FILE: Aveli_System_Decisions.md:452
CATEGORY: DECISIONS
EXACT TEXT:
- All lesson/content media references must use `lesson_media_id` only.

RULE_ID: DECISIONS_0368
SOURCE_FILE: Aveli_System_Decisions.md:453
CATEGORY: DECISIONS
EXACT TEXT:
- Fallback is forbidden.

RULE_ID: DECISIONS_0369
SOURCE_FILE: Aveli_System_Decisions.md:454
CATEGORY: DECISIONS
EXACT TEXT:
  - If canonical media resolution fails, the system must fail explicitly rather than route through legacy or storage shortcuts.

RULE_ID: DECISIONS_0370
SOURCE_FILE: Aveli_System_Decisions.md:459
CATEGORY: DECISIONS
EXACT TEXT:
- Chosen source of truth:

RULE_ID: DECISIONS_0371
SOURCE_FILE: Aveli_System_Decisions.md:460
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json

RULE_ID: DECISIONS_0372
SOURCE_FILE: Aveli_System_Decisions.md:461
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md

RULE_ID: DECISIONS_0373
SOURCE_FILE: Aveli_System_Decisions.md:462
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md

RULE_ID: DECISIONS_0374
SOURCE_FILE: Aveli_System_Decisions.md:463
CATEGORY: DECISIONS
EXACT TEXT:
- Classification:

RULE_ID: DECISIONS_0375
SOURCE_FILE: Aveli_System_Decisions.md:464
CATEGORY: DECISIONS
EXACT TEXT:
  - API verification source: `runtime-observed`

RULE_ID: DECISIONS_0376
SOURCE_FILE: Aveli_System_Decisions.md:465
CATEGORY: DECISIONS
EXACT TEXT:
  - Canonical legitimacy: `separate_from_observation`

RULE_ID: DECISIONS_0377
SOURCE_FILE: Aveli_System_Decisions.md:466
CATEGORY: DECISIONS
EXACT TEXT:
- Canonical decision:

RULE_ID: DECISIONS_0378
SOURCE_FILE: Aveli_System_Decisions.md:467
CATEGORY: DECISIONS
EXACT TEXT:
  - audit artifacts describe what exists and how it behaves

RULE_ID: DECISIONS_0379
SOURCE_FILE: Aveli_System_Decisions.md:468
CATEGORY: DECISIONS
EXACT TEXT:
  - audit artifacts do not automatically justify keeping legacy endpoints or duplicate authorities

RULE_ID: DECISIONS_0380
SOURCE_FILE: Aveli_System_Decisions.md:471
CATEGORY: DECISIONS
EXACT TEXT:
- Chosen source of truth:

RULE_ID: DECISIONS_0381
SOURCE_FILE: Aveli_System_Decisions.md:472
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/media_control_plane_mcp.md

RULE_ID: DECISIONS_0382
SOURCE_FILE: Aveli_System_Decisions.md:473
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/media_architecture.md

RULE_ID: DECISIONS_0383
SOURCE_FILE: Aveli_System_Decisions.md:474
CATEGORY: DECISIONS
EXACT TEXT:
- Classification:

RULE_ID: DECISIONS_0384
SOURCE_FILE: Aveli_System_Decisions.md:475
CATEGORY: DECISIONS
EXACT TEXT:
  - Scope intent: `planned_preserved`

RULE_ID: DECISIONS_0385
SOURCE_FILE: Aveli_System_Decisions.md:476
CATEGORY: DECISIONS
EXACT TEXT:
  - Canonical roles: `media_intent_authority`, `media_lifecycle_observability_authority`

RULE_ID: DECISIONS_0386
SOURCE_FILE: Aveli_System_Decisions.md:477
CATEGORY: DECISIONS
EXACT TEXT:
- Canonical decision:

RULE_ID: DECISIONS_0387
SOURCE_FILE: Aveli_System_Decisions.md:478
CATEGORY: DECISIONS
EXACT TEXT:
  - control plane is preserved and not open to semantic redefinition

RULE_ID: DECISIONS_0388
SOURCE_FILE: Aveli_System_Decisions.md:479
CATEGORY: DECISIONS
EXACT TEXT:
  - control plane must not be removed or semantically redefined

RULE_ID: DECISIONS_0389
SOURCE_FILE: Aveli_System_Decisions.md:480
CATEGORY: DECISIONS
EXACT TEXT:
  - control plane does not own execution, runtime truth, or frontend representation

RULE_ID: DECISIONS_0390
SOURCE_FILE: Aveli_System_Decisions.md:483
CATEGORY: DECISIONS
EXACT TEXT:
- Chosen source of truth:

RULE_ID: DECISIONS_0391
SOURCE_FILE: Aveli_System_Decisions.md:484
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md

RULE_ID: DECISIONS_0392
SOURCE_FILE: Aveli_System_Decisions.md:485
CATEGORY: DECISIONS
EXACT TEXT:
  - docs/SECURITY.md

RULE_ID: DECISIONS_0393
SOURCE_FILE: Aveli_System_Decisions.md:486
CATEGORY: DECISIONS
EXACT TEXT:
- Classification:

RULE_ID: DECISIONS_0394
SOURCE_FILE: Aveli_System_Decisions.md:487
CATEGORY: DECISIONS
EXACT TEXT:
  - Auth/security intent: `planned`

RULE_ID: DECISIONS_0395
SOURCE_FILE: Aveli_System_Decisions.md:488
CATEGORY: DECISIONS
EXACT TEXT:
  - Runtime status: `runtime-audited`

RULE_ID: DECISIONS_0396
SOURCE_FILE: Aveli_System_Decisions.md:489
CATEGORY: DECISIONS
EXACT TEXT:
- Canonical decision:

RULE_ID: DECISIONS_0397
SOURCE_FILE: Aveli_System_Decisions.md:490
CATEGORY: DECISIONS
EXACT TEXT:
  - security and audit docs remain the governing baseline for auth constraints

RULE_ID: DECISIONS_0398
SOURCE_FILE: Aveli_System_Decisions.md:491
CATEGORY: DECISIONS
EXACT TEXT:
  - UX-driven evolution must not redesign the structural trust boundary in this phase

RULE_ID: DECISIONS_0399
SOURCE_FILE: Aveli_System_Decisions.md:495
CATEGORY: DECISIONS
EXACT TEXT:
- API definitions: observed via audit, verified separately from legitimacy

RULE_ID: DECISIONS_0400
SOURCE_FILE: Aveli_System_Decisions.md:496
CATEGORY: DECISIONS
EXACT TEXT:
- Media control plane: planned, preserved, intent-authoritative

RULE_ID: DECISIONS_0401
SOURCE_FILE: Aveli_System_Decisions.md:497
CATEGORY: DECISIONS
EXACT TEXT:
- Media runtime truth: runtime-active via `runtime_media`

RULE_ID: DECISIONS_0402
SOURCE_FILE: Aveli_System_Decisions.md:498
CATEGORY: DECISIONS
EXACT TEXT:
- Media representation to frontend: runtime-active via backend read composition

RULE_ID: DECISIONS_0403
SOURCE_FILE: Aveli_System_Decisions.md:499
CATEGORY: DECISIONS
EXACT TEXT:
- Auth flow: planned constraints + runtime-audited behavior

RULE_ID: DECISIONS_0404
SOURCE_FILE: Aveli_System_Decisions.md:500
CATEGORY: DECISIONS
EXACT TEXT:
- Home player ingest/curation: runtime-active within the same media domain

RULE_ID: DECISIONS_0405
SOURCE_FILE: Aveli_System_Decisions.md:501
CATEGORY: DECISIONS
EXACT TEXT:
- Membership app access: runtime/canonical authority

RULE_ID: DECISIONS_0406
SOURCE_FILE: Aveli_System_Decisions.md:502
CATEGORY: DECISIONS
EXACT TEXT:
- `course_discovery_surface`: canonical surface type

RULE_ID: DECISIONS_0407
SOURCE_FILE: Aveli_System_Decisions.md:503
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_structure_surface`: canonical surface type

RULE_ID: DECISIONS_0408
SOURCE_FILE: Aveli_System_Decisions.md:504
CATEGORY: DECISIONS
EXACT TEXT:
- `lesson_content_surface`: canonical surface type

RULE_ID: DECISIONS_0409
SOURCE_FILE: Aveli_System_Decisions.md:505
CATEGORY: DECISIONS
EXACT TEXT:
- `canonical_protected_course_content_access`: runtime/canonical authority

RULE_ID: DECISIONS_0410
SOURCE_FILE: Aveli_System_Decisions.md:509
CATEGORY: DECISIONS
EXACT TEXT:
- `subscription` as active runtime/domain authority

RULE_ID: DECISIONS_0411
SOURCE_FILE: Aveli_System_Decisions.md:510
CATEGORY: DECISIONS
EXACT TEXT:
- `module` as runtime/domain construct

RULE_ID: DECISIONS_0412
SOURCE_FILE: Aveli_System_Decisions.md:511
CATEGORY: DECISIONS
EXACT TEXT:
- duplicate app-access authorities parallel to `memberships`

RULE_ID: DECISIONS_0413
SOURCE_FILE: Aveli_System_Decisions.md:512
CATEGORY: DECISIONS
EXACT TEXT:
- duplicate `canonical_protected_course_content_access` authorities parallel to `course_enrollments`

RULE_ID: DECISIONS_0414
SOURCE_FILE: Aveli_System_Decisions.md:513
CATEGORY: DECISIONS
EXACT TEXT:
- implicit intro access

RULE_ID: DECISIONS_0415
SOURCE_FILE: Aveli_System_Decisions.md:514
CATEGORY: DECISIONS
EXACT TEXT:
- treating `course_discovery_surface` as enrollment-gated

RULE_ID: DECISIONS_0416
SOURCE_FILE: Aveli_System_Decisions.md:515
CATEGORY: DECISIONS
EXACT TEXT:
- hiding course catalog behind enrollment

RULE_ID: DECISIONS_0417
SOURCE_FILE: Aveli_System_Decisions.md:516
CATEGORY: DECISIONS
EXACT TEXT:
- treating `lesson_structure_surface` as `lesson_content_surface`

RULE_ID: DECISIONS_0418
SOURCE_FILE: Aveli_System_Decisions.md:517
CATEGORY: DECISIONS
EXACT TEXT:
- conflating `course_discovery_surface` or `lesson_structure_surface` with `lesson_content_surface`

RULE_ID: DECISIONS_0419
SOURCE_FILE: Aveli_System_Decisions.md:518
CATEGORY: DECISIONS
EXACT TEXT:
- exposing `lesson_content` or `lesson_media` on `lesson_structure_surface`

RULE_ID: DECISIONS_0420
SOURCE_FILE: Aveli_System_Decisions.md:519
CATEGORY: DECISIONS
EXACT TEXT:
- returning `lesson_content_surface` data from course-detail endpoints

RULE_ID: DECISIONS_0421
SOURCE_FILE: Aveli_System_Decisions.md:520
CATEGORY: DECISIONS
EXACT TEXT:
- treating any rule that does not require `course_enrollments` AND `lesson.position <= current_unlock_position` as sufficient authority for `lesson_content_surface`

RULE_ID: DECISIONS_0422
SOURCE_FILE: Aveli_System_Decisions.md:521
CATEGORY: DECISIONS
EXACT TEXT:
- entitlement fallback paths

RULE_ID: DECISIONS_0423
SOURCE_FILE: Aveli_System_Decisions.md:522
CATEGORY: DECISIONS
EXACT TEXT:
- progression-position-based ownership logic

RULE_ID: DECISIONS_0424
SOURCE_FILE: Aveli_System_Decisions.md:523
CATEGORY: DECISIONS
EXACT TEXT:
- runtime-derived progression

RULE_ID: DECISIONS_0425
SOURCE_FILE: Aveli_System_Decisions.md:524
CATEGORY: DECISIONS
EXACT TEXT:
- runtime-derived unlock state

RULE_ID: DECISIONS_0426
SOURCE_FILE: Aveli_System_Decisions.md:525
CATEGORY: DECISIONS
EXACT TEXT:
- drip logic tied to `intro_enrollment` vs `purchase`

RULE_ID: DECISIONS_0427
SOURCE_FILE: Aveli_System_Decisions.md:526
CATEGORY: DECISIONS
EXACT TEXT:
- hardcoded drip defaults

RULE_ID: DECISIONS_0428
SOURCE_FILE: Aveli_System_Decisions.md:527
CATEGORY: DECISIONS
EXACT TEXT:
- fallback drip behavior

RULE_ID: DECISIONS_0429
SOURCE_FILE: Aveli_System_Decisions.md:528
CATEGORY: DECISIONS
EXACT TEXT:
- implicit unlock strategies

RULE_ID: DECISIONS_0430
SOURCE_FILE: Aveli_System_Decisions.md:529
CATEGORY: DECISIONS
EXACT TEXT:
- inferred drip behavior from course type

RULE_ID: DECISIONS_0431
SOURCE_FILE: Aveli_System_Decisions.md:530
CATEGORY: DECISIONS
EXACT TEXT:
- implicit `lesson_content_surface` access by inferred tags or hidden rules

RULE_ID: DECISIONS_0432
SOURCE_FILE: Aveli_System_Decisions.md:531
CATEGORY: DECISIONS
EXACT TEXT:
- direct media delivery from `storage.objects`

RULE_ID: DECISIONS_0433
SOURCE_FILE: Aveli_System_Decisions.md:532
CATEGORY: DECISIONS
EXACT TEXT:
- alternate media authorities outside `runtime_media`

RULE_ID: DECISIONS_0434
SOURCE_FILE: Aveli_System_Decisions.md:533
CATEGORY: DECISIONS
EXACT TEXT:
- alternate frontend-representation authorities outside backend read composition

RULE_ID: DECISIONS_0435
SOURCE_FILE: Aveli_System_Decisions.md:534
CATEGORY: DECISIONS
EXACT TEXT:
- cover-specific resolver ownership

RULE_ID: DECISIONS_0436
SOURCE_FILE: Aveli_System_Decisions.md:535
CATEGORY: DECISIONS
EXACT TEXT:
- frontend media construction or resolution

RULE_ID: DECISIONS_0437
SOURCE_FILE: Aveli_System_Decisions.md:536
CATEGORY: DECISIONS
EXACT TEXT:
- fallback to legacy paths when canonical resolution fails

RULE_ID: DECISIONS_0438
SOURCE_FILE: Aveli_System_Decisions.md:537
CATEGORY: DECISIONS
EXACT TEXT:
- any endpoint or function that presents storage as business truth instead of dependency detail

RULE_ID: DECISIONS_0439
SOURCE_FILE: Aveli_System_Decisions.md:541
CATEGORY: DECISIONS
EXACT TEXT:
- This file is the preserved semantic decision layer for rule interpretation, contradiction review, and deterministic cleanup of legacy surfaces.

