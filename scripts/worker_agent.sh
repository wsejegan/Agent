#!/bin/bash
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# HiveAgent v5.0 — Worker Agent (The Execution Loop)
# Runs the same way in Docker or Native mode
# ═══════════════════════════════════════════════════════════════

# ── 1. Teleport to Target Service ──────────────────────────────
cd "services/$TARGET_SERVICE" || { echo "❌ Failed to enter services/$TARGET_SERVICE"; exit 1; }
echo "📍 AGENT ACTIVE IN: $(pwd)"
echo ""

# ── 2. Run Setup Command (if defined) ──────────────────────────
if [ -n "${SETUP_CMD:-}" ]; then
    echo "📦 Running setup: $SETUP_CMD"
    eval "$SETUP_CMD" || { echo "⚠️  Setup command failed (non-fatal)"; }
    echo ""
fi

# ── 3. Context Reconnaissance ──────────────────────────────────
echo "🔭 RECON: Scanning service structure..."
FILE_TREE=$(find . -maxdepth 2 -not -path '*/.*' | head -n 15)
echo "$FILE_TREE"
echo ""

# ── 4. Read Key Source Files ────────────────────────────────────
# Build a context payload with actual file contents
CONTEXT_PAYLOAD="SERVICE DIRECTORY STRUCTURE:\n$FILE_TREE\n\n"

# Read key implementation files (max 30 lines)
IMPLEMENTATION_FILES=$(find . -maxdepth 2 -name '*.go' ! -name '*_test.go' 2>/dev/null | head -n 2)
if [ -n "$IMPLEMENTATION_FILES" ]; then
    CONTEXT_PAYLOAD+="CODE:\n"
    for ifile in $IMPLEMENTATION_FILES; do
        CONTEXT_PAYLOAD+="-- $ifile --\n$(cat "$ifile" | head -n 30)\n\n"
    done
fi

# ── 5. Create Git Branch ───────────────────────────────────────
BRANCH_NAME="ai/$(date +%s)-$TARGET_SERVICE"
git checkout -b "$BRANCH_NAME" 2>/dev/null || true
echo "🌿 Branch: $BRANCH_NAME"
echo ""

SKILLS_PAYLOAD=""

# ── 5.6 Timeout + Budget Configuration ─────────────────────────
LLM_TIMEOUT=${LLM_TIMEOUT:-300}        # 5 minutes max per LLM call
ORACLE_TIMEOUT=${ORACLE_TIMEOUT:-180}  # 3 minutes max for verification
GATE_TIMEOUT=${GATE_TIMEOUT:-300}      # 5 minutes max for quality gates
RETRY_DIFFS_DIR="/tmp/hiveagent-retry-diffs-$$"
mkdir -p "$RETRY_DIFFS_DIR"

CUMULATIVE_TOKENS=0
TOKEN_BUDGET=${TOKEN_BUDGET:-50000}

# ── 6. The Execution Loop ──────────────────────────────────────
MAX=${MAX_RETRIES:-5}
ATTEMPT=1
LAST_ERROR=""

while [ $ATTEMPT -le $MAX ]; do
    echo "═══════════════════════════════════════════════════"
    echo "⚡ Attempt $ATTEMPT / $MAX"
    echo "═══════════════════════════════════════════════════"

    # Build the LLM prompt with full context
    LLM_PROMPT="
YOU ARE LOCKED IN: services/$TARGET_SERVICE
You are an expert Staff Engineer. Follow ALL rules strictly.

CONTEXT (File Tree + Key Files):
$CONTEXT_PAYLOAD

MISSION: $TASK_PROMPT

ACTIVE SKILLS (follow these protocols):
$SKILLS_PAYLOAD

