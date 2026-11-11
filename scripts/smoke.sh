#!/usr/bin/env bash
set -euo pipefail
base="${OCR_URL:-http://localhost:4000}"
: "${AIKE_ACCOUNT_ID:?Set AIKE_ACCOUNT_ID}"
: "${AIKE_ACCOUNT_SECRET:?Set AIKE_ACCOUNT_SECRET}"
auth=(-H "authorization: ApiKey ${AIKE_ACCOUNT_ID}:${AIKE_ACCOUNT_SECRET}")
created=$(curl --fail --silent --show-error "${auth[@]}" "$base/v1/extractions" \
  -H 'content-type: application/json' \
  -d '{"appId":"smoke","externalId":"local-smoke","document":{"type":"cnh","country":"BR"},"images":[{"side":"front","image":"ZmFrZTpmcm9udA=="}]}')
document_id=$(jq -er '.id' <<< "$created")
for attempt in {1..30}; do
  status=$(curl --fail --silent --show-error "${auth[@]}" "$base/v1/extractions/$document_id" | jq -er '.status')
  if [[ "$status" == completed ]]; then
    curl --fail --silent --show-error "${auth[@]}" "$base/v1/extractions/$document_id" | \
      jq -e '.status == "completed" and .result.person.cpf.value == "52998224725" and .result.person.birthDate.value == "1990-03-12"' >/dev/null
    echo "HTTP + Oban + persisted result: completed ($document_id)"
    exit 0
  fi
  sleep 1
done
echo "Pipeline did not complete; last status: $status" >&2
exit 1
