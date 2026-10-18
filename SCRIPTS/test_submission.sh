#!/bin/bash
# Usage: test_submission.sh <header_file> <test_file> <output_file> [checks_spec]

HEADER_FILE="${1:-}"
TEST_FILE="${2:-}"
OUTPUT_FILE="${3:-}"
CHECKS_SPEC="${4:-}"

TIME_LIMIT=10          # seconds
MEMORY_LIMIT_KB=262144 # 256 MB

if [ -z "$HEADER_FILE" ] || [ -z "$TEST_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <header_file> <test_file> <output_file> [checks_spec]" >&2
    exit 1
fi

if [ ! -f "$HEADER_FILE" ]; then
    echo "Error: Header file not found: $HEADER_FILE" >&2
    exit 1
fi

if [ ! -f "$TEST_FILE" ]; then
    echo "Error: Test file not found: $TEST_FILE" >&2
    exit 1
fi

trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "$1"; }

spec_keys() {
    local -a items
    local item key
    IFS=',' read -ra items <<< "$CHECKS_SPEC"
    for item in "${items[@]}"; do
        item=$(trim "$item")
        key=$(trim "${item%%:*}")
        [ -n "$key" ] && echo "$key"
    done
    return 0
}

mkdir -p "$(dirname "$OUTPUT_FILE")"

BIN=$(mktemp)
trap 'rm -f "$BIN"' EXIT

echo "Testing: $HEADER_FILE"

echo "FILE: $HEADER_FILE" > "$OUTPUT_FILE"

echo "Compiling..."
compile_output=$(g++ -std=c++20 -Wall -Wextra -I. -include "$HEADER_FILE" "$TEST_FILE" -o "$BIN" 2>&1)
compile_status=$?

if [ $compile_status -ne 0 ]; then
    echo "COMPILATION: FAIL" >> "$OUTPUT_FILE"
    while IFS= read -r key; do
        echo "CHECK: $key=FAIL" >> "$OUTPUT_FILE"
    done < <(spec_keys)
    {
        echo ""
        echo "Compiler output:"
        echo "$compile_output" | sed 's/^/    /'
    } >> "$OUTPUT_FILE"

    echo "$compile_output"
    echo "::error file=$HEADER_FILE::Compilation failed for $HEADER_FILE"
    exit 1
fi

echo "COMPILATION: PASS" >> "$OUTPUT_FILE"
echo "Running tests..."

test_output=$( (ulimit -v "$MEMORY_LIMIT_KB"; timeout "${TIME_LIMIT}s" "$BIN") 2>&1 )
test_status=$?

echo "$test_output"
{
    echo ""
    echo "Test output:"
    echo "$test_output" | sed 's/^/    /'
} >> "$OUTPUT_FILE"

if [ $test_status -eq 124 ]; then
    echo "TIMEOUT: test run exceeded ${TIME_LIMIT}s" | tee -a "$OUTPUT_FILE"
    echo "::error file=$HEADER_FILE::Test run exceeded ${TIME_LIMIT}s for $HEADER_FILE"
fi

declare -A seen=()
any_fail=false
result_line=$(echo "$test_output" | grep "^RESULT:" | tail -1 || true)

if [ -n "$result_line" ]; then
    IFS='|' read -ra parts <<< "${result_line#RESULT:}"
    for part in "${parts[@]}"; do
        part=$(trim "$part")
        if [[ "$part" =~ ^([A-Za-z0-9_]+)=([A-Za-z]+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]^^}"
            echo "CHECK: $key=$value" >> "$OUTPUT_FILE"
            seen[$key]=1
            [ "$value" = "FAIL" ] && any_fail=true
        fi
    done
else
    echo "RESULT PARSE: FAIL" >> "$OUTPUT_FILE"
    any_fail=true
fi

while IFS= read -r key; do
    if [ -z "${seen[$key]:-}" ]; then
        echo "CHECK: $key=FAIL" >> "$OUTPUT_FILE"
        any_fail=true
    fi
done < <(spec_keys)

if [ $test_status -eq 0 ] && [ "$any_fail" = true ]; then
    test_status=1
fi

if [ $test_status -eq 0 ]; then
    echo "OVERALL: PASS" | tee -a "$OUTPUT_FILE"
    echo "::notice file=$HEADER_FILE::All tests passed for $HEADER_FILE"
else
    echo "OVERALL: FAIL" | tee -a "$OUTPUT_FILE"
    echo "::error file=$HEADER_FILE::Tests failed for $HEADER_FILE"
fi

echo ""

exit $test_status