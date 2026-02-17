#!/bin/bash
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# Quality Gate: Security Scan (Trivy wrapper)
# ═══════════════════════════════════════════════════════════════

echo "🔐 Running security scan..."

if command -v trivy &>/dev/null; then
    docker run --rm -v $(pwd):/app -w /app aquasec/trivy fs \
        --security-checks vuln,config \
        --exit-code 1 \
        --severity HIGH,CRITICAL \
        . || { echo "❌ Trivy found HIGH/CRITICAL vulnerabilities"; exit 1; }
    echo "✅ No critical vulnerabilities found"
    exit 0
else
    echo "⚠️  Trivy not installed. Skipping deep security scan."
    echo "   (Install: brew install trivy)"
    # Fallback basic checks
    if [ -f "go.sum" ]; then
        # Check for known bad deps (example)
        if grep -q "github.com/bad/lib" go.sum; then
            echo "❌ Forbidden dependency detected"
            exit 1
        fi
    fi
    exit 0
fi
