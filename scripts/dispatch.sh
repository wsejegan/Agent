#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# HiveAgent v5.0 — Hybrid Dispatcher
# USAGE: ./scripts/dispatch.sh <SERVICE_NAME> "<TASK_PROMPT>"
# ═══════════════════════════════════════════════════════════════

SERVICE_NAME="${1:?❌ Usage: dispatch.sh <SERVICE_NAME> <TASK_PROMPT>}"
TASK_PROMPT="${2:?❌ Usage: dispatch.sh <SERVICE_NAME> <TASK_PROMPT>}"
MANIFEST="services/$SERVICE_NAME/.hiveagent.yml"
LOG_DIR="logs"
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)
LOG_FILE="$(pwd)/$LOG_DIR/${TIMESTAMP}-${SERVICE_NAME}.json"
LOCK_FILE="services/$SERVICE_NAME/.hiveagent.lock"

# ── 0. Check Prerequisites (yq required) ──────────────────────
if ! command -v yq &>/dev/null; then
    echo "❌ ERROR: 'yq' is required but not installed."
    echo "   Install: https://github.com/mikefarah/yq#install"
    echo "   brew install yq  |  snap install yq  |  go install github.com/mikefarah/yq/v4@latest"
    exit 1
fi

LOCK_DIR="services/$SERVICE_NAME/.hiveagent.lock.dir"

# ── 1. Validate Target ─────────────────────────────────────────
if [ ! -d "services/$SERVICE_NAME" ]; then
    echo "❌ ERROR: Service '$SERVICE_NAME' not found in services/ directory."
    echo ""
    echo "Available targets:"
    for dir in services/*/; do
        [ -d "$dir" ] && echo "  → $(basename "$dir")"
    done
    exit 1
fi

# ── 1.5 Acquire Per-Service Lock ───────────────────────────────
# Prevents concurrent agents from dispatching to the same service
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "🔒 ERROR: Service '$SERVICE_NAME' is already being processed by another agent."
    echo "   Lock directory: $LOCK_DIR"
    echo "   If this is stale, remove it: rm -rf $LOCK_DIR"
    exit 1
fi
echo "🔓 Lock acquired for $SERVICE_NAME"

# Ensure lock is released on exit
release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}
trap release_lock EXIT

# ── 2. Read Service Manifest (via yq) ──────────────────────────
if [ -f "$MANIFEST" ]; then
    DOCKER_COMPATIBLE=$(yq '.docker_compatible // false' "$MANIFEST")
    RUNTIME=$(yq '.runtime // "unknown"' "$MANIFEST")
    MAX_RETRIES=$(yq '.max_retries // 3' "$MANIFEST")
    MAX_COST=$(yq '.max_cost_usd // 5.00' "$MANIFEST")
    SETUP_CMD=$(yq '.setup_command // ""' "$MANIFEST")
    TOKEN_BUDGET=$(yq '.token_budget // 50000' "$MANIFEST")
else
    echo "⚠️  No .hiveagent.yml found for '$SERVICE_NAME'. Defaulting to native mode."
    DOCKER_COMPATIBLE="false"
    RUNTIME="unknown"
    MAX_RETRIES=3
    MAX_COST="5.00"
    SETUP_CMD=""
    TOKEN_BUDGET=50000
fi

# ── 3. Initialize Audit Log ────────────────────────────────────
mkdir -p "$LOG_DIR"
cat > "$LOG_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "service": "$SERVICE_NAME",
  "task": "$TASK_PROMPT",
  "runtime": "$RUNTIME",
  "mode": "$([ "$DOCKER_COMPATIBLE" == "true" ] && echo "docker" || echo "native")",
  "max_retries": $MAX_RETRIES,
  "max_cost_usd": $MAX_COST,
  "result": "in_progress",
  "attempts": 0,
  "pr_url": null,
  "error": null
}
EOF

# ── 4. Display Mission Brief ───────────────────────────────────
echo "╔══════════════════════════════════════════════════════╗"
echo "║           HiveAgent v5.0 — MISSION BRIEF                 ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  🎯 Target:   $SERVICE_NAME"
echo "║  📝 Mission:  $TASK_PROMPT"
echo "║  ⚙️  Runtime:  $RUNTIME"
echo "║  🔄 Retries:  $MAX_RETRIES"
echo "║  💰 Budget:   \$$MAX_COST"
echo "║  🚀 Mode:     $([ "$DOCKER_COMPATIBLE" == "true" ] && echo "🐳 Docker" || echo "🖥️  Native")"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 5. Route: Docker or Native ─────────────────────────────────
export TARGET_SERVICE="$SERVICE_NAME"
export TASK_PROMPT="$TASK_PROMPT"
export MAX_RETRIES="$MAX_RETRIES"
export MAX_COST_USD="$MAX_COST"
export TOKEN_BUDGET="$TOKEN_BUDGET"
export LOG_FILE="$LOG_FILE"
export SETUP_CMD="$SETUP_CMD"
export RUNTIME="$RUNTIME"

# Source environment variables
if [ -f .env ]; then
    echo "🔑 Loading secrets from .env..."
    export $(cat .env | grep -v '^#' | xargs)
fi

if [ "$DOCKER_COMPATIBLE" == "true" ]; then
    echo "🐳 Launching Docker-isolated execution..."
    echo ""
    
    CUSTOM_IMAGE=$(yq '.docker_image // ""' "$MANIFEST" 2>/dev/null)
    
    # Run Docker Compose
    # Maps secrets and config into the container
    docker compose run --rm \
      -e TARGET_SERVICE="$SERVICE_NAME" \
      -e TASK_PROMPT="$TASK_PROMPT" \
      -e MAX_RETRIES="$MAX_RETRIES" \
      -e MAX_COST_USD="$MAX_COST" \
      -e SETUP_CMD="$SETUP_CMD" \
      -e OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
      -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
      ${CUSTOM_IMAGE:+-e DOCKER_IMAGE="$CUSTOM_IMAGE"} \
      -v "$HOME/.ssh:/root/.ssh:ro" \
      -v "$HOME/.gitconfig:/root/.gitconfig:ro" \
      hiveagent-worker
    EXIT_CODE=$?
else
    echo "🖥️  Launching native execution with worktree isolation..."
    echo ""
    
    # Check prerequisites
    if yq '.prerequisites' "$MANIFEST" 2>/dev/null | grep -q '\S'; then
        echo "⚠️  Prerequisites for $SERVICE_NAME:"
        yq '.prerequisites[]' "$MANIFEST" 2>/dev/null | sed 's/^/   → /'
        echo ""
        # In automated mode, we assume yes if prerequisites are met
        # read -p "Are all prerequisites met? (y/n): " CONFIRM
        CONFIRM="y" 
        if [ "$CONFIRM" != "y" ]; then
            echo "Aborted by user."
            # Update audit log
            jq '.result = "aborted"' "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
            exit 1
        fi
    fi
    
    ./scripts/dispatch_native.sh "$SERVICE_NAME" "$TASK_PROMPT"
    EXIT_CODE=$?
fi

# ── 6. Final Status ────────────────────────────────────────────
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "════════════════════════════════════════════════"
    echo "✅ MISSION COMPLETE — PR submitted for review"
    echo "════════════════════════════════════════════════"
else
    echo ""
    echo "════════════════════════════════════════════════"
    echo "❌ MISSION FAILED — See $LOG_FILE for details"
    echo "════════════════════════════════════════════════"
fi

exit $EXIT_CODE
