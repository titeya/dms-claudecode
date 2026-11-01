#!/usr/bin/env bash
# Tests for get-claude-usage script
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/get-claude-usage"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}
assert_match() {
    if echo "$1" | grep -qE "$2"; then pass "$3"; else fail "$3 (no match for '$2')"; fi
}

# --- Setup isolated environment ---
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

setup_env() {
    local name="$1"
    local dir="$TMPDIR_ROOT/$name"
    mkdir -p "$dir/.claude/projects/test-project"
    echo "$dir"
}

# Mock curl: returns empty JSON for everything except the usage endpoint
# (avoids real network calls). The usage endpoint honours:
#   MOCK_USAGE_BODY  response body            (default '{}')
#   MOCK_USAGE_CODE  HTTP status printed by -w (default 200)
#   MOCK_USAGE_FAIL  non-empty: exit 6 with no output, like a network failure
#   MOCK_CURL_LOG    file that gets one line per usage request
mock_curl="$TMPDIR_ROOT/curl"
cat > "$mock_curl" << 'CURLEOF'
#!/usr/bin/env bash
case "$*" in
    *api/oauth/usage*)
        [ -n "${MOCK_CURL_LOG:-}" ] && echo "usage" >> "$MOCK_CURL_LOG"
        [ -n "${MOCK_USAGE_FAIL:-}" ] && exit 6
        printf '%s\n%s' "${MOCK_USAGE_BODY:-{\}}" "${MOCK_USAGE_CODE:-200}"
        ;;
    *) echo '{}' ;;
esac
CURLEOF
chmod +x "$mock_curl"

run_script() {
    local home_dir="$1"
    shift
    # Override HOME and prepend mock curl to PATH; remaining args go to the script
    HOME="$home_dir" PATH="$TMPDIR_ROOT:$PATH" bash "$SCRIPT" "$@" 2>/dev/null
}

# Build a JSONL fixture line
# Usage: make_jsonl_line <date> <model> <input> <output> <cache_read> <cache_write> <sessionId>
make_jsonl_line() {
    local date="$1" model="$2" inp="$3" out="$4" cr="$5" cw="$6" sess="$7"
    printf '{"type":"assistant","timestamp":"%sT12:00:00Z","sessionId":"%s","message":{"model":"%s","usage":{"input_tokens":%d,"output_tokens":%d,"cache_read_input_tokens":%d,"cache_creation_input_tokens":%d}}}\n' \
        "$date" "$sess" "$model" "$inp" "$out" "$cr" "$cw"
}

# ============================================================
echo "=== Test 1: Output format — all 22 keys present ==="
# ============================================================
ENV1=$(setup_env "test1")
OUTPUT1=$(run_script "$ENV1")

EXPECTED_KEYS="SUBSCRIPTION_TYPE RATE_LIMIT_TIER FIVE_HOUR_UTIL FIVE_HOUR_RESET SEVEN_DAY_UTIL SEVEN_DAY_RESET EXTRA_USAGE_ENABLED AUTH_STATE WEEK_MESSAGES WEEK_SESSIONS WEEK_TOKENS WEEK_MODELS ALLTIME_SESSIONS ALLTIME_MESSAGES FIRST_SESSION DAILY MONTH_TOKENS TODAY_COST WEEK_COST MONTH_COST DAILY_COSTS USD_EUR_RATE"
for key in $EXPECTED_KEYS; do
    if echo "$OUTPUT1" | grep -q "^${key}="; then
        pass "key $key present"
    else
        fail "key $key missing"
    fi
done

# ============================================================
echo "=== Test 2: Token aggregation ==="
# ============================================================
ENV2=$(setup_env "test2")
TODAY=$(date +%Y-%m-%d)
DOW=$(date +%u)  # 1=Monday, 7=Sunday

# Pick a "second day" that's in the same calendar week as today
# If today is Monday (DOW=1), there's no earlier day this week, so use tomorrow (Tuesday)
if [ "$DOW" -eq 1 ]; then
    OTHER_DAY=$(date -d "1 day" +%Y-%m-%d)
    OTHER_IDX=1  # Tuesday = index 1
else
    OTHER_DAY=$(date -d "1 day ago" +%Y-%m-%d)
    OTHER_IDX=$((DOW - 2))  # Yesterday's index
fi
TODAY_IDX=$((DOW - 1))

# Create JSONL fixtures: 2 messages today (session A), 1 message on other day (session B)
{
    make_jsonl_line "$TODAY" "claude-opus-4-20250514" 100 200 50 30 "sess-a"
    make_jsonl_line "$TODAY" "claude-opus-4-20250514" 150 100 0 0 "sess-a"
    make_jsonl_line "$OTHER_DAY" "claude-sonnet-4-20250514" 80 60 20 10 "sess-b"
} > "$ENV2/.claude/projects/test-project/test.jsonl"

OUTPUT2=$(run_script "$ENV2")

