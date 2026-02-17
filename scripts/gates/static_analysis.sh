#!/bin/bash
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# Quality Gate: Static Analysis
# Checks for common anti-patterns
# ═══════════════════════════════════════════════════════════════

echo "🔍 Running static analysis..."

# Check key length in logs
if grep -r "sk-or-v1-" logs/ 2>/dev/null; then
    echo "🚨 ERROR: API Key leaked in logs!"
    exit 1
fi

# Check for TODOs
TODO_COUNT=$(grep -rq "TODO" services/$TARGET_SERVICE --include=*.go | wc -l)
if [ $TODO_COUNT -gt 5 ]; then
    echo "⚠️  WARNING: Too many TODOs ($TODO_COUNT > 5)"
    # Non-fatal warning
fi

# Check for hardcoded secrets (Basic patterns)
if grep -r "password =" services/$TARGET_SERVICE 2>/dev/null; then
    echo "🚨 ERROR: Potential hardcoded password found"
    exit 1
fi

echo "✅ Static analysis passed"
exit 0
