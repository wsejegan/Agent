#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# HiveAgent v5.0 — Fleet Status Dashboard
# Shows all services, their mode, and readiness
# ═══════════════════════════════════════════════════════════════

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                    HiveAgent v5.0 — SERVICE FLEET STATUS                   ║"
echo "╠════════════════════╦══════════╦════════════════╦══════════════════════╣"
echo "║ Service            ║ Runtime  ║ Mode           ║ Tests Defined?       ║"
echo "╠════════════════════╬══════════╬════════════════╬══════════════════════╣"

for dir in services/*/; do
    [ ! -d "$dir" ] && continue
    NAME=$(basename "$dir")
    MANIFEST="$dir/.hiveagent.yml"
    
    if [ -f "$MANIFEST" ]; then
        RUNTIME=$(grep '^runtime' "$MANIFEST" | awk '{print $2}' | tr -d '"')
        DOCKER=$(grep 'docker_compatible' "$MANIFEST" | awk '{print $2}' | tr -d '"')
        TEST_CMD=$(grep 'test_command' "$MANIFEST" | sed 's/test_command: *//' | tr -d '"')
        
        MODE=$( [ "$DOCKER" == "true" ] && echo "🐳 Docker" || echo "🖥️  Native" )
        TESTS=$( [ -n "$TEST_CMD" ] && echo "✅ $TEST_CMD" || echo "⚠️  None" )
    else
        RUNTIME="???"
        MODE="⚠️  No manifest"
        TESTS="⚠️  Unknown"
    fi
    
    printf "║ %-18s ║ %-8s ║ %-14s ║ %-20s ║\n" "$NAME" "$RUNTIME" "$MODE" "$TESTS"
done

echo "╚════════════════════╩══════════╩════════════════╩══════════════════════╝"
echo ""

# Show recent mission logs
if [ -d "logs" ] && ls logs/*.json 1>/dev/null 2>&1; then
    echo "📋 Recent Missions (last 5):"
    echo "─────────────────────────────────────────────────────"
    ls -t logs/*.json | head -5 | while read logfile; do
        SERVICE=$(jq -r '.service' "$logfile")
        RESULT=$(jq -r '.result' "$logfile")
        TASK=$(jq -r '.task' "$logfile" | head -c 50)
        ICON=$( [ "$RESULT" == "success" ] && echo "✅" || echo "❌" )
        echo "  $ICON $SERVICE — $TASK"
    done
    echo ""
fi
