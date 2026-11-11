#!/usr/bin/env bash
set -euo pipefail
base="${OCR_URL:-http://localhost:4000}"
: "${AIKE_ACCOUNT_ID:?Set AIKE_ACCOUNT_ID}"
: "${AIKE_ACCOUNT_SECRET:?Set AIKE_ACCOUNT_SECRET}"
auth=(-H "authorization: ApiKey ${AIKE_ACCOUNT_ID}:${AIKE_ACCOUNT_SECRET}")
pipeline_version="${PIPELINE_VERSION:-2026.11.0}"

wait_for_run() {
  local expected_run="$1" response status
  for attempt in {1..30}; do
    response=$(curl --fail --silent --show-error "${auth[@]}" "$base/v1/extractions/$document_id")
    jq -e --arg run "$expected_run" '.runId == $run' <<< "$response" >/dev/null
    status=$(jq -er '.status' <<< "$response")
    if [[ "$status" == completed ]]; then
      curl --fail --silent --show-error "${auth[@]}" "$base/v1/extractions/$document_id" |
        jq -e --arg run "$expected_run" \
          '.runId == $run and .status == "completed" and .result.person.cpf.value == "52998224725"' >/dev/null
      return 0
    fi
    sleep 1
  done
  echo "Run did not complete: $expected_run ($status)" >&2
  return 1
}

created=$(curl --fail --silent --show-error "${auth[@]}" "$base/v1/extractions" \
  -H 'content-type: application/json' \
  -d '{"appId":"smoke","externalId":"local-reprocess-smoke","document":{"type":"cnh","country":"BR"},"images":[{"side":"front","image":"ZmFrZTpmcm9udA=="}]}')
document_id=$(jq -er '.id' <<< "$created")
original_run=$(jq -er '.runId' <<< "$created")
wait_for_run "$original_run"

restarted=$(jq -nc --arg version "$pipeline_version" '{pipelineVersion:$version}' |
  curl --fail --silent --show-error "${auth[@]}" "$base/v1/extractions/$document_id/reprocess" \
    -H 'content-type: application/json' --data-binary @-)
jq -e --arg id "$document_id" --arg old "$original_run" \
  '.id == $id and .status == "pending" and .runId != $old' <<< "$restarted" >/dev/null
current_run=$(jq -er '.runId' <<< "$restarted")
wait_for_run "$current_run"
echo "HTTP reprocess completed: $document_id ($original_run -> $current_run)"
