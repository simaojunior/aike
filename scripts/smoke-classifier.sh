#!/usr/bin/env bash
set -euo pipefail
base="${CLASSIFIER_URL:-http://localhost:4001}"
: "${AIKE_ACCOUNT_ID:?Set AIKE_ACCOUNT_ID}"
: "${AIKE_ACCOUNT_SECRET:?Set AIKE_ACCOUNT_SECRET}"
: "${CLASSIFIER_FILE:?Set CLASSIFIER_FILE to a JPEG, PNG or single-page PDF}"
test -f "$CLASSIFIER_FILE"

base64 -w0 "$CLASSIFIER_FILE" | jq -Rs '{image: .}' |
  curl --fail-with-body --silent --show-error "$base/v1/classifications" \
    -H 'content-type: application/json' \
    -H "authorization: ApiKey ${AIKE_ACCOUNT_ID}:${AIKE_ACCOUNT_SECRET}" --data-binary @- |
  jq -e '.document.type as $type | ($type == "cnh" or $type == "rg" or $type == "unknown") and (.confidence >= 0 and .confidence <= 1)'

curl --fail-with-body --silent --show-error "$base/v1/classifications" \
  -H "authorization: ApiKey ${AIKE_ACCOUNT_ID}:${AIKE_ACCOUNT_SECRET}" \
  -F "file=@${CLASSIFIER_FILE}" |
  jq -e '.version == "v1" and (.data | type == "array") and (.metadata.filesInfo | length == 1)'