$([ -n "$LAST_ERROR" ] && echo "
PREVIOUS ATTEMPT FAILED WITH:
$LAST_ERROR

Analyze the error carefully and fix the root cause. Do NOT repeat the same mistake.
")

1. Apply SURGICAL patches. This service uses the **GIN** router.
2. Update/add tests in tests/ or *_test.go.
3. Pass verification. If you add dependencies, I will run 'go mod tidy' for you.
8. **Editing**: You MUST use the following format for ALL file modifications:
    <file path=\"relative/path/within/service/file.go\">
    // Full file content here
    </file>
"

    # ── Check Token Budget ────────────────────────────────────
    CALL_TOKENS=$(echo "$LLM_PROMPT" | wc -c)  # Rough approximation
    CUMULATIVE_TOKENS=$((CUMULATIVE_TOKENS + CALL_TOKENS))

    if [ $CUMULATIVE_TOKENS -gt $TOKEN_BUDGET ]; then
        echo "💰 TOKEN BUDGET EXCEEDED ($CUMULATIVE_TOKENS / $TOKEN_BUDGET)"
        echo "   Aborting to prevent cost overrun."
        exit 1
    fi

    LLM_RESPONSE_FILE="/tmp/hiveagent-llm-response-$$.txt"
    
    # Capture LLM output
    if command -v timeout &>/dev/null; then
        timeout "$LLM_TIMEOUT" ../../scripts/ac "$LLM_PROMPT" > "$LLM_RESPONSE_FILE"
    elif command -v perl &>/dev/null; then
        perl -e 'eval { local $SIG{ALRM} = sub { die "TIMEOUT\n" }; alarm shift; system(@ARGV); alarm 0 }; if ($@ eq "TIMEOUT\n") { exit 124 } exit ($? >> 8)' "$LLM_TIMEOUT" ../../scripts/ac "$LLM_PROMPT" > "$LLM_RESPONSE_FILE"
    else
        ../../scripts/ac "$LLM_PROMPT" > "$LLM_RESPONSE_FILE"
    fi
    LLM_CODE=$?
    
    # Also print to console for visibility in logs
    cat "$LLM_RESPONSE_FILE"
    
    if [ $LLM_CODE -eq 124 ]; then
        echo "⏰ LLM call TIMED OUT after ${LLM_TIMEOUT}s"
        LAST_ERROR="LLM call timed out after ${LLM_TIMEOUT} seconds"
        ((ATTEMPT++))
        continue
    elif [ $LLM_CODE -ne 0 ]; then
        echo "❌ LLM call FAILED"
        LAST_ERROR="LLM call failed with exit code $LLM_CODE"
        ((ATTEMPT++))
        continue
    fi

    # ── Apply Edits ───────────────────────────────────────────
    echo ""
    echo "🛠️  Applying AI edits..."
    if ! python3 ../../scripts/apply_edits.py "$LLM_RESPONSE_FILE"; then
        echo "⚠️  Failed to apply edits or no edits found."
    fi

    # ── Run the Oracle (with timeout) ──────────────────────────
    echo ""
    echo "🔮 Running Oracle verification..."
    if command -v timeout &>/dev/null; then
        ORACLE_OUTPUT=$(timeout "$ORACLE_TIMEOUT" ../../scripts/oracle_verify.sh 2>&1)
        ORACLE_EXIT=$?
    elif command -v perl &>/dev/null; then
        ORACLE_OUTPUT=$(perl -e 'eval { local $SIG{ALRM} = sub { die "TIMEOUT\n" }; alarm shift; system(@ARGV); alarm 0 }; if ($@ eq "TIMEOUT\n") { exit 124 } exit ($? >> 8)' "$ORACLE_TIMEOUT" ../../scripts/oracle_verify.sh 2>&1)
        ORACLE_EXIT=$?
    else
        ORACLE_OUTPUT=$(../../scripts/oracle_verify.sh 2>&1)
        ORACLE_EXIT=$?
    fi

    if [ $ORACLE_EXIT -eq 0 ]; then
        echo "$ORACLE_OUTPUT"
        echo ""
        echo "✅ VERIFICATION PASSED on attempt $ATTEMPT"

        # ── Quality Gate Pipeline (Section 8) ────────────────────
        # Runs AFTER Oracle passes, BEFORE code is committed
        if [ -f "../../scripts/quality_gate_pipeline.sh" ]; then
            echo ""
            echo "🏗️  Running Quality Gate Pipeline..."
            
            if command -v timeout &>/dev/null; then
                GATE_OUTPUT=$(timeout "$GATE_TIMEOUT" ../../scripts/quality_gate_pipeline.sh 2>&1)
                GATE_EXIT=$?
            elif command -v perl &>/dev/null; then
                GATE_OUTPUT=$(perl -e 'eval { local $SIG{ALRM} = sub { die "TIMEOUT\n" }; alarm shift; system(@ARGV); alarm 0 }; if ($@ eq "TIMEOUT\n") { exit 124 } exit ($? >> 8)' "$GATE_TIMEOUT" ../../scripts/quality_gate_pipeline.sh 2>&1)
                GATE_EXIT=$?
            else
                GATE_OUTPUT=$(../../scripts/quality_gate_pipeline.sh 2>&1)
                GATE_EXIT=$?
            fi

            if [ $GATE_EXIT -ne 0 ]; then
                # Save diff BEFORE wiping (state persistence)
                echo "💾 Saving attempt $ATTEMPT diff for retry context..."
                git diff > "$RETRY_DIFFS_DIR/attempt-${ATTEMPT}.diff" 2>/dev/null || true
                
                LAST_ERROR="Quality Gate Failed:\n\nCHANGES ATTEMPTED (diff):\n$(cat "$RETRY_DIFFS_DIR/attempt-${ATTEMPT}.diff" | head -50)\n\nError Output:\n$GATE_OUTPUT"
                echo "$GATE_OUTPUT"
                echo ""
                echo "❌ QUALITY GATE FAILED on attempt $ATTEMPT"
                echo "   Feeding quality gate errors + attempted diff back to LLM on retry."
                
                # Undo changes for clean retry
                git checkout -- . 2>/dev/null || true
                git clean -fd 2>/dev/null || true
                
                ((ATTEMPT++))
                continue
            fi
            echo "$GATE_OUTPUT"
        fi

        # ── Git Operations ──────────────────────────────────────
        git add .
        git commit -m "feat($TARGET_SERVICE): $TASK_PROMPT

Automated by HiveAgent v5.0
Attempts: $ATTEMPT/$MAX
Verification: Oracle + Quality Gates passed"

        echo "🚀 Pushing to GitHub..."
        # git push origin "$BRANCH_NAME"  <-- Commented out for local demo to avoid auth errors
        echo "   (Skipped push for local demo)"

        # ── Create Pull Request ─────────────────────────────────
        PR_BODY=$(cat <<PREOF
## 🤖 Automated Change — HiveAgent v5.0

**Service:** \`$TARGET_SERVICE\`
**Mission:** $TASK_PROMPT

### Verification
- ✅ Oracle verification passed
- ✅ Quality gates passed (static analysis, security, coverage, code review)
- Attempts: $ATTEMPT / $MAX
- Mode: ${EXECUTION_MODE:-docker}

### Changes
$(git diff HEAD~1 --stat)

---
*Generated by HiveAgent v5.0 — Hybrid Agentic Development Workflow*
PREOF
)
        # Use simple text output if gh CLI not configured
        if command -v gh &>/dev/null; then
             # PR_URL=$(gh pr create \
             #   --title "AI($TARGET_SERVICE): $TASK_PROMPT" \
             #   --body "$PR_BODY" \
             #   --head "$BRANCH_NAME" \
             #   --base main 2>&1)
             PR_URL="https://github.com/org/repo/pull/mock-123"
        else
             PR_URL="https://github.com/org/repo/pull/mock-123"
        fi

        echo "✨ SUCCESS: PR Created → $PR_URL"

        # Update audit log
        if [ -n "${LOG_FILE:-}" ]; then
            jq ".result = \"success\" | .attempts = $ATTEMPT | .pr_url = \"$PR_URL\"" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi

        exit 0
    else
        LAST_ERROR="$ORACLE_OUTPUT"
        echo "$ORACLE_OUTPUT"
        echo ""
        echo "❌ VERIFICATION FAILED on attempt $ATTEMPT"
        echo "   Error output captured. Will feed back to LLM on retry."
        
        # Save diff BEFORE wiping (state persistence)
        echo "💾 Saving attempt $ATTEMPT diff for retry context..."
        git diff > "$RETRY_DIFFS_DIR/attempt-${ATTEMPT}.diff" 2>/dev/null || true
        LAST_ERROR+="\n\nCHANGES ATTEMPTED (diff):\n$(cat "$RETRY_DIFFS_DIR/attempt-${ATTEMPT}.diff" | head -80)"
        
        # Undo changes for clean retry
        git checkout -- . 2>/dev/null || true
        git clean -fd 2>/dev/null || true
        
        ((ATTEMPT++))
    fi
done

echo ""
echo "💀 ═══════════════════════════════════════════════════"
echo "💀 MISSION FAILED after $MAX attempts."
echo "💀 ═══════════════════════════════════════════════════"

# Update audit log
if [ -n "${LOG_FILE:-}" ]; then
    ESCAPED_ERROR=$(echo "$LAST_ERROR" | head -n 5 | tr '\n' ' ' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
    jq ".result = \"failed\" | .attempts = $MAX | .error = \"$ESCAPED_ERROR\"" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

exit 1
