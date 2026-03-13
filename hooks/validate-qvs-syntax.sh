#!/bin/bash
################################################################################
# validate-qvs-syntax.sh
#
# Qlik Script Validation Hook
#
# Purpose:
#   Detects high-confidence syntax errors in .qvs (Qlik script) files before
#   they reach execution validation gates. This hook scans for SQL constructs
#   that do not exist in Qlik LOAD context, unbalanced control blocks, and
#   malformed function arguments.
#
# Key Distinction - SQL Pass-Through vs LOAD Context:
#   Qlik scripts allow two contexts:
#   1. LOAD context: Native Qlik language (LOAD, RESIDENT, WHERE, etc.)
#   2. SQL pass-through: Direct SQL to database (SQL SELECT ... ;)
#
#   This hook ONLY flags SQL constructs in LOAD context. Constructs inside
#   SQL blocks (between "SQL" and ";") are legitimate and are EXCLUDED from checks.
#
# Critical SQL Constructs Not Allowed in Qlik LOAD Context:
#   - HAVING           (aggregate filtering; use preceding LOAD instead)
#   - Count(*)         (aggregation; use Count(field_name) instead)
#   - IS NULL/NOT NULL (null checking; use IsNull(field) function instead)
#   - BETWEEN          (range filtering; use >= AND <= instead)
#   - CASE WHEN        (conditional; use IF(), Pick(), Match() instead)
#   - IN (list)        (value matching; use Match() or WildMatch() instead)
#   - LIMIT            (row limiting; use WHERE RowNo() <= N instead)
#   - Table aliases    (FROM t1; use full table names in brackets instead)
#   - SELECT DISTINCT  (for LOAD context; use LOAD DISTINCT instead)
#
# Checks Applied:
#   1. SQL Constructs in LOAD context
#   2. Block balance (IF/END IF, SUB/END SUB, FOR/NEXT)
#   3. PurgeChar() argument count validation
#
# Exit Codes:
#   0 = No findings (file is clean)
#   1 = Findings present (warnings generated)
#   2 = Error (file not found, unreadable, or script error)
#
# Usage:
#   ./validate-qvs-syntax.sh file.qvs
#   ./validate-qvs-syntax.sh artifacts/04-scripts/*.qvs
################################################################################

set -u

# Colors for output (optional, may not be available in all shells)
WARN_PREFIX="[WARN]"

# Accumulate findings
findings=""
exit_code=0

# Function to add a finding
add_finding() {
    local file="$1"
    local line="$2"
    local message="$3"

    if [ -z "$line" ]; then
        findings="${findings}${WARN_PREFIX} ${file}: ${message}"$'\n'
    else
        findings="${findings}${WARN_PREFIX} ${file}:${line}: ${message}"$'\n'
    fi
    exit_code=1
}

