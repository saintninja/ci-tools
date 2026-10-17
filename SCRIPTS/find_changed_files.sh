#!/bin/bash
set -euo pipefail

EVENT_NAME="${1:-}"
BASE_REF="${2:-}"
BEFORE_SHA="${3:-}"
OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

PATTERN='^PROGRAMMING/HOMEWORKS/HW_[0-9]+/.*\.cpp$'

if [ "$EVENT_NAME" = "pull_request" ]; then
    BASE="origin/${BASE_REF}"
else
    if [ "$BEFORE_SHA" = "0000000000000000000000000000000000000000" ] || [ -z "$BEFORE_SHA" ]; then
        BASE=""
    else
        BASE="$BEFORE_SHA"
    fi
fi

if [ -n "$BASE" ]; then
    CHANGED_FILES=$(git diff --name-only --diff-filter=ACMR "$BASE" HEAD \
      | grep -E "$PATTERN" || true)
else
    CHANGED_FILES=$(git ls-files \
      | grep -E "$PATTERN" || true)
fi

{
    echo "files<<EOF"
    echo "$CHANGED_FILES"
    echo "EOF"
} >> "$OUTPUT_FILE"