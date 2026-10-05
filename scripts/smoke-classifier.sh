#!/usr/bin/env bash
set -euo pipefail
base="${CLASSIFIER_URL:-http://localhost:4001}"

check() {
  local key="$1" type="$2" side="$3" acceptable="$4" score="$5" confidence="$6" issues="$7"
  jq -nc --arg key "$key" '{source:{type:"object_storage",key:$key}}' |
    curl --fail --silent --show-error "$base/v1/classifications" \
      -H 'content-type: application/json' --data-binary @- |
    jq -e --arg type "$type" --arg side "$side" \
      --argjson acceptable "$acceptable" --argjson score "$score" \
      --argjson confidence "$confidence" --argjson issues "$issues" \
      '.document == {type:$type,country:"BR",side:$side} and
       .quality == {acceptable:$acceptable,score:$score,issues:$issues} and
       .confidence == $confidence' >/dev/null
  echo "Classifier HTTP: $key OK"
}

check 'kyc/session-123/frame-001.jpg' cnh front true 0.96 0.99 '[]'
check 'fake/cnh-back.jpg' cnh back true 0.96 0.99 '[]'
check 'fake/rg-front.jpg' rg front true 0.96 0.99 '[]'
check 'fake/rg-back.jpg' rg back true 0.96 0.99 '[]'
check 'fake/rg-single.jpg' rg single true 0.96 0.99 '[]'
check 'fake/unknown.jpg' unknown unknown true 0.91 0.37 '[]'
check 'fake/bad-quality.jpg' cnh front false 0.42 0.98 '["blur","glare"]'
