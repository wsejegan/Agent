#!/bin/bash
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# Quality Gate: Coverage Check
# ═══════════════════════════════════════════════════════════════

echo "📊 Checking test coverage..."

# Simple regex check for 'Test' functions in new files
NEW_FILES=$(git diff --name-only --cached --diff-filter=ACM | grep ".go$")

if [ -z "$NEW_FILES" ]; then
    echo "✅ No new Go files to check coverage for."
    exit 0
fi

MISSING_TESTS=0
for file in $NEW_FILES; do
    if [[ "$file" == *"_test.go" ]]; then
        continue
    fi
    
    TEST_FILE="${file%.go}_test.go"
    if [ ! -f "$TEST_FILE" ]; then
        echo "⚠️  WARNING: New file '$file' has no corresponding '$TEST_FILE'"
        MISSING_TESTS=1
    fi
done

if [ $MISSING_TESTS -eq 1 ]; then
    echo "❌ Coverage check failed: Missing test files for new code."
    exit 1
fi

echo "✅ Coverage check passed (basic existence check)"
exit 0