# Process a single file
process_file() {
    local file="$1"

    # Check file exists and is readable
    if [ ! -f "$file" ]; then
        add_finding "$file" "" "File not found"
        return 2
    fi

    if [ ! -r "$file" ]; then
        add_finding "$file" "" "File not readable"
        return 2
    fi

    local line_num=0
    local in_sql=0
    local if_count=0
    local endif_count=0
    local sub_count=0
    local endsub_count=0
    local for_count=0
    local foreach_count=0
    local next_count=0

    # Read file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))

        # Handle CRLF line endings
        line="${line%$'\r'}"

        # Track SQL block boundaries (simplified state machine)
        # Check if entering SQL block (must start with SQL keyword)
        if echo "$line" | grep -iq '^\s*SQL\s'; then
            in_sql=1
        fi

        # Check if exiting SQL block (line contains semicolon terminator)
        # This can happen on the same line as "SQL" or on a later line
        if [ "$in_sql" -eq 1 ] && echo "$line" | grep -q ';'; then
            in_sql=0
            # Skip remaining checks for SQL terminator line
            continue
        fi

        # Skip checks inside SQL blocks (except terminator lines which we already skipped)
        if [ "$in_sql" -eq 1 ]; then
            continue
        fi

        # ===== SQL Construct Checks (LOAD context only) =====

        # 1. HAVING (case-insensitive, word boundaries)
        if echo "$line" | grep -iqE '\bHAVING\b'; then
            add_finding "$file" "$line_num" "SQL construct 'HAVING' found in LOAD context. Use preceding LOAD with filter instead."
        fi

        # 2. Count(*) - case insensitive, with asterisk
        if echo "$line" | grep -iqE '[Cc]ount\s*\(\s*\*\s*\)'; then
            add_finding "$file" "$line_num" "Count(*) not supported. Use Count(field_name) with explicit field reference."
        fi

        # 3. IS NULL or IS NOT NULL (case-insensitive, word boundaries)
        if echo "$line" | grep -iqE '\bIS\s+(NOT\s+)?NULL\b'; then
            # But not if it's the function IsNull()
            if ! echo "$line" | grep -iq 'IsNull('; then
                add_finding "$file" "$line_num" "'IS NULL' / 'IS NOT NULL' not supported in Qlik script. Use IsNull() function."
            fi
        fi

        # 4. BETWEEN (case-insensitive, word boundaries)
        if echo "$line" | grep -iqE '\bBETWEEN\b'; then
            add_finding "$file" "$line_num" "'BETWEEN' not supported. Use field >= low AND field <= high."
        fi

        # 5. CASE WHEN (both keywords present, case-insensitive)
        if echo "$line" | grep -iqE '\bCASE\b' && echo "$line" | grep -iqE '\bWHEN\b'; then
            add_finding "$file" "$line_num" "'CASE WHEN' not supported in Qlik LOAD. Use IF(), Pick(), or Match() instead."
        fi

        # 6. LIMIT (case-insensitive, word boundaries, followed by number)
        if echo "$line" | grep -iqE '\bLIMIT\s+[0-9]'; then
            add_finding "$file" "$line_num" "'LIMIT' not supported in Qlik LOAD. Use WHERE RowNo() <= N on a RESIDENT LOAD."
        fi

        # 7. IN (list) - pattern: IN followed by parentheses
        if echo "$line" | grep -iqE '\bIN\s*\('; then
            add_finding "$file" "$line_num" "'IN (list)' not supported. Use Match(field, val1, val2, ...) or WildMatch()."
        fi

        # 8. SELECT DISTINCT in LOAD context (not in SQL blocks, which are already skipped)
        if echo "$line" | grep -iqE 'SELECT\s+DISTINCT'; then
            add_finding "$file" "$line_num" "'SELECT DISTINCT' not allowed in LOAD context. Use 'LOAD DISTINCT' instead."
        fi

        # ===== Block Balance Checks =====

        # Count IF THEN blocks (not IF() function calls)
        # Pattern: IF (word boundary) followed by THEN (not immediately followed by parenthesis)
        # This distinguishes control blocks "IF ... THEN" from function calls "IF(...)"
        if echo "$line" | grep -iqE '\bIF\s+(.*\s+)?THEN\b'; then
            if_count=$((if_count + 1))
        fi

        # Count END IF (case-insensitive, handles both "END IF" and "ENDIF")
        endif_line_count=$(echo "$line" | grep -io '\bEND\s*IF\b' | wc -l)
        endif_count=$((endif_count + endif_line_count))

        # Count SUB declarations (case-insensitive, word boundary start, followed by space/paren)
        # Avoid counting "sub" within other words; must be a standalone SUB keyword
        if echo "$line" | grep -iqE '^\s*SUB\s|^\s*SUB\('; then
            sub_count=$((sub_count + 1))
        fi

        # Count END SUB (case-insensitive)
        endsub_line_count=$(echo "$line" | grep -io '\bEND\s*SUB\b' | wc -l)
        endsub_count=$((endsub_count + endsub_line_count))

        # Count FOR (case-insensitive, word boundary)
        for_line_count=$(echo "$line" | grep -io '\bFOR\b' | wc -l)
        for_count=$((for_count + for_line_count))

        # Count FOR EACH (case-insensitive)
        foreach_line_count=$(echo "$line" | grep -io '\bFOR\s+EACH\b' | wc -l)
        foreach_count=$((foreach_count + foreach_line_count))

        # Count NEXT (case-insensitive, word boundary)
        next_line_count=$(echo "$line" | grep -io '\bNEXT\b' | wc -l)
        next_count=$((next_count + next_line_count))

        # ===== PurgeChar Argument Count Check =====

        # Find PurgeChar with single argument (no comma inside parentheses)
        # Pattern: PurgeChar\s*\([^,)]*\)
        if echo "$line" | grep -iqE '[Pp]urge[Cc]har\s*\([^,)]*\)'; then
            add_finding "$file" "$line_num" "PurgeChar() called with 1 argument (expected 2). Provide both text and chars_to_remove."
        fi

    done < "$file"

    # Check block balance after entire file is read
    if [ "$if_count" -ne "$endif_count" ]; then
        add_finding "$file" "" "Block imbalance: $if_count 'IF' found but $endif_count 'END IF' found. Check IF/END IF pairing."
    fi

    if [ "$sub_count" -ne "$endsub_count" ]; then
        add_finding "$file" "" "Block imbalance: $sub_count 'SUB' found but $endsub_count 'END SUB' found. Check SUB/END SUB pairing."
    fi

    # FOR and FOR EACH both map to NEXT
    local for_total=$((for_count + foreach_count))
    if [ "$for_total" -ne "$next_count" ]; then
        add_finding "$file" "" "Block imbalance: $for_total 'FOR/FOR EACH' found but $next_count 'NEXT' found. Check FOR/NEXT pairing."
    fi

    return 0
}

# Main: Determine file path from arguments or PostToolUse hook stdin
if [ $# -gt 0 ]; then
    # Direct invocation with file arguments
    files=("$@")
else
    # PostToolUse hook invocation: file path arrives as JSON on stdin.
    # Extract tool_input.file_path using jq (or grep fallback).
    hook_input=$(cat)
    if command -v jq &>/dev/null; then
        hook_file=$(echo "$hook_input" | jq -r '.tool_input.file_path // empty')
    else
        # Fallback: extract file_path with grep/sed if jq unavailable
        hook_file=$(echo "$hook_input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
    fi

    if [ -z "${hook_file:-}" ]; then
        # No file path found in stdin or args; nothing to do
        exit 0
    fi
    files=("$hook_file")
fi

for file in "${files[@]}"; do
    # Only validate .qvs files; skip everything else silently
    case "$file" in
        *.qvs) process_file "$file" ;;
        *)     ;;
    esac
done

# Output all findings
if [ -n "$findings" ]; then
    echo -n "$findings"
fi

exit "$exit_code"
