#!/usr/bin/env bash
set -euo pipefail
base="${OCR_URL:-http://localhost:4000}"
created=$(curl --fail --silent --show-error "$base/v1/documents" \
  -H 'content-type: application/json' \
  -d '{"app_id":"smoke","external_id":"local-smoke","document":{"type":"cnh","country":"BR"},"images":[{"side":"front","source":{"type":"object_storage","key":"fake/front.jpg"}}]}')
document_id=$(jq -er '.id' <<< "$created")
for attempt in {1..30}; do
  status=$(curl --fail --silent --show-error "$base/v1/documents/$document_id" | jq -er '.status')
  if [[ "$status" == completed ]]; then
    curl --fail --silent --show-error "$base/v1/documents/$document_id" | \
      jq -e '.status == "completed" and .result.person.cpf.value == "52998224725" and .result.person.birth_date.value == "1990-03-12"' >/dev/null
    echo "HTTP + Oban + persisted result: completed ($document_id)"
    exit 0
  fi
  sleep 1
done
echo "Pipeline did not complete; last status: $status" >&2
exit 1
