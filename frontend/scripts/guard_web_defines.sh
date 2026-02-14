#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-}"
if [[ -z "$ENV_FILE" ]]; then
  echo "Usage: guard_web_defines.sh <env-file>" >&2
  exit 2
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: web defines file not found: $ENV_FILE" >&2
  exit 1
fi

declare -A allowed
for key in \
  API_BASE_URL \
  SUPABASE_URL \
  SUPABASE_PUBLISHABLE_API_KEY \
  SUPABASE_PUBLIC_API_KEY \
  SUPABASE_ANON_KEY \
  STRIPE_PUBLISHABLE_KEY \
  STRIPE_MERCHANT_DISPLAY_NAME \
  OAUTH_REDIRECT_WEB \
  FRONTEND_URL \
  SUBSCRIPTIONS_ENABLED \
  IMAGE_LOGGING \
  MVP_BASE_URL \
  SENTRY_DSN; do
  allowed["$key"]=1
done

bad=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="${raw%%$'\r'}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ -z "$line" || "$line" == \#* ]]; then
    continue
  fi
  if [[ "$line" == export\ * ]]; then
    line="${line#export }"
  fi
  if [[ "$line" != *"="* ]]; then
    continue
  fi
  key="${line%%=*}"
  key="${key#"${key%%[![:space:]]*}"}"
  key="${key%"${key##*[![:space:]]}"}"
  if [[ -z "$key" ]]; then
    continue
  fi
  if [[ -z "${allowed[$key]+x}" ]]; then
    echo "ERROR: $key is not allowed in web defines (file: $ENV_FILE)." >&2
    bad=1
  fi
done <"$ENV_FILE"

if [[ "$bad" -ne 0 ]]; then
  echo "Web defines guard failed. Remove backend secrets from $ENV_FILE." >&2
  exit 1
fi