# Total tokens: (100+200+50+30) + (150+100+0+0) + (80+60+20+10) = 380+250+170 = 800
WEEK_TOKENS=$(echo "$OUTPUT2" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS" "800" "WEEK_TOKENS=800"

# 3 messages total
WEEK_MESSAGES=$(echo "$OUTPUT2" | grep "^WEEK_MESSAGES=" | cut -d= -f2)
assert_eq "$WEEK_MESSAGES" "3" "WEEK_MESSAGES=3"

# 2 sessions
WEEK_SESSIONS=$(echo "$OUTPUT2" | grep "^WEEK_SESSIONS=" | cut -d= -f2)
assert_eq "$WEEK_SESSIONS" "2" "WEEK_SESSIONS=2"

# WEEK_MODELS should contain opus and sonnet
WEEK_MODELS=$(echo "$OUTPUT2" | grep "^WEEK_MODELS=" | cut -d= -f2-)
assert_match "$WEEK_MODELS" "opus" "WEEK_MODELS contains opus"
assert_match "$WEEK_MODELS" "sonnet" "WEEK_MODELS contains sonnet"

# DAILY: calendar week (Mon=index 0 ... Sun=index 6)
DAILY=$(echo "$OUTPUT2" | grep "^DAILY=" | cut -d= -f2)
DAILY_TODAY=$(echo "$DAILY" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")
DAILY_OTHER=$(echo "$DAILY" | tr ',' '\n' | sed -n "$((OTHER_IDX + 1))p")
assert_eq "$DAILY_TODAY" "630" "DAILY today=630"
assert_eq "$DAILY_OTHER" "170" "DAILY other day=170"

# ============================================================
echo "=== Test 3: Cost calculation ==="
# ============================================================
ENV3=$(setup_env "test3")

# Write a pricing cache with known prices
# opus: input=0.000015, output=0.000075, cache_read=0.0000015, cache_write=0.00001875
cat > "$ENV3/.claude/pricing-cache.json" << PRICEEOF
{
    "updated": "$(date +%Y-%m-%d)",
    "models": {
        "opus": {"input": 0.000015, "output": 0.000075, "cache_read": 0.0000015, "cache_write": 0.00001875}
    },
    "usd_eur_rate": 0.92
}
PRICEEOF

# One message today: 1000 input, 500 output, 200 cache_read, 100 cache_write
{
    make_jsonl_line "$TODAY" "claude-opus-4-20250514" 1000 500 200 100 "sess-c"
} > "$ENV3/.claude/projects/test-project/test.jsonl"

OUTPUT3=$(run_script "$ENV3")

# Expected cost: 1000*0.000015 + 500*0.000075 + 200*0.0000015 + 100*0.00001875
# = 0.015 + 0.0375 + 0.0003 + 0.001875 = 0.054675
TODAY_COST=$(echo "$OUTPUT3" | grep "^TODAY_COST=" | cut -d= -f2)
assert_eq "$TODAY_COST" "0.05" "TODAY_COST=0.05 (rounded)"

WEEK_COST=$(echo "$OUTPUT3" | grep "^WEEK_COST=" | cut -d= -f2)
assert_eq "$WEEK_COST" "0.05" "WEEK_COST matches TODAY_COST"

USD_EUR_RATE=$(echo "$OUTPUT3" | grep "^USD_EUR_RATE=" | cut -d= -f2)
assert_eq "$USD_EUR_RATE" "0.92" "USD_EUR_RATE from cache"

# ============================================================
echo "=== Test 4: Missing credentials — defaults ==="
# ============================================================
ENV4=$(setup_env "test4")
# No .credentials.json
OUTPUT4=$(run_script "$ENV4")

SUB_TYPE=$(echo "$OUTPUT4" | grep "^SUBSCRIPTION_TYPE=" | cut -d= -f2)
assert_eq "$SUB_TYPE" "unknown" "SUBSCRIPTION_TYPE=unknown without credentials"

FIVE_HOUR=$(echo "$OUTPUT4" | grep "^FIVE_HOUR_UTIL=" | cut -d= -f2)
assert_eq "$FIVE_HOUR" "0" "FIVE_HOUR_UTIL=0 without credentials"

EXTRA=$(echo "$OUTPUT4" | grep "^EXTRA_USAGE_ENABLED=" | cut -d= -f2)
assert_eq "$EXTRA" "false" "EXTRA_USAGE_ENABLED=false without credentials"

# ============================================================
echo "=== Test 5: Empty projects dir — all counters zero ==="
# ============================================================
ENV5=$(setup_env "test5")
# projects dir exists but has no JSONL files
OUTPUT5=$(run_script "$ENV5")

assert_eq "$(echo "$OUTPUT5" | grep "^WEEK_TOKENS=" | cut -d= -f2)" "0" "WEEK_TOKENS=0 empty"
assert_eq "$(echo "$OUTPUT5" | grep "^WEEK_MESSAGES=" | cut -d= -f2)" "0" "WEEK_MESSAGES=0 empty"
assert_eq "$(echo "$OUTPUT5" | grep "^WEEK_SESSIONS=" | cut -d= -f2)" "0" "WEEK_SESSIONS=0 empty"
assert_eq "$(echo "$OUTPUT5" | grep "^MONTH_TOKENS=" | cut -d= -f2)" "0" "MONTH_TOKENS=0 empty"
assert_eq "$(echo "$OUTPUT5" | grep "^DAILY=" | cut -d= -f2)" "0,0,0,0,0,0,0" "DAILY all zeros"

# ============================================================
echo "=== Test 6: EUR rate sanitisation ==="
# ============================================================
ENV6=$(setup_env "test6")

# Pricing cache with a non-numeric EUR rate — should be treated as 0
cat > "$ENV6/.claude/pricing-cache.json" << 'EUREOF'
{
    "updated": "2099-12-31",
    "models": {
        "opus": {"input": 0.000015, "output": 0.000075, "cache_read": 0.0000015, "cache_write": 0.00001875}
    },
    "usd_eur_rate": "not-a-number"
}
EUREOF

OUTPUT6=$(run_script "$ENV6")
# The script reads usd_eur_rate from JSON as-is via jq; the QML side validates.
# What matters is that it doesn't crash and still produces output.
if echo "$OUTPUT6" | grep -q "^USD_EUR_RATE="; then
    pass "Script runs with non-numeric EUR rate without crashing"
else
    fail "Script crashed or missing USD_EUR_RATE with non-numeric EUR rate"
fi

# ============================================================
echo "=== Test 7: Pricing validation — cache without opus family ==="
# ============================================================
ENV7=$(setup_env "test7")

# Pricing cache with only "haiku" — no opus family
cat > "$ENV7/.claude/pricing-cache.json" << 'PVEOF'
{
    "updated": "2099-12-31",
    "models": {
        "haiku": {"input": 0.0000008, "output": 0.000004, "cache_read": 0.00000008, "cache_write": 0.000001}
    }
}
PVEOF

# Message with an opus model — should not crash, cost should be 0 (no pricing match)
{
    make_jsonl_line "$TODAY" "claude-opus-4-20250514" 1000 500 0 0 "sess-d"
} > "$ENV7/.claude/projects/test-project/test.jsonl"

OUTPUT7=$(run_script "$ENV7")
TODAY_COST7=$(echo "$OUTPUT7" | grep "^TODAY_COST=" | cut -d= -f2)
assert_eq "$TODAY_COST7" "0.00" "Cost=0 when model family not in pricing cache"

# ============================================================
echo "=== Test 8: PROFILES field — default profile always present ==="
# ============================================================
ENV8=$(setup_env "test8")
OUTPUT8=$(run_script "$ENV8")

if echo "$OUTPUT8" | grep -q "^PROFILES="; then
    pass "PROFILES key present"
else
    fail "PROFILES key missing"
fi

PROFILES8=$(echo "$OUTPUT8" | grep "^PROFILES=" | cut -d= -f2)
assert_match "$PROFILES8" "default" "PROFILES contains default"

# ============================================================
echo "=== Test 9: PROFILES discovers CCS instances ==="
# ============================================================
ENV9=$(setup_env "test9")
mkdir -p "$ENV9/.ccs/instances/work/projects/proj1"
mkdir -p "$ENV9/.ccs/instances/home/projects/proj2"

make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 500 300 0 0 "sess-r" \
    > "$ENV9/.ccs/instances/work/projects/proj1/test.jsonl"

OUTPUT9=$(run_script "$ENV9")

PROFILES9=$(echo "$OUTPUT9" | grep "^PROFILES=" | cut -d= -f2)
assert_match "$PROFILES9" "default" "PROFILES contains default (test9)"
assert_match "$PROFILES9" "work" "PROFILES contains work"
assert_match "$PROFILES9" "home" "PROFILES contains home"

# ============================================================
echo "=== Test 10: PROFILE_WEEK_TOKENS format and values ==="
# ============================================================
ENV10=$(setup_env "test10")
mkdir -p "$ENV10/.ccs/instances/work/projects/proj1"

# default: 630 tokens (100+200+50+30+150+100)
make_jsonl_line "$TODAY" "claude-opus-4-20250514" 100 200 50 30 "sess-a" \
    > "$ENV10/.claude/projects/test-project/t.jsonl"
make_jsonl_line "$TODAY" "claude-opus-4-20250514" 150 100 0 0 "sess-a" \
    >> "$ENV10/.claude/projects/test-project/t.jsonl"

# work: 800 tokens (500+300)
make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 500 300 0 0 "sess-r" \
    > "$ENV10/.ccs/instances/work/projects/proj1/t.jsonl"

OUTPUT10=$(run_script "$ENV10")

PWT=$(echo "$OUTPUT10" | grep "^PROFILE_WEEK_TOKENS=" | cut -d= -f2)
if [ -n "$PWT" ]; then
    pass "PROFILE_WEEK_TOKENS present"
else
    fail "PROFILE_WEEK_TOKENS missing"
fi
assert_match "$PWT" "default:[0-9]+" "PROFILE_WEEK_TOKENS has default:N"
assert_match "$PWT" "work:800" "PROFILE_WEEK_TOKENS work:800"

# Aggregate WEEK_TOKENS must equal sum: 630+800=1430
AGG10=$(echo "$OUTPUT10" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$AGG10" "1430" "WEEK_TOKENS aggregate = 1430"

# ============================================================
echo "=== Test 11: PROFILE_DAILY pipe-separated, 7 values per profile ==="
# ============================================================
ENV11=$(setup_env "test11")
mkdir -p "$ENV11/.ccs/instances/work/projects/proj1"

make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 100 50 0 0 "s1" \
    > "$ENV11/.ccs/instances/work/projects/proj1/t.jsonl"

OUTPUT11=$(run_script "$ENV11")

PD=$(echo "$OUTPUT11" | grep "^PROFILE_DAILY=" | cut -d= -f2)
if [ -n "$PD" ]; then
    pass "PROFILE_DAILY present"
else
    fail "PROFILE_DAILY missing"
fi

# Verify pipe separator exists (at least 2 profiles = 1 pipe)
assert_match "$PD" "[|]" "PROFILE_DAILY has pipe separator"

# Each block should have 7 comma-separated values
# Check work block: split on | then check count of commas in work part
WORK_BLOCK=$(echo "$PD" | tr '|' '\n' | grep "^work:")
WORK_VALS=$(echo "$WORK_BLOCK" | cut -d: -f2)
COMMA_COUNT=$(echo "$WORK_VALS" | tr -cd ',' | wc -c)
assert_eq "$COMMA_COUNT" "6" "PROFILE_DAILY work block has 7 values (6 commas)"

# ============================================================
echo "=== Test 12: PROFILE_WEEK_MODELS uses = not : for model/count ==="
# ============================================================
ENV12=$(setup_env "test12")
mkdir -p "$ENV12/.ccs/instances/work/projects/proj1"

make_jsonl_line "$TODAY" "claude-opus-4-20250514" 100 50 0 0 "s1" \
    > "$ENV12/.ccs/instances/work/projects/proj1/t.jsonl"

OUTPUT12=$(run_script "$ENV12")

PWM=$(echo "$OUTPUT12" | grep "^PROFILE_WEEK_MODELS=" | cut -d= -f2-)
if [ -n "$PWM" ]; then
    pass "PROFILE_WEEK_MODELS present"
else
    fail "PROFILE_WEEK_MODELS missing"
fi
assert_match "$PWM" "opus=[0-9]+" "PROFILE_WEEK_MODELS uses = separator for model/count"

# Also verify the aggregate WEEK_MODELS field uses = (not :)
AGG_WM12=$(echo "$OUTPUT12" | sed -n 's/^WEEK_MODELS=//p')
assert_match "$AGG_WM12" "opus=[0-9]+" "aggregate WEEK_MODELS also uses = separator"

# ============================================================
echo "=== Test 13: Week boundary — previous week data excluded from WEEK_TOKENS ==="
# ============================================================
ENV13=$(setup_env "test13")

# Compute last Sunday (always before current week which starts Monday)
LAST_SUNDAY=$(date -d "last Sunday" +%Y-%m-%d)
# If today IS Sunday, "last Sunday" is today; go back 7 more days
if [ "$(date +%u)" -eq 7 ]; then
    LAST_SUNDAY=$(date -d "7 days ago" +%Y-%m-%d)
fi

{
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 100 100 0 0 "sess-w1"
    make_jsonl_line "$LAST_SUNDAY" "claude-sonnet-4-20250514" 500 500 0 0 "sess-w2"
} > "$ENV13/.claude/projects/test-project/test.jsonl"

OUTPUT13=$(run_script "$ENV13")
WEEK_TOKENS13=$(echo "$OUTPUT13" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS13" "200" "Previous week data excluded from WEEK_TOKENS"

# Previous week data should still count toward MONTH_TOKENS if same month
MONTH_TOKENS13=$(echo "$OUTPUT13" | grep "^MONTH_TOKENS=" | cut -d= -f2)
LAST_SUNDAY_MONTH=$(date -d "$LAST_SUNDAY" +%Y-%m)
CURRENT_MONTH=$(date +%Y-%m)
if [ "$LAST_SUNDAY_MONTH" = "$CURRENT_MONTH" ]; then
    assert_eq "$MONTH_TOKENS13" "1200" "Previous week same-month data included in MONTH_TOKENS"
else
    assert_eq "$MONTH_TOKENS13" "200" "Previous month data excluded from MONTH_TOKENS"
fi

# ============================================================
echo "=== Test 14: Month boundary — previous month data excluded ==="
# ============================================================
ENV14=$(setup_env "test14")

# Use a date from the previous month
PREV_MONTH_DATE=$(date -d "$(date +%Y-%m-01) - 1 day" +%Y-%m-%d)

{
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 100 100 0 0 "sess-m1"
    make_jsonl_line "$PREV_MONTH_DATE" "claude-sonnet-4-20250514" 400 400 0 0 "sess-m2"
} > "$ENV14/.claude/projects/test-project/test.jsonl"

OUTPUT14=$(run_script "$ENV14")
MONTH_TOKENS14=$(echo "$OUTPUT14" | grep "^MONTH_TOKENS=" | cut -d= -f2)
assert_eq "$MONTH_TOKENS14" "200" "Previous month data excluded from MONTH_TOKENS"

# ============================================================
echo "=== Test 15: Malformed JSONL lines are skipped ==="
# ============================================================
ENV15=$(setup_env "test15")

{
    echo "this is not json"
    echo ""
    echo '{"truncated": true'
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 100 100 0 0 "sess-mf"
    echo '{"type":"assistant","timestamp":"invalid"}'
} > "$ENV15/.claude/projects/test-project/test.jsonl"

OUTPUT15=$(run_script "$ENV15")
WEEK_TOKENS15=$(echo "$OUTPUT15" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS15" "200" "Malformed lines skipped, valid line counted"

# ============================================================
echo "=== Test 16: Non-assistant types excluded ==="
# ============================================================
ENV16=$(setup_env "test16")

{
    # User message — should be ignored
    printf '{"type":"user","timestamp":"%sT12:00:00Z","sessionId":"sess-u","message":{"model":"claude-sonnet-4-20250514","usage":{"input_tokens":999,"output_tokens":999,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$TODAY"
    # Tool message — should be ignored
    printf '{"type":"tool","timestamp":"%sT12:00:00Z","sessionId":"sess-t","message":{"model":"claude-sonnet-4-20250514","usage":{"input_tokens":888,"output_tokens":888,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$TODAY"
    # Valid assistant message
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 50 50 0 0 "sess-a"
} > "$ENV16/.claude/projects/test-project/test.jsonl"

OUTPUT16=$(run_script "$ENV16")
WEEK_TOKENS16=$(echo "$OUTPUT16" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS16" "100" "Only assistant messages counted"
WEEK_MESSAGES16=$(echo "$OUTPUT16" | grep "^WEEK_MESSAGES=" | cut -d= -f2)
assert_eq "$WEEK_MESSAGES16" "1" "Non-assistant messages excluded from count"

# ============================================================
echo "=== Test 17: Multiple projects aggregated ==="
# ============================================================
ENV17=$(setup_env "test17")
mkdir -p "$ENV17/.claude/projects/project-a"
mkdir -p "$ENV17/.claude/projects/project-b"

{
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 100 100 0 0 "sess-pa"
} > "$ENV17/.claude/projects/project-a/log.jsonl"
{
    make_jsonl_line "$TODAY" "claude-opus-4-20250514" 200 200 0 0 "sess-pb"
} > "$ENV17/.claude/projects/project-b/log.jsonl"

OUTPUT17=$(run_script "$ENV17")
WEEK_TOKENS17=$(echo "$OUTPUT17" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS17" "600" "Tokens from multiple projects aggregated"
WEEK_SESSIONS17=$(echo "$OUTPUT17" | grep "^WEEK_SESSIONS=" | cut -d= -f2)
assert_eq "$WEEK_SESSIONS17" "2" "Sessions from multiple projects counted"

# ============================================================
echo "=== Test 18: Usage API cache — fresh cache used ==="
# ============================================================
ENV18=$(setup_env "test18")

# Create credentials so the API path is entered
cat > "$ENV18/.claude/.credentials.json" << 'CREDEOF'
{
    "claudeAiOauth": {
        "subscriptionType": "pro",
        "rateLimitTier": "t1_pro",
        "accessToken": "fake-token"
    }
}
CREDEOF

# Create fresh usage cache (cached_at = now)
NOW_TS=$(date +%s)
cat > "$ENV18/.claude/usage-cache.json" << CACHEEOF
{
    "cached_at": $NOW_TS,
    "identity": "$ENV18/.claude/.credentials.json",
    "data": {
        "five_hour": {"utilization": 42, "resets_at": "2099-01-01T00:00:00Z"},
        "seven_day": {"utilization": 15, "resets_at": "2099-01-07T00:00:00Z"},
        "extra_usage": {"is_enabled": true}
    }
}
CACHEEOF

OUTPUT18=$(run_script "$ENV18")
FIVE18=$(echo "$OUTPUT18" | grep "^FIVE_HOUR_UTIL=" | cut -d= -f2)
assert_eq "$FIVE18" "42" "Fresh cache: FIVE_HOUR_UTIL from cache"
SEVEN18=$(echo "$OUTPUT18" | grep "^SEVEN_DAY_UTIL=" | cut -d= -f2)
assert_eq "$SEVEN18" "15" "Fresh cache: SEVEN_DAY_UTIL from cache"
EXTRA18=$(echo "$OUTPUT18" | grep "^EXTRA_USAGE_ENABLED=" | cut -d= -f2)
assert_eq "$EXTRA18" "true" "Fresh cache: EXTRA_USAGE_ENABLED from cache"

# A fresh cache created for another config directory must not leak usage data
sed "s|$ENV18/.claude/.credentials.json|$ENV18/old-profile/.credentials.json|" \
    "$ENV18/.claude/usage-cache.json" > "$ENV18/.claude/usage-cache-other.json"
mv "$ENV18/.claude/usage-cache-other.json" "$ENV18/.claude/usage-cache.json"
OUTPUT18B=$(run_script "$ENV18")
FIVE18B=$(echo "$OUTPUT18B" | grep "^FIVE_HOUR_UTIL=" | cut -d= -f2)
assert_eq "$FIVE18B" "0" "Fresh cache from another profile is ignored"

# ============================================================
echo "=== Test 19: Stats cache parsing ==="
# ============================================================
ENV19=$(setup_env "test19")

cat > "$ENV19/.claude/stats-cache.json" << 'STATSEOF'
{
    "totalSessions": 150,
    "totalMessages": 4200,
    "firstSessionDate": "2024-06-15T10:30:00Z"
}
STATSEOF

OUTPUT19=$(run_script "$ENV19")
AT_SESS19=$(echo "$OUTPUT19" | grep "^ALLTIME_SESSIONS=" | cut -d= -f2)
assert_eq "$AT_SESS19" "150" "Stats cache: ALLTIME_SESSIONS"
AT_MSGS19=$(echo "$OUTPUT19" | grep "^ALLTIME_MESSAGES=" | cut -d= -f2)
assert_eq "$AT_MSGS19" "4200" "Stats cache: ALLTIME_MESSAGES"
FIRST19=$(echo "$OUTPUT19" | grep "^FIRST_SESSION=" | cut -d= -f2)
assert_eq "$FIRST19" "2024-06-15" "Stats cache: ISO timestamp T-suffix stripped"

# ============================================================
echo "=== Test 20: Cost with multiple model families ==="
# ============================================================
ENV20=$(setup_env "test20")

cat > "$ENV20/.claude/pricing-cache.json" << MPEOF
{
    "updated": "$(date +%Y-%m-%d)",
    "models": {
        "opus": {"input": 0.000015, "output": 0.000075, "cache_read": 0, "cache_write": 0},
        "sonnet": {"input": 0.000003, "output": 0.000015, "cache_read": 0, "cache_write": 0}
    }
}
MPEOF

{
    make_jsonl_line "$TODAY" "claude-opus-4-20250514" 1000 1000 0 0 "sess-mp1"
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 1000 1000 0 0 "sess-mp2"
} > "$ENV20/.claude/projects/test-project/test.jsonl"

OUTPUT20=$(run_script "$ENV20")
# opus: 1000*0.000015 + 1000*0.000075 = 0.015 + 0.075 = 0.09
# sonnet: 1000*0.000003 + 1000*0.000015 = 0.003 + 0.015 = 0.018
# total: 0.108
TODAY_COST20=$(echo "$OUTPUT20" | grep "^TODAY_COST=" | cut -d= -f2)
assert_eq "$TODAY_COST20" "0.11" "Multi-model cost summed correctly"

# ============================================================
echo "=== Test 21: Pricing cache without EUR rate — USD_EUR_RATE=0 ==="
# ============================================================
ENV21=$(setup_env "test21")

cat > "$ENV21/.claude/pricing-cache.json" << 'NOEUREOF'
{
    "updated": "2099-12-31",
    "models": {
        "sonnet": {"input": 0.000003, "output": 0.000015, "cache_read": 0, "cache_write": 0}
    }
}
NOEUREOF

OUTPUT21=$(run_script "$ENV21")
EUR21=$(echo "$OUTPUT21" | grep "^USD_EUR_RATE=" | cut -d= -f2)
assert_eq "$EUR21" "0" "Missing usd_eur_rate defaults to 0"

# ============================================================
echo "=== Test 22: Session deduplication — same session counted once ==="
# ============================================================
ENV22=$(setup_env "test22")

{
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 10 10 0 0 "same-sess"
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 20 20 0 0 "same-sess"
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 30 30 0 0 "same-sess"
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 40 40 0 0 "other-sess"
} > "$ENV22/.claude/projects/test-project/test.jsonl"

OUTPUT22=$(run_script "$ENV22")
WEEK_SESSIONS22=$(echo "$OUTPUT22" | grep "^WEEK_SESSIONS=" | cut -d= -f2)
assert_eq "$WEEK_SESSIONS22" "2" "Same sessionId counted as 1 session"
WEEK_MESSAGES22=$(echo "$OUTPUT22" | grep "^WEEK_MESSAGES=" | cut -d= -f2)
assert_eq "$WEEK_MESSAGES22" "4" "All messages counted regardless of session"

# ============================================================
echo "=== Test 23: DAILY_COSTS aligns with DAILY indices ==="
# ============================================================
ENV23=$(setup_env "test23")

cat > "$ENV23/.claude/pricing-cache.json" << DCEOF
{
    "updated": "$(date +%Y-%m-%d)",
    "models": {
        "sonnet": {"input": 0.000003, "output": 0.000015, "cache_read": 0, "cache_write": 0}
    }
}
DCEOF

{
    make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 1000 1000 0 0 "sess-dc"
} > "$ENV23/.claude/projects/test-project/test.jsonl"

OUTPUT23=$(run_script "$ENV23")
DAILY23=$(echo "$OUTPUT23" | grep "^DAILY=" | cut -d= -f2)
DAILY_COSTS23=$(echo "$OUTPUT23" | grep "^DAILY_COSTS=" | cut -d= -f2)

# Today's index in calendar week
TODAY_IDX23=$((DOW - 1))

# Verify tokens and costs are at the same index
DAILY_TOK=$(echo "$DAILY23" | tr ',' '\n' | sed -n "$((TODAY_IDX23 + 1))p")
DAILY_CST=$(echo "$DAILY_COSTS23" | tr ',' '\n' | sed -n "$((TODAY_IDX23 + 1))p")
assert_eq "$DAILY_TOK" "2000" "DAILY tokens at today's index"
if [ "$DAILY_CST" != "0" ] && [ "$DAILY_CST" != "0.00" ]; then
    pass "DAILY_COSTS at today's index is non-zero"
else
    fail "DAILY_COSTS at today's index should be non-zero (got '$DAILY_CST')"
fi

# Verify all other indices are zero
for i in $(seq 0 6); do
    if [ "$i" -ne "$TODAY_IDX23" ]; then
        val=$(echo "$DAILY_COSTS23" | tr ',' '\n' | sed -n "$((i + 1))p")
        if [ "$val" = "0.00" ] || [ "$val" = "0" ]; then
            pass "DAILY_COSTS[$i] is zero (not today)"
        else
            fail "DAILY_COSTS[$i] should be zero, got '$val'"
        fi
    fi
done

# ============================================================
echo "=== Test 24: PROFILES discovers claude-code-profiles (ccp) ==="
# ============================================================
ENV24=$(setup_env "test24")
mkdir -p "$ENV24/.ccp/profiles"
mkdir -p "$ENV24/ccpdata/ranqia/projects/proj1"
echo "CLAUDE_CONFIG_DIR=$ENV24/ccpdata/ranqia" > "$ENV24/.ccp/profiles/ranqia.env"

make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 400 200 0 0 "sess-ccp" \
    > "$ENV24/ccpdata/ranqia/projects/proj1/t.jsonl"

OUTPUT24=$(run_script "$ENV24")
PROFILES24=$(echo "$OUTPUT24" | grep "^PROFILES=" | cut -d= -f2)
assert_match "$PROFILES24" "default" "PROFILES contains default (test24)"
assert_match "$PROFILES24" "ranqia" "PROFILES contains ccp profile"

# Tokens from the ccp profile are counted (400+200)
PWT24=$(echo "$OUTPUT24" | grep "^PROFILE_WEEK_TOKENS=" | cut -d= -f2)
RANQIA_TOK=$(echo "$PWT24" | tr ',' '\n' | grep "^ranqia:" | cut -d: -f2)
assert_eq "$RANQIA_TOK" "600" "ccp profile token count"

# Per-profile session/message counts are emitted
PWM24=$(echo "$OUTPUT24" | grep "^PROFILE_WEEK_MESSAGES=" | cut -d= -f2)
PWS24=$(echo "$OUTPUT24" | grep "^PROFILE_WEEK_SESSIONS=" | cut -d= -f2)
assert_eq "$(echo "$PWM24" | tr ',' '\n' | grep '^ranqia:' | cut -d: -f2)" "1" \
    "PROFILE_WEEK_MESSAGES per profile"
assert_eq "$(echo "$PWS24" | tr ',' '\n' | grep '^ranqia:' | cut -d: -f2)" "1" \
    "PROFILE_WEEK_SESSIONS per profile"

# ============================================================
echo "=== Test 25: ccp profile without CLAUDE_CONFIG_DIR is ignored ==="
# ============================================================
ENV25=$(setup_env "test25")
mkdir -p "$ENV25/.ccp/profiles"
printf '# Profile: broken\nANTHROPIC_BASE_URL=https://example.com\n' \
    > "$ENV25/.ccp/profiles/broken.env"

OUTPUT25=$(run_script "$ENV25")
PROFILES25=$(echo "$OUTPUT25" | grep "^PROFILES=" | cut -d= -f2)
assert_eq "$PROFILES25" "default" "ccp profile without CLAUDE_CONFIG_DIR is skipped"

# ============================================================
echo "=== Test 26: manual profiles passed as name=path arguments ==="
# ============================================================
ENV26=$(setup_env "test26")
mkdir -p "$ENV26/manual/work/projects/proj1"
make_jsonl_line "$TODAY" "claude-sonnet-4-20250514" 100 100 0 0 "sess-m" \
    > "$ENV26/manual/work/projects/proj1/t.jsonl"

OUTPUT26=$(run_script "$ENV26" "work=$ENV26/manual/work")
PROFILES26=$(echo "$OUTPUT26" | grep "^PROFILES=" | cut -d= -f2)
assert_match "$PROFILES26" "work" "manual profile appears in PROFILES"

# A manual path that has no projects/ dir is ignored
OUTPUT26B=$(run_script "$ENV26" "ghost=$ENV26/does-not-exist")
PROFILES26B=$(echo "$OUTPUT26B" | grep "^PROFILES=" | cut -d= -f2)
assert_eq "$PROFILES26B" "default" "manual profile with missing projects/ is skipped"

# Tilde in a manual path is expanded against HOME
OUTPUT26C=$(run_script "$ENV26" "tilde=~/manual/work")
PROFILES26C=$(echo "$OUTPUT26C" | grep "^PROFILES=" | cut -d= -f2)
assert_match "$PROFILES26C" "tilde" "manual profile path expands leading ~"

# ============================================================
echo "=== Test 27: duplicate profile names are registered once ==="
# ============================================================
ENV27=$(setup_env "test27")
mkdir -p "$ENV27/.ccs/instances/work/projects/proj1"
mkdir -p "$ENV27/other/projects/proj1"

# "work" is already discovered from CCS; the manual entry must not duplicate it
OUTPUT27=$(run_script "$ENV27" "work=$ENV27/other")
PROFILES27=$(echo "$OUTPUT27" | grep "^PROFILES=" | cut -d= -f2)
WORK_COUNT=$(echo "$PROFILES27" | tr ',' '\n' | grep -c '^work$')
assert_eq "$WORK_COUNT" "1" "duplicate profile name registered only once"

# Delimiter characters are stripped from profile names
OUTPUT27B=$(run_script "$ENV27" "a:b,c|d=$ENV27/other")
PROFILES27B=$(echo "$OUTPUT27B" | grep "^PROFILES=" | cut -d= -f2)
assert_match "$PROFILES27B" "abcd" "delimiters stripped from manual profile name"

# The same config directory under another name must not be counted twice
OUTPUT27C=$(run_script "$ENV27" "alias=$ENV27/.ccs/instances/work")
PROFILES27C=$(echo "$OUTPUT27C" | grep "^PROFILES=" | cut -d= -f2)
if echo "$PROFILES27C" | tr ',' '\n' | grep -q '^alias$'; then
    fail "duplicate config directory registered under another name"
else
    pass "duplicate config directory registered only once"
fi


# ============================================================
echo "=== Test 28: AUTH_STATE — live response is ok ==="
# ============================================================
VALID_BODY='{"five_hour":{"utilization":55,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"utilization":20,"resets_at":"2099-01-07T00:00:00Z"},"extra_usage":{"is_enabled":false}}'
make_creds() {
    # make_creds <env> [expiresAt-ms] [accessToken]
    local env="$1" exp="${2:-4102444800000}" tok="${3-fake-token}"
    cat > "$env/.claude/.credentials.json" << CREDEOF
{"claudeAiOauth":{"subscriptionType":"pro","rateLimitTier":"t1_pro","accessToken":"$tok","expiresAt":$exp}}
CREDEOF
}
auth_state_of() { echo "$1" | grep "^AUTH_STATE=" | cut -d= -f2; }

ENV28=$(setup_env "test28")
make_creds "$ENV28"
OUTPUT28=$(MOCK_USAGE_BODY="$VALID_BODY" run_script "$ENV28")
assert_eq "$(auth_state_of "$OUTPUT28")" "ok" "live response: AUTH_STATE=ok"
assert_eq "$(echo "$OUTPUT28" | grep "^FIVE_HOUR_UTIL=" | cut -d= -f2)" "55" "live response: usage still parsed"
assert_match "$OUTPUT28" "^PROFILE_AUTH_STATE=default:ok$" "live response: PROFILE_AUTH_STATE lists default:ok"

# ============================================================
echo "=== Test 29: AUTH_STATE — missing credentials ==="
# ============================================================
ENV29=$(setup_env "test29")
OUTPUT29=$(run_script "$ENV29")
assert_eq "$(auth_state_of "$OUTPUT29")" "missing" "no credentials file: AUTH_STATE=missing"

ENV29B=$(setup_env "test29b")
make_creds "$ENV29B" 4102444800000 ""
OUTPUT29B=$(run_script "$ENV29B")
assert_eq "$(auth_state_of "$OUTPUT29B")" "missing" "empty accessToken: AUTH_STATE=missing"

# ============================================================
echo "=== Test 30: AUTH_STATE — expired ==="
# ============================================================
ENV30=$(setup_env "test30")
make_creds "$ENV30"
for code in 401 403; do
    OUTPUT30=$(MOCK_USAGE_CODE="$code" run_script "$ENV30")
    assert_eq "$(auth_state_of "$OUTPUT30")" "expired" "HTTP $code: AUTH_STATE=expired"
done

ENV30B=$(setup_env "test30b")
make_creds "$ENV30B" 1000
OUTPUT30B=$(MOCK_USAGE_FAIL=1 run_script "$ENV30B")
assert_eq "$(auth_state_of "$OUTPUT30B")" "expired" "expiresAt in the past + failed call: AUTH_STATE=expired"

# ============================================================
echo "=== Test 31: AUTH_STATE — rate limited ==="
# ============================================================
ENV31=$(setup_env "test31")
make_creds "$ENV31"
OUTPUT31=$(MOCK_USAGE_CODE=429 run_script "$ENV31")
assert_eq "$(auth_state_of "$OUTPUT31")" "rate_limited" "HTTP 429: AUTH_STATE=rate_limited"

ENV31B=$(setup_env "test31b")
make_creds "$ENV31B" 1000
OUTPUT31B=$(MOCK_USAGE_CODE=429 run_script "$ENV31B")
assert_eq "$(auth_state_of "$OUTPUT31B")" "rate_limited" "HTTP 429 wins over a past expiresAt"

# ============================================================
echo "=== Test 32: AUTH_STATE — stale keeps cached values ==="
# ============================================================
ENV32=$(setup_env "test32")
make_creds "$ENV32"
OLD_TS=$(( $(date +%s) - 3600 ))
cat > "$ENV32/.claude/usage-cache.json" << CACHEEOF
{"cached_at": $OLD_TS, "identity": "$ENV32/.claude/.credentials.json", "data": $VALID_BODY}
CACHEEOF
OUTPUT32=$(MOCK_USAGE_CODE=500 run_script "$ENV32")
assert_eq "$(auth_state_of "$OUTPUT32")" "stale" "HTTP 500 with cache: AUTH_STATE=stale"
assert_eq "$(echo "$OUTPUT32" | grep "^FIVE_HOUR_UTIL=" | cut -d= -f2)" "55" "stale: cached FIVE_HOUR_UTIL still emitted"

OUTPUT32B=$(MOCK_USAGE_FAIL=1 run_script "$ENV32")
assert_eq "$(auth_state_of "$OUTPUT32B")" "stale" "network failure: AUTH_STATE=stale"

# A cache that belongs to another profile must not be used as the fallback
sed -i "s|$ENV32/.claude/.credentials.json|$ENV32/other/.credentials.json|" "$ENV32/.claude/usage-cache.json"
OUTPUT32C=$(MOCK_USAGE_CODE=500 run_script "$ENV32")
assert_eq "$(echo "$OUTPUT32C" | grep "^FIVE_HOUR_UTIL=" | cut -d= -f2)" "0" "stale: foreign cache not used as fallback"

# ============================================================
echo "=== Test 33: AUTH_STATE — fresh cache makes no request and is ok ==="
# ============================================================
ENV33=$(setup_env "test33")
make_creds "$ENV33" 1000
cat > "$ENV33/.claude/usage-cache.json" << CACHEEOF
{"cached_at": $(date +%s), "identity": "$ENV33/.claude/.credentials.json", "data": $VALID_BODY}
CACHEEOF
CURL_LOG33="$TMPDIR_ROOT/curl33.log"
: > "$CURL_LOG33"
OUTPUT33=$(MOCK_CURL_LOG="$CURL_LOG33" MOCK_USAGE_CODE=401 run_script "$ENV33")
assert_eq "$(auth_state_of "$OUTPUT33")" "ok" "fresh cache: AUTH_STATE=ok"
assert_eq "$(wc -l < "$CURL_LOG33")" "0" "fresh cache: no usage request made"

# ============================================================
echo "=== Test 34: PROFILE_AUTH_STATE — per profile, default drives AUTH_STATE ==="
# ============================================================
ENV34=$(setup_env "test34")
make_creds "$ENV34"
mkdir -p "$ENV34/.ccs/instances/work/projects/proj1"
OUTPUT34=$(MOCK_USAGE_BODY="$VALID_BODY" run_script "$ENV34")
assert_match "$OUTPUT34" "^PROFILE_AUTH_STATE=default:ok,work:missing$" "per-profile states: default ok, work missing"
assert_eq "$(auth_state_of "$OUTPUT34")" "ok" "AUTH_STATE mirrors the default profile"

# ============================================================
echo "=== Test 35: the access token never appears in output ==="
# ============================================================
ENV35=$(setup_env "test35")
make_creds "$ENV35" 4102444800000 "SECRET-TOKEN-VALUE"
for code in 200 401 429 500; do
    OUTPUT35=$(MOCK_USAGE_CODE="$code" run_script "$ENV35")
    if echo "$OUTPUT35" | grep -q "SECRET-TOKEN-VALUE"; then
        fail "token leaked in output (HTTP $code)"
    else
        pass "token absent from output (HTTP $code)"
    fi
done

# ============================================================
echo "=== Test 36: streamed messages are billed once across transcript files ==="
# ============================================================
usage_field() { echo "$1" | sed -n "s/^$2=//p"; }
make_identified_line() {
    make_jsonl_line "$1" "claude-opus-4" "$2" "$3" "$4" "$5" "$6" \
        | jq -c --arg mid "$7" --arg rid "$8" '.message.id = $mid | .requestId = $rid'
}
ENV36=$(setup_env "test36")
cp "$ENV6/.claude/pricing-cache.json" "$ENV36/.claude/pricing-cache.json"
{
    for out in 1 1 1 1 327; do
        make_identified_line "$TODAY" 2 "$out" 15030 8655 original msg-stream req-stream
    done
} > "$ENV36/.claude/projects/test-project/stream.jsonl"
# A resumed session copies the original message with its counters zeroed.
make_identified_line "$TODAY" 0 0 0 0 resumed msg-stream req-stream \
    > "$ENV36/.claude/projects/test-project/resumed.jsonl"
OUTPUT36=$(run_script "$ENV36")
assert_eq "$(usage_field "$OUTPUT36" WEEK_TOKENS)" "24014" "streamed input/cache count once and output reaches final value"
assert_eq "$(usage_field "$OUTPUT36" WEEK_MESSAGES)" "1" "one message despite streamed blocks and resumed copy"
assert_eq "$(usage_field "$OUTPUT36" WEEK_SESSIONS)" "1" "zeroed resume does not add a billed session"
assert_match "$(usage_field "$OUTPUT36" WEEK_MODELS)" "opus=24014" "model totals use deduplicated tokens"
assert_eq "$(usage_field "$OUTPUT36" TODAY_COST)" "0.21" "cost uses deduplicated counters"
assert_eq "$(usage_field "$OUTPUT36" DAILY | cut -d, -f$((TODAY_IDX + 1)))" "24014" "daily activity uses deduplicated tokens"

# Reverse row order: maxima must not depend on traversal or stream order.
{ make_identified_line "$TODAY" 0 0 0 0 resumed msg-stream req-stream
  make_identified_line "$TODAY" 2 327 15030 8655 original msg-stream req-stream
  make_identified_line "$TODAY" 2 1 15030 8655 original msg-stream req-stream
} > "$ENV36/.claude/projects/test-project/stream.jsonl"
rm "$ENV36/.claude/projects/test-project/resumed.jsonl"
OUTPUT36B=$(run_script "$ENV36")
assert_eq "$(usage_field "$OUTPUT36B" WEEK_TOKENS)" "24014" "zero-first and reversed stream retain all usage"
assert_eq "$(usage_field "$OUTPUT36B" WEEK_SESSIONS)" "1" "metadata comes from billed record"

# Nonzero copies across dates keep the earliest billed day. A zeroed copy
# in the current window must not move an old message into today's totals.
ENV37=$(setup_env "test37")
OLD_DATE=$(date -d "$(date +%Y-%m-01) - 7 days" +%Y-%m-%d)
make_identified_line "$OLD_DATE" 100 20 0 0 original msg-old req-old \
    > "$ENV37/.claude/projects/test-project/original.jsonl"
touch -d '90 days ago' "$ENV37/.claude/projects/test-project/original.jsonl"
{
    make_identified_line "$TODAY" 100 20 0 0 resumed msg-old req-old
    make_identified_line "$TODAY" 0 0 0 0 resumed msg-old req-old
} > "$ENV37/.claude/projects/test-project/resumed.jsonl"
OUTPUT37=$(run_script "$ENV37")
assert_eq "$(usage_field "$OUTPUT37" WEEK_TOKENS)" "0" "resumed message stays outside current week"
assert_eq "$(usage_field "$OUTPUT37" MONTH_TOKENS)" "0" "resumed message stays outside current month"
assert_eq "$(usage_field "$OUTPUT37" DAILY)" "0,0,0,0,0,0,0" "resumed message keeps original date"

# Same message id with different request ids represents distinct calls.
# Incomplete or absent identities must never collapse unrelated legacy rows.
ENV38=$(setup_env "test38")
{
    make_identified_line "$TODAY" 10 0 0 0 sess shared req-a
    make_identified_line "$TODAY" 20 0 0 0 sess shared req-b
    make_identified_line "$TODAY" 30 0 0 0 sess shared ''
    make_identified_line "$TODAY" 40 0 0 0 sess shared ''
    make_identified_line "$TODAY" 50 0 0 0 sess '' req-c
    make_identified_line "$TODAY" 60 0 0 0 sess '' req-c
    make_jsonl_line "$TODAY" claude-opus-4 70 0 0 0 sess
    make_jsonl_line "$TODAY" claude-opus-4 80 0 0 0 sess
} > "$ENV38/.claude/projects/test-project/test.jsonl"
OUTPUT38=$(run_script "$ENV38")
assert_eq "$(usage_field "$OUTPUT38" WEEK_TOKENS)" "360" "distinct requests and incomplete identities are counted independently"
assert_eq "$(usage_field "$OUTPUT38" WEEK_MESSAGES)" "8" "legacy rows do not collapse into one message"

# Every usage field takes its maximum; profiles keep separate billing identities.
ENV39=$(setup_env "test39")
{
    make_identified_line "$TODAY" 10 0 30 0 sess same same
    make_identified_line "$TODAY" 0 20 0 40 sess same same
} > "$ENV39/.claude/projects/test-project/test.jsonl"
mkdir -p "$ENV39/.ccs/instances/work/projects/p"
make_identified_line "$TODAY" 50 0 0 0 work same same \
    > "$ENV39/.ccs/instances/work/projects/p/test.jsonl"
OUTPUT39=$(run_script "$ENV39")
assert_eq "$(usage_field "$OUTPUT39" WEEK_TOKENS)" "150" "each field uses its maximum and separate profiles do not deduplicate each other"
assert_eq "$(usage_field "$OUTPUT39" WEEK_MESSAGES)" "2" "one deduplicated message per profile"
assert_match "$(usage_field "$OUTPUT39" PROFILE_WEEK_TOKENS)" "default:100,work:50" "profile totals stay independent"

# ============================================================
echo "=== Test 40: FIVE_HOUR_ENABLED — plans without a 5-hour limit ==="
# ============================================================
NO_FIVE_BODY='{"five_hour":null,"seven_day":{"utilization":7,"resets_at":"2099-01-07T00:00:00Z"},"extra_usage":{"is_enabled":false}}'
IDLE_FIVE_BODY='{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":7,"resets_at":"2099-01-07T00:00:00Z"}}'

ENV40=$(setup_env "test40")
make_creds "$ENV40"
cat > "$ENV40/.claude/usage-cache.json" << CACHEEOF
{"cached_at": $OLD_TS, "identity": "$ENV40/.claude/.credentials.json", "data": $VALID_BODY}
CACHEEOF
OUTPUT40=$(MOCK_USAGE_BODY="$NO_FIVE_BODY" run_script "$ENV40")
assert_eq "$(auth_state_of "$OUTPUT40")" "ok" "five_hour null: AUTH_STATE=ok, not stale"
assert_eq "$(usage_field "$OUTPUT40" SEVEN_DAY_UTIL)" "7" "five_hour null: live 7-day value replaces the old cache"
assert_eq "$(usage_field "$OUTPUT40" FIVE_HOUR_ENABLED)" "false" "five_hour null: FIVE_HOUR_ENABLED=false"
assert_eq "$(usage_field "$OUTPUT40" PROFILE_FIVE_HOUR_ENABLED)" "default:false" "five_hour null: per-profile value emitted"
assert_eq "$(jq -r '.data.seven_day.utilization' "$ENV40/.claude/usage-cache.json")" "7" "five_hour null: cache refreshed"

cat > "$ENV40/.claude/usage-cache.json" << CACHEEOF
{"cached_at": $OLD_TS, "identity": "$ENV40/.claude/.credentials.json", "data": $NO_FIVE_BODY}
CACHEEOF
OUTPUT40B=$(MOCK_USAGE_CODE=500 run_script "$ENV40")
assert_eq "$(auth_state_of "$OUTPUT40B")" "stale" "cached five_hour null + failed call: AUTH_STATE=stale"
assert_eq "$(usage_field "$OUTPUT40B" FIVE_HOUR_ENABLED)" "false" "cached five_hour null + failed call: stays false"

ENV40C=$(setup_env "test40c")
make_creds "$ENV40C"
OUTPUT40C=$(MOCK_USAGE_BODY="$IDLE_FIVE_BODY" run_script "$ENV40C")
assert_eq "$(usage_field "$OUTPUT40C" FIVE_HOUR_ENABLED)" "true" "idle window with no resets_at: FIVE_HOUR_ENABLED=true"

ENV40D=$(setup_env "test40d")
make_creds "$ENV40D"
OUTPUT40D=$(MOCK_USAGE_BODY="$VALID_BODY" run_script "$ENV40D")
assert_eq "$(usage_field "$OUTPUT40D" FIVE_HOUR_ENABLED)" "true" "populated window: FIVE_HOUR_ENABLED=true"

ENV40E=$(setup_env "test40e")
make_creds "$ENV40E"
OUTPUT40E=$(MOCK_USAGE_CODE=500 run_script "$ENV40E")
assert_eq "$(usage_field "$OUTPUT40E" FIVE_HOUR_ENABLED)" "true" "failed call with no cache: FIVE_HOUR_ENABLED stays true"

ENV40F=$(setup_env "test40f")
OUTPUT40F=$(run_script "$ENV40F")
assert_eq "$(usage_field "$OUTPUT40F" FIVE_HOUR_ENABLED)" "true" "no credentials: FIVE_HOUR_ENABLED stays true"

ENV40G=$(setup_env "test40g")
make_creds "$ENV40G"
cat > "$ENV40G/.claude/usage-cache.json" << CACHEEOF
{"cached_at": $(date +%s), "identity": "$ENV40G/.claude/.credentials.json", "data": "corrupt"}
CACHEEOF
OUTPUT40G=$(run_script "$ENV40G")
assert_eq "$(usage_field "$OUTPUT40G" FIVE_HOUR_ENABLED)" "true" "fetch died on a corrupt cache: FIVE_HOUR_ENABLED stays true"
assert_eq "$(usage_field "$OUTPUT40G" PROFILE_FIVE_HOUR_ENABLED)" "default:true" "fetch died on a corrupt cache: per-profile value stays true"

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
