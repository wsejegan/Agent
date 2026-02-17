#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# HiveAgent v5.0 — Cleanup Utility
# Removes temporary artifacts, logs, and worktrees
# ═══════════════════════════════════════════════════════════════

echo "🧹 Cleaning up HiveAgent artifacts..."

# Clean logs older than 7 days
find logs/ -name "*.json" -mtime +7 -exec rm {} \; 2>/dev/null
echo "✅ Cleaned old logs"

# Clean temporary worktrees
git worktree prune
rm -rf /tmp/HiveAgent-* 2>/dev/null
echo "✅ Cleaned stale worktrees"

# Clean diffs
rm -rf /tmp/hiveagent-retry-diffs-* 2>/dev/null
echo "✅ Cleaned diff snapshots"

echo "✨ Cleanup complete."
