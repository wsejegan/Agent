#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# HiveAgent v5.0 — Native Dispatch (Git Worktree Isolation)
# Called by dispatch.sh when docker_compatible=false
# ═══════════════════════════════════════════════════════════════

SERVICE_NAME="$1"
TASK_PROMPT="$2"
WORKTREE_ID="HiveAgent-$(date +%s)-$SERVICE_NAME"
WORKTREE_DIR="/tmp/$WORKTREE_ID"
BRANCH_NAME="ai/$(date +%s)-$SERVICE_NAME"
ORIGINAL_DIR="$(pwd)"

cleanup() {
    echo "🧹 Cleaning up worktree..."
    cd "$ORIGINAL_DIR"
    git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
    
    if [ "${MISSION_SUCCESS:-false}" == "true" ]; then
        echo "✅ Mission successful. Merging $BRANCH_NAME into main..."
        git merge "$BRANCH_NAME" --no-ff -m "merge: ai mission complete [$SERVICE_NAME]"
    else
        echo "❌ Mission failed or aborted. Discarding $BRANCH_NAME..."
    fi
    git branch -D "$BRANCH_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# ── 1. Create Isolated Worktree ────────────────────────────────
echo "📂 Creating isolated worktree at $WORKTREE_DIR..."
git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME"
cd "$WORKTREE_DIR"

# ── 2. Snapshot: Hash all files OUTSIDE the target service ─────
echo "📸 Taking blast radius snapshot..."
BEFORE_HASH=$(find services/ -not -path "services/$SERVICE_NAME/*" \
    -not -path "services/$SERVICE_NAME" \
    -type f -exec shasum -a 256 {} \; 2>/dev/null | sort | shasum -a 256)

# ── 3. Enforce readable_paths as Read-Only ─────────────────────
# Prevent the agent from writing to shared paths declared in manifest
MANIFEST="services/$SERVICE_NAME/.hiveagent.yml"
if [ -f "$MANIFEST" ] && yq '.readable_paths' "$MANIFEST" 2>/dev/null | grep -q '\S'; then
    echo "🔒 Enforcing read-only access on shared paths..."
    yq '.readable_paths[]' "$MANIFEST" 2>/dev/null | while read rpath; do
        if [ -d "$rpath" ]; then
            chmod -R a-w "$rpath" 2>/dev/null || true
            echo "   🔒 Read-only: $rpath"
        fi
    done
fi

# ── 4. Run Worker Agent ────────────────────────────────────────
export TARGET_SERVICE="$SERVICE_NAME"
export TASK_PROMPT="$TASK_PROMPT"
export WORKSPACE_ROOT="$WORKTREE_DIR"
export EXECUTION_MODE="native"

# Portable timeout logic for MacOS
if command -v timeout &>/dev/null; then
    timeout 1800 ./scripts/worker_agent.sh
elif command -v perl &>/dev/null; then
    perl -e 'eval { local $SIG{ALRM} = sub { die "TIMEOUT\n" }; alarm shift; system(@ARGV); alarm 0 }; if ($@ eq "TIMEOUT\n") { exit 124 } exit ($? >> 8)' 1800 ./scripts/worker_agent.sh
else
    ./scripts/worker_agent.sh
fi
WORKER_EXIT=$?
if [ $WORKER_EXIT -eq 124 ]; then
    echo "⏰ MISSION TIMED OUT after 30 minutes"
fi

# ── 5. Restore write permissions on shared paths ───────────────
if [ -f "$MANIFEST" ] && yq '.readable_paths' "$MANIFEST" 2>/dev/null | grep -q '\S'; then
    yq '.readable_paths[]' "$MANIFEST" 2>/dev/null | while read rpath; do
        [ -d "$rpath" ] && chmod -R u+w "$rpath" 2>/dev/null || true
    done
fi

# ── 6. Blast Radius Verification ───────────────────────────────
echo ""
echo "🔍 Verifying blast radius..."
AFTER_HASH=$(find services/ -not -path "services/$SERVICE_NAME/*" \
    -not -path "services/$SERVICE_NAME" \
    -type f -exec shasum -a 256 {} \; 2>/dev/null | sort | shasum -a 256)

if [ "$BEFORE_HASH" != "$AFTER_HASH" ]; then
    echo "🚨 ═══════════════════════════════════════════════════"
    echo "🚨 BLAST RADIUS BREACH DETECTED!"
    echo "🚨 Files outside services/$SERVICE_NAME were modified."
    echo "🚨 ═══════════════════════════════════════════════════"
    echo ""
    echo "Modified files outside target:"
    git diff --name-only | grep -v "^services/$SERVICE_NAME/" || true
    echo ""
    echo "All changes have been discarded. Worktree will be destroyed."
    
    # Update audit log
    if [ -n "${LOG_FILE:-}" ]; then
        jq '.result = "blast_radius_breach"' "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
    exit 1
fi

echo "✅ Blast radius verified: Only services/$SERVICE_NAME was touched."

if [ $WORKER_EXIT -eq 0 ]; then
    MISSION_SUCCESS="true"
fi

exit $WORKER_EXIT
