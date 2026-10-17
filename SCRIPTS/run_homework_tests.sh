#!/bin/bash
set -euo pipefail

CHANGED_FILES="${1:-}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/tmp/github_summary.md}"

normalize() {
    sed '1s/^\xEF\xBB\xBF//' | tr -d '\r' | sed 's/[[:space:]]*$//' | sed '/^$/d'
}

log_test_error() {
    local test_name="$1"
    local input_file="$2"
    local actual_file="$3"
    local expected_file="$4"

    {
        echo "### TEST FAILED: $test_name"
        echo ""
        echo "<details>"
        echo "<summary>Click to view details</summary>"
        echo ""
        echo "**Input data:**"
        echo '```text'
        cat "$input_file" || echo "(empty)"
        echo -e "\n"
        echo '```'
        echo ""
        echo "**Your output:**"
        echo '```text'
        cat "$actual_file" || echo "(empty)"
        echo -e "\n"
        echo '```'
        echo ""
        echo "**Expected output:**"
        echo '```text'
        cat "$expected_file" || echo "(empty)"
        echo '```'
        echo ""
        echo "</details>"
        echo ""
    } >> "$SUMMARY_FILE"
}

{
  echo "### Homework Check Results"
  echo ""
} >> "$SUMMARY_FILE"

OVERALL_FAILED=0

while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue

    echo "::group::Processing: $file"
    FILE_FAILED=0

    echo "Compiling $file..."
    COMPILE_OUTPUT=$(mktemp)

    if ! g++ -std=c++20 -Wall -Wextra -pedantic "$file" -o student_program 2>"$COMPILE_OUTPUT"; then
        echo "::error file=$file::Compilation failed"
        {
            echo "### Compilation Failed: \`$file\`"
            echo ""
            echo "<details>"
            echo "<summary>Compiler errors</summary>"
            echo ""
            echo '```'
            cat "$COMPILE_OUTPUT"
            echo '```'
            echo ""
            echo "</details>"
            echo ""
        } >> "$SUMMARY_FILE"

        FILE_FAILED=1
    else
        if [ -s "$COMPILE_OUTPUT" ]; then
            {
                echo "### Compilation Warnings: \`$file\`"
                echo ""
                echo "<details>"
                echo "<summary>Compiler warnings</summary>"
                echo ""
                echo '```'
                cat "$COMPILE_OUTPUT"
                echo '```'
                echo ""
                echo "</details>"
                echo ""
            } >> "$SUMMARY_FILE"
        else
            echo "### COMPILE SUCCESS: \`$file\`" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
        fi
    fi
    rm -f "$COMPILE_OUTPUT"

    if [ "$FILE_FAILED" -eq 1 ]; then
        OVERALL_FAILED=1
        echo "::endgroup::"
        continue
    fi

    echo "Running tests for $file..."

    hw_name=$(echo "$file" | cut -d'/' -f3)
    filename=$(basename "$file")
    if [[ "$filename" =~ ([0-9]+)\.[^.]+$ ]]; then
        task_number="${BASH_REMATCH[1]}"
    else
        echo "::error file=$file::Invalid file name format. Cannot extract task number."
        {
            echo "### File Naming Violation: \`$file\`"
            echo ""
            echo "The file name must contain a task number before the extension."
            echo "Expected formats: \`SurnameInitials_TaskNumber.cpp\` or \`SurnameInitialsTaskNumber.cpp\`"
            echo "Examples: \`PetrovAS_01.cpp\`, \`PetrovAS1.cpp\`"
            echo ""
        } >> "$SUMMARY_FILE"
        OVERALL_FAILED=1
        rm -f student_program
        echo "::endgroup::"
        continue
    fi

    task_number_formatted=$(printf "%02d" $((10#$task_number)))
    tests_dir="PROGRAMMING/TESTS/HOMEWORKS/${hw_name}/${task_number_formatted}"

    has_tests=false
    if [ -d "$tests_dir" ]; then
        for f in "$tests_dir"/*.in; do
            if [ -f "$f" ]; then
                has_tests=true
                break
            fi
        done
    fi

    if [ "$has_tests" = false ]; then
        echo "No tests found for $file, skipping tests stage"
        echo "### FOR FILE $file NO TESTS" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    else
        test_passed=true
        passed_count=0

        for input_file in "$tests_dir"/*.in; do
            [ -f "$input_file" ] || continue

            test_name=$(basename "$input_file" .in)
            expected_file="${tests_dir}/${test_name}.out"

            if [ ! -f "$expected_file" ]; then
                echo "::warning file=$file::Expected output file not found: $expected_file"
                continue
            fi

            actual_file=$(mktemp)

            exit_code=0
            (ulimit -v 262144; timeout 5s ./student_program) < "$input_file" > "$actual_file" || exit_code=$?

            if [ "$exit_code" -eq 124 ]; then
                echo "::error file=$file::Test $test_name failed: Timeout (5s exceeded)"
                log_test_error "$test_name (TIMEOUT)" "$input_file" "$actual_file" "$expected_file"
                test_passed=false
                rm -f "$actual_file"
                break
            elif [ "$exit_code" -eq 137 ] || [ "$exit_code" -eq 134 ]; then
                # 137 = SIGKILL, 134 = SIGABRT (std::bad_alloc with ulimit -v)
                echo "::error file=$file::Test $test_name failed: Memory Limit Exceeded (256MB)"
                log_test_error "$test_name (MEMORY LIMIT)" "$input_file" "$actual_file" "$expected_file"
                test_passed=false
                rm -f "$actual_file"
                break
            fi

            actual_clean=$(mktemp)
            expected_clean=$(mktemp)

            normalize < "$actual_file" > "$actual_clean"
            normalize < "$expected_file" > "$expected_clean"

            if ! diff -w -B "$actual_clean" "$expected_clean" > /dev/null; then
                echo "::error file=$file::Test $test_name failed (Output mismatch)"
                log_test_error "$test_name" "$input_file" "$actual_file" "$expected_file"
                test_passed=false
                rm -f "$actual_file" "$actual_clean" "$expected_clean"
                break
            fi

            ((passed_count++)) || true
            rm -f "$actual_file" "$actual_clean" "$expected_clean"
        done

        if [ "$test_passed" = false ]; then
            FILE_FAILED=1
        else
            echo "### FOR FILE $file ALL $passed_count TESTS PASSED" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
        fi
    fi
    rm -f student_program
    if [ "$FILE_FAILED" -eq 1 ]; then
        OVERALL_FAILED=1
    fi

    echo "::endgroup::"

done <<< "$CHANGED_FILES"

if [ "$OVERALL_FAILED" -ne 0 ]; then
    {
      echo "### Overall Result: FAILED"
      echo "One or more files failed compilation or testing. Please fix the errors listed above."
    } >> "$SUMMARY_FILE"
    echo "::error::Homework check failed. See Step Summary for details."
    exit 1
fi

{
  echo "### Overall Result: ALL CHECKS PASSED"
  echo "All files were successfully compiled and tested."
} >> "$SUMMARY_FILE"