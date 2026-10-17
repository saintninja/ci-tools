#!/bin/bash
set -euo pipefail

CHANGED_FILES="${1:-}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/tmp/github_summary.md}"

if [ -z "$CHANGED_FILES" ]; then
    echo "No files to check style."
    exit 0
fi

{
  echo "### Code Style Check Results"
  echo ""
} >> "$SUMMARY_FILE"

while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue

    echo "::group::Style Check: $file"
    STYLE_ISSUES=0

    echo "Checking clang-format for $file..."
    FORMAT_DIFF=$(clang-format --dry-run "$file" 2>&1 || true)
    if [ -n "$FORMAT_DIFF" ]; then
        echo "::warning file=$file::clang-format style issues found"
        {
            echo "#### clang-format: \`$file\`"
            echo "<details>"
            echo "<summary>Format diff</summary>"
            echo ""
            echo '```text'
            echo "$FORMAT_DIFF"
            echo '```'
            echo ""
            echo "</details>"
            echo ""
        } >> "$SUMMARY_FILE"
        STYLE_ISSUES=1
    fi

    echo "Checking clang-tidy for $file..."
    TIDY_OUTPUT=$(clang-tidy --quiet "$file" --config-file=.clang-tidy -- -std=c++20 2>&1 || true)
    if [ -n "$TIDY_OUTPUT" ]; then
        echo "::warning file=$file::clang-tidy style issues found"
        {
            echo "#### clang-tidy: \`$file\`"
            echo "<details>"
            echo "<summary>Tidy warnings</summary>"
            echo ""
            echo '```'
            echo "$TIDY_OUTPUT"
            echo '```'
            echo ""
            echo "</details>"
            echo ""
        } >> "$SUMMARY_FILE"
        STYLE_ISSUES=1
    fi

    if [ "$STYLE_ISSUES" -eq 0 ]; then
        echo "### FILE MATCHES CODE STYLE: \`$file\`" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    fi

    echo "::endgroup::"

done <<< "$CHANGED_FILES"