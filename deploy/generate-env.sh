#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -e .env ]; then
  echo "deploy/.env already exists; remove it first to generate new secrets" >&2
  exit 1
fi

umask 077
while IFS= read -r line; do
  case "$line" in
    *=change-me) echo "${line%=change-me}=$(openssl rand -hex 32)" ;;
    *) echo "$line" ;;
  esac
done < .env.example > .env

echo "deploy/.env created with random secrets"
