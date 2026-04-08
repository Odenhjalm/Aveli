# 0011C

- TASK_ID: `0011C`
- TYPE: `OWNER`
- TITLE: `Align home-player read surfaces to runtime-media authority`
- PROBLEM_STATEMENT: `Home-player schemas and repository code still model storage_path, storage_bucket, media_id, media_asset_id, download_url, and signed_url on read surfaces while runtime_media ownership for home-player rows is unresolved and repository sync code currently raises at runtime.`
- TARGET_STATE:
  - `backend/app/schemas/__init__.py`
  - `backend/app/routes/home.py`
  - `backend/app/repositories/home_player_library.py`
  - any mounted home-player read service owner
  - home-player read surfaces expose canonical runtime-media identity plus backend-authored playback/readiness metadata only
  - home-player read repositories do not expose storage paths, direct URLs, or duplicate runtime assumptions
  - frontend home-player rendering consumes backend-authored runtime media data only
- DEPENDS_ON:
  - `0011A`
- VERIFICATION_METHOD:
  - `rg -n "HomeAudioItem|storage_path|storage_bucket|download_url|signed_url|media_asset_id|runtime_media_id" backend/app frontend/lib/features/home`
  - confirm home read schemas no longer leak storage or duplicate media ids
  - confirm mounted home-player read path is backed by explicit runtime-media authority

