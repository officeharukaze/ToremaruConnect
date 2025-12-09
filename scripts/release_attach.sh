#!/usr/bin/env bash
set -euo pipefail

# A minimal release attach script adapted from ToremaruHome
# Expects artifacts in ./artifacts (the workflow downloads them there)

ART_DIR="${ART_DIR:-./artifacts}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
VER_NAME="${VER_NAME:-}"
VER_CODE="${VER_CODE:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$REPO" ]; then
  echo "REPO not set and GITHUB_REPOSITORY not available" >&2
  exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "GITHUB_TOKEN not set. Ensure the workflow passes it in." >&2
  exit 1
fi

if [ -z "$VER_NAME" ]; then
  VER_NAME="ci-$(date +%Y%m%d%H%M%S)"
fi
if [ -z "$VER_CODE" ]; then
  VER_CODE="0"
fi

TAG="v${VER_NAME}-${VER_CODE}"

echo "Repo: $REPO"
echo "Tag: $TAG"
echo "Artifacts dir: $ART_DIR"

if [ ! -d "$ART_DIR" ]; then
  echo "Artifacts directory $ART_DIR not found" >&2
  exit 1
fi

# Determine whether a release with TAG exists
API_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token ${GITHUB_TOKEN}" "$API_URL") || true

if [ "$HTTP_STATUS" = "200" ]; then
  echo "Release $TAG exists — retrieving upload_url"
  RESP=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$API_URL")
  UPLOAD_URL=$(echo "$RESP" | jq -r .upload_url | sed -e 's/{?name,label}//')
else
  echo "Release $TAG does not exist — creating"
  # Build JSON payload safely. Prefer python3 (widely available) to avoid manual escaping issues.
  if command -v python3 >/dev/null 2>&1; then
    # Use shell variable expansion inside heredoc so python sees actual TAG/VER values
    PAYLOAD=$(python3 - <<PY
import json
tag = "${TAG}"
ver_name = "${VER_NAME}"
ver_code = "${VER_CODE}"
body = f"Automated release (version {ver_name}-{ver_code})"
print(json.dumps({"tag_name": tag, "name": tag, "body": body}))
PY
)
  elif command -v jq >/dev/null 2>&1; then
    PAYLOAD=$(jq -n --arg tag "$TAG" --arg name "$TAG" --arg body "Automated release (version ${VER_NAME}-${VER_CODE})" '{tag_name: $tag, name: $name, body: $body}')
  else
    # Last-resort minimal escaping for double quotes/newlines in variables
    ESC_TAG=$(printf '%s' "$TAG" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
    ESC_BODY=$(printf '%s' "Automated release (version ${VER_NAME}-${VER_CODE})" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
    PAYLOAD="{\"tag_name\": \"${ESC_TAG}\", \"name\": \"${ESC_TAG}\", \"body\": \"${ESC_BODY}\"}"
  fi
  CREATE_RESP=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" -d "$PAYLOAD" "https://api.github.com/repos/${REPO}/releases")
  UPLOAD_URL=$(echo "$CREATE_RESP" | jq -r .upload_url | sed -e 's/{?name,label}//')
  RESP="$CREATE_RESP"
fi

if [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
  echo "Failed to obtain upload URL" >&2
  echo "Response: $RESP" || true
  exit 1
fi

echo "Uploading files from $ART_DIR"
find "$ART_DIR" -type f -print0 | while IFS= read -r -d '' f; do
  FNAME=$(basename "$f")
  echo "Uploading $FNAME"
  # URL-encode the file name for the upload URL to avoid curl URL errors (spaces, unicode, etc.)
  if command -v python3 >/dev/null 2>&1; then
    FNAME_ENC=$(printf '%s' "$FNAME" | python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))')
  elif command -v jq >/dev/null 2>&1; then
    FNAME_ENC=$(printf '%s' "$FNAME" | jq -s -R -r @uri)
  else
    FNAME_ENC=$(printf '%s' "$FNAME" | sed -e 's/ /%20/g')
  fi

  curl --fail -sS -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/octet-stream" --data-binary @"$f" "${UPLOAD_URL}?name=${FNAME_ENC}" || echo "upload failed: $FNAME"
done

echo "Release attach script finished"
