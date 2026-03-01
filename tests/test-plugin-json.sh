#!/usr/bin/env bash
# Tests for plugin.json validation
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_JSON="$SCRIPT_DIR/plugin.json"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Test 1: JSON is valid ==="
if jq empty "$PLUGIN_JSON" 2>/dev/null; then
    pass "plugin.json is valid JSON"
else
    fail "plugin.json is not valid JSON"
fi

echo "=== Test 2: Required fields present ==="
for field in id name version type component; do
    val=$(jq -r ".$field // empty" "$PLUGIN_JSON")
    if [ -n "$val" ]; then
        pass "field '$field' present ($val)"
    else
        fail "field '$field' missing or empty"
    fi
done

echo "=== Test 3: Requires contains jq and curl ==="
REQUIRES=$(jq -r '.requires[]' "$PLUGIN_JSON" 2>/dev/null)
for dep in jq curl; do
    if echo "$REQUIRES" | grep -qx "$dep"; then
        pass "requires contains '$dep'"
    else
        fail "requires missing '$dep'"
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
