#!/bin/bash
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# HiveAgent v5.0 — Quality Gate Pipeline
# Runs all checks in scripts/gates/ and aggregates results
# ═══════════════════════════════════════════════════════════════

GATE_DIR="$(dirname "$0")/gates"
FAILED=0

echo "🏗️  Starting Quality Gate Pipeline..."
echo "─────────────────────────────────────────────────────"

if [ ! -d "$GATE_DIR" ]; then
    echo "⚠️  No gates directory found at $GATE_DIR"
    exit 0
fi

for gate in "$GATE_DIR"/*.sh; do
    [ ! -x "$gate" ] && continue
    GATE_NAME=$(basename "$gate" .sh)
    
    echo "running $GATE_NAME..."
    OUTPUT=$("$gate" 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ PASS: $GATE_NAME"
    else
        echo "❌ FAIL: $GATE_NAME"
        echo "$OUTPUT" | sed 's/^/   /'
        FAILED=1
    fi
    echo "─────────────────────────────────────────────────────"
done

if [ $FAILED -eq 1 ]; then
    echo "🚫 PIPELINE FAILED"
    exit 1
else
    echo "✨ PIPELINE PASSED"
    exit 0
fi
