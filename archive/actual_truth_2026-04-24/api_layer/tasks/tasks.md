# api_layer — extracted tasks

## blocking
- `api_align_media_sign_route`: align the active frontend sign path with the mounted backend `/media/sign` handler.

## important
- `api_refresh_usage_diff_current_frontend`: regenerate the API usage baseline from current frontend call sites before relying on January 2026 mismatch lists.
- `api_resolve_legacy_auth_router_drift`: classify or retire the unmounted legacy auth router so it stops acting like active API truth.
- `api_resolve_legacy_payments_router_drift`: classify or retire the unmounted legacy payments router so route accounting only follows mounted checkout/billing paths.

## informational
- None.
