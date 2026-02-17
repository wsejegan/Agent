#!/bin/bash
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# HiveAgent v5.0 — Oracle Verification Engine
# Reads .hiveagent.yml for commands, falls back to auto-detection
# ═══════════════════════════════════════════════════════════════

MANIFEST=".hiveagent.yml"
echo "🔮 ORACLE: Analyzing $(pwd)..."

# ── Strategy 1: Manifest-Driven ────────────────────────────────
if [ -f "$MANIFEST" ]; then
    echo "📋 Using manifest-defined commands"

    # Type Check (optional)
    TYPE_CMD=$(yq '.type_check_command // ""' "$MANIFEST")
    if [ -n "$TYPE_CMD" ]; then
        echo "🔷 TYPE CHECK: $TYPE_CMD"
        eval "$TYPE_CMD" || { echo "❌ Type check failed"; exit 1; }
        echo "   ✓ Type check passed"
    fi

    # Lint (optional)
    LINT_CMD=$(yq '.lint_command // ""' "$MANIFEST")
    if [ -n "$LINT_CMD" ]; then
        echo "🔍 LINT: $LINT_CMD"
        eval "$LINT_CMD" || { echo "❌ Lint failed"; exit 1; }
        echo "   ✓ Lint passed"
    fi

    # Test (required)
    TEST_CMD=$(yq '.test_command // ""' "$MANIFEST")
    if [ -n "$TEST_CMD" ]; then
        echo "🧪 TEST: $TEST_CMD"
        eval "$TEST_CMD" || { echo "❌ Tests failed"; exit 1; }
        echo "   ✓ Tests passed"
    else
        echo "⚠️  No test_command in manifest. Skipping tests."
    fi

    echo "✨ ALL SYSTEMS GREEN (manifest-driven)."
    exit 0
fi

# ── Strategy 2: Auto-Detection (Fallback) ──────────────────────
echo "⚙️  No manifest found. Auto-detecting environment..."

if [ -f "angular.json" ]; then
    echo "🅰️  ANGULAR detected"
    if grep -q '"lint"' package.json 2>/dev/null; then
        npx ng lint --silent || { echo "❌ Lint failed"; exit 1; }
    fi
    npx ng test --watch=false --browsers=ChromeHeadless || { echo "❌ Tests failed"; exit 1; }
    npx ng build --configuration=production || { echo "❌ Build failed"; exit 1; }

elif [ -f "package.json" ] && grep -q '"react"' package.json 2>/dev/null; then
    echo "⚛️  REACT detected"
    if grep -q '"lint"' package.json; then
        npm run lint --silent || { echo "❌ Lint failed"; exit 1; }
    fi
    if grep -q '"test"' package.json; then
        CI=true npm test || { echo "❌ Tests failed"; exit 1; }
    fi
    npm run build || { echo "❌ Build failed"; exit 1; }

elif [ -f "package.json" ]; then
    echo "📦 NODE.JS detected"
    if grep -q '"lint"' package.json; then
        npm run lint --silent || { echo "❌ Lint failed"; exit 1; }
    fi
    npm test || { echo "❌ Tests failed"; exit 1; }

elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    echo "🐍 PYTHON detected"
    flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics 2>/dev/null || true
    pytest || { echo "❌ Tests failed"; exit 1; }

elif [ -f "go.mod" ]; then
    echo "🐹 GO detected"
    go vet ./... || { echo "❌ Vet failed"; exit 1; }
    go test ./... || { echo "❌ Tests failed"; exit 1; }

elif [ -f "pom.xml" ]; then
    echo "☕ JAVA (Maven) detected"
    mvn verify -q || { echo "❌ Maven verify failed"; exit 1; }

elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "☕ JAVA (Gradle) detected"
    ./gradlew test || { echo "❌ Gradle tests failed"; exit 1; }

elif ls *.csproj 1>/dev/null 2>&1 || ls *.sln 1>/dev/null 2>&1; then
    # Distinguish .NET Core vs .NET Framework
    if grep -rq 'net6\|net7\|net8\|netcoreapp\|Microsoft.NET.Sdk' *.csproj 2>/dev/null; then
        echo "🔷 .NET CORE detected"
        dotnet build --warnaserror || { echo "❌ Build failed"; exit 1; }
        dotnet test || { echo "❌ Tests failed"; exit 1; }
    elif grep -rq 'net4\|v4.' *.csproj 2>/dev/null; then
        echo "🔶 .NET FRAMEWORK detected"
        # .NET Framework uses MSBuild (Windows) or Mono (Linux)
        if command -v msbuild &>/dev/null; then
            msbuild /t:Build /p:Configuration=Release || { echo "❌ MSBuild failed"; exit 1; }
        elif command -v dotnet &>/dev/null; then
            dotnet build || { echo "❌ Build failed"; exit 1; }
        fi
        # Test with VSTest or NUnit
        if command -v vstest.console.exe &>/dev/null; then
            vstest.console.exe $(find . -name '*Tests.dll' -path '*/bin/*' | head -5) || { echo "❌ Tests failed"; exit 1; }
        elif command -v dotnet &>/dev/null; then
            dotnet test || { echo "❌ Tests failed"; exit 1; }
        fi
    else
        echo "🔷 .NET detected (version unknown, defaulting to dotnet CLI)"
        dotnet build --warnaserror || { echo "❌ Build failed"; exit 1; }
        dotnet test || { echo "❌ Tests failed"; exit 1; }
    fi

elif [ -f "Cargo.toml" ]; then
    echo "🦀 RUST detected"
    cargo test || { echo "❌ Tests failed"; exit 1; }

else
    echo "⚠️  UNKNOWN ENVIRONMENT. No tests to run."
    echo "   Performing basic git diff sanity check..."
    CHANGED=$(git diff --name-only 2>/dev/null | wc -l)
    echo "   Files changed: $CHANGED"
    exit 0
fi

echo "✨ ALL SYSTEMS GREEN (auto-detected)."
exit 0
