#!/usr/bin/env bash
set -euo pipefail
base="${OCR_URL:-http://localhost:4000}"
pipeline_version="${PIPELINE_VERSION:-2026.11.0}"

wait_for_run() {
  local expected_run="$1" response status
  for attempt in {1..30}; do
    response=$(curl --fail --silent --show-error "$base/v1/documents/$document_id")
    jq -e --arg run "$expected_run" '.run_id == $run' <<< "$response" >/dev/null
    status=$(jq -er '.status' <<< "$response")
    if [[ "$status" == completed ]]; then
      curl --fail --silent --show-error "$base/v1/documents/$document_id" |
        jq -e --arg run "$expected_run" \
          '.run_id == $run and .status == "completed" and .result.person.cpf.value == "52998224725"' >/dev/null
      return 0
    fi
    sleep 1
  done
  echo "Run did not complete: $expected_run ($status)" >&2
  return 1
}

created=$(curl --fail --silent --show-error "$base/v1/documents" \
  -H 'content-type: application/json' \
  -d '{"app_id":"smoke","external_id":"local-reprocess-smoke","document":{"type":"cnh","country":"BR"},"images":[{"side":"front","source":{"type":"object_storage","key":"fake/front.jpg"}}]}')
document_id=$(jq -er '.id' <<< "$created")
original_run=$(jq -er '.run_id' <<< "$created")
wait_for_run "$original_run"

restarted=$(jq -nc --arg version "$pipeline_version" '{pipeline_version:$version}' |
  curl --fail --silent --show-error "$base/v1/documents/$document_id/reprocess" \
    -H 'content-type: application/json' --data-binary @-)
jq -e --arg id "$document_id" --arg old "$original_run" \
  '.id == $id and .status == "pending" and .run_id != $old' <<< "$restarted" >/dev/null
current_run=$(jq -er '.run_id' <<< "$restarted")
wait_for_run "$current_run"
echo "HTTP reprocess completed: $document_id ($original_run -> $current_run)"
