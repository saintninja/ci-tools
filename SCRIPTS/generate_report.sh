#!/bin/bash
# Usage: generate_report.sh [results_dir] [checks_spec]

RESULTS_DIR="${1:-test_results}"
CHECKS_SPEC="${2:-}"

if [ ! -d "$RESULTS_DIR" ]; then
    echo "Error: Results directory not found: $RESULTS_DIR" >&2
    exit 1
fi

shopt -s nullglob
result_files=("$RESULTS_DIR"/*.txt)
shopt -u nullglob

if [ ${#result_files[@]} -eq 0 ]; then
    echo "No test result files found in $RESULTS_DIR"
    exit 0
fi

trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "$1"; }

declare -A LABELS=()
IFS=',' read -ra spec_items <<< "$CHECKS_SPEC"
for item in "${spec_items[@]}"; do
    item=$(trim "$item")
    [ -z "$item" ] && continue
    key=$(trim "${item%%:*}")
    label="$key"
    if [[ "$item" == *:* ]]; then
        label=$(trim "${item#*:}")
    fi
    [ -n "$key" ] && LABELS["$key"]="${label:-$key}"
done

label_of() { echo "${LABELS[$1]:-$1}"; }

total=0
passed=0
failed=0

SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/tmp/github_summary.md}"

echo "# Homework Check Results" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

for result_file in "${result_files[@]}"; do
    total=$((total + 1))

    echo "INDIVIDUAL TEST REPORT"
    echo ""

    file_name=$(grep "^FILE:" "$result_file" 2>/dev/null | head -1 | sed 's/^FILE: //' || true)
    if [ -z "$file_name" ]; then
        file_name=$(basename "$result_file" _result.txt)
    fi

    echo "File: $file_name"
    echo ""

    check_keys=()
    check_values=()
    while IFS= read -r line; do
        entry="${line#CHECK: }"
        check_keys+=("${entry%%=*}")
        check_values+=("${entry#*=}")
    done < <(grep "^CHECK: " "$result_file" 2>/dev/null || true)

    width=0
    for key in "${check_keys[@]}"; do
        label=$(label_of "$key")
        [ ${#label} -gt $width ] && width=${#label}
    done

    print_checks() {
        if [ ${#check_keys[@]} -eq 0 ]; then
            return
        fi
        echo "Check Results:"
        local i
        for i in "${!check_keys[@]}"; do
            printf "  %-*s %s\n" $((width + 1)) "$(label_of "${check_keys[$i]}"):" "${check_values[$i]}"
        done
        echo ""
    }

    any_check_failed=false
    for value in "${check_values[@]}"; do
        [ "$value" = "FAIL" ] && any_check_failed=true
    done

    if grep -q "^COMPILATION: FAIL" "$result_file" 2>/dev/null; then
        echo "COMPILATION STATUS: FAIL"
        echo ""
        echo "The code did not compile. Please check the compiler output above."
        echo ""
        print_checks
        echo "OVERALL RESULT: FAIL"
        failed=$((failed + 1))

        echo "**COMPILE FAILED:** \`$file_name\`" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        echo "The code did not compile. Please check the compiler output in the logs." >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    else
        echo "COMPILATION STATUS: PASS"
        echo ""
        print_checks

        if grep -q "^OVERALL: PASS" "$result_file" 2>/dev/null && [ "$any_check_failed" = false ]; then
            echo "OVERALL RESULT: PASS"
            passed=$((passed + 1))

            echo "**COMPILE SUCCESS:** \`$file_name\`" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
            echo "FOR FILE \`$file_name\` ALL TESTS PASSED" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
        else
            echo "OVERALL RESULT: FAIL"
            failed=$((failed + 1))

            echo "**COMPILE SUCCESS:** \`$file_name\`" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
            echo "FOR FILE \`$file_name\` TESTS FAILED:" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"

            if grep -q "^TIMEOUT:" "$result_file" 2>/dev/null; then
                echo "- Time limit exceeded" >> "$SUMMARY_FILE"
            fi
            for i in "${!check_keys[@]}"; do
                if [ "${check_values[$i]}" = "FAIL" ]; then
                    echo "- $(label_of "${check_keys[$i]}"): FAIL" >> "$SUMMARY_FILE"
                fi
            done

            echo "" >> "$SUMMARY_FILE"
        fi
    fi

    echo ""
done

echo "---" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "**Summary:**" >> "$SUMMARY_FILE"
echo "- Total submissions: $total" >> "$SUMMARY_FILE"
echo "- Passed: $passed" >> "$SUMMARY_FILE"
echo "- Failed: $failed" >> "$SUMMARY_FILE"

echo "SUMMARY:"
echo "Total submissions: $total"
echo "Passed: $passed"
echo "Failed: $failed"

if [ $failed -gt 0 ]; then
    exit 1
else
    exit 0
fi