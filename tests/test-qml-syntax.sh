#!/usr/bin/env bash
# Tests for QML file syntax validation
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

QML_FILES=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.qml" -type f)

echo "=== Test 1: QML files exist and are not empty ==="
if [ -z "$QML_FILES" ]; then
    fail "No .qml files found"
else
    for f in $QML_FILES; do
        name=$(basename "$f")
        if [ -s "$f" ]; then
            pass "$name exists and is not empty"
        else
            fail "$name is empty"
        fi
    done
fi

echo "=== Test 2: Required imports ==="
for f in $QML_FILES; do
    name=$(basename "$f")
    if grep -q "^import QtQuick" "$f"; then
        pass "$name imports QtQuick"
    else
        fail "$name missing 'import QtQuick'"
    fi
done

echo "=== Test 3: No hardcoded millisecond date arithmetic ==="
for f in $QML_FILES; do
    name=$(basename "$f")
    # 86400000 in date offset arithmetic (e.g. "new Date() - 86400000") is fragile.
    # Using it for duration formatting (remaining / 86400000) is acceptable.
    if grep "86400000" "$f" | grep -qvE '(remaining|elapsed|duration|diff)'; then
        fail "$name uses 86400000 outside duration formatting"
    else
        pass "$name no problematic 86400000 usage"
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
