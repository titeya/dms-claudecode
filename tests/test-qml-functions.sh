#!/usr/bin/env bash
# Tests for QML widget JavaScript functions
# Extracts pure JS functions from ClaudeCodeUsageWidget.qml and tests them via Node.js
set -eu

# Check for Node.js
if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping QML function tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# Run a JS expression and capture stdout
run_js() {
    node -e "$1" 2>/dev/null
}

# Build JS test harness with functions extracted from the QML widget
JS_HARNESS='
// --- Functions extracted from ClaudeCodeUsageWidget.qml ---

function formatTokens(n) {
    if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(1) + "K"
    return Math.round(n).toString()
}

function shortModelName(name) {
    if (!name || name.length === 0) return name
    return name.charAt(0).toUpperCase() + name.slice(1)
}

function progressColor(pct) {
    if (pct > 80) return "error"
    if (pct > 50) return "warning"
    return "primary"
}

var testLang = "en"
var tierTranslations = {
    Free: { fr: "Gratuit", es: "Gratis" },
    Team: { fr: "Équipe", es: "Equipo" },
    Enterprise: { fr: "Entreprise", es: "Empresa" }
}

function tr(key) {
    return tierTranslations[key] && tierTranslations[key][testLang]
        ? tierTranslations[key][testLang]
        : key
}

function formatTier(tier) {
    if (!tier || tier === "unknown") return ""
    if (tier.indexOf("max_20x") >= 0) return tr("Max") + " 20x"
    if (tier.indexOf("max_5x") >= 0) return tr("Max") + " 5x"
    if (tier.indexOf("max") >= 0) return tr("Max")
    if (tier.indexOf("pro") >= 0) return tr("Pro")
    if (tier.indexOf("free") >= 0) return tr("Free")
    if (tier.indexOf("team") >= 0) return tr("Team")
    if (tier.indexOf("enterprise") >= 0) return tr("Enterprise")
    return tier.replace(/_/g, " ").replace(/\b\w/g, function (c) {
        return c.toUpperCase()
    })
}

function formatCost(usd, lang, usdEurRate) {
    var useEur = lang === "fr" && usdEurRate > 0
    var n = useEur ? usd * usdEurRate : usd
    var sym = useEur ? "" : "$"
    var suffix = useEur ? " €" : ""
    if (n >= 1000) return sym + (n / 1000).toFixed(1) + "K" + suffix
    if (n >= 100) return sym + Math.round(n) + suffix
    if (n >= 10) return sym + n.toFixed(1) + suffix
    return sym + n.toFixed(2) + suffix
}

function todayIndex() {
    var dow = new Date().getDay() // 0=Sunday, 6=Saturday
    return dow === 0 ? 6 : dow - 1
}

// parseLine: simulates the QML property-setting logic
function parseLine(line, state) {
    var idx = line.indexOf("=")
    if (idx < 0) return state
    var key = line.substring(0, idx)
    var val = line.substring(idx + 1)

    switch (key) {
    case "SUBSCRIPTION_TYPE": state.subscriptionType = val; break
    case "RATE_LIMIT_TIER": state.rateLimitTier = val; break
    case "FIVE_HOUR_UTIL": state.fiveHourUtil = parseFloat(val) || 0; break
    case "FIVE_HOUR_RESET": state.fiveHourReset = val; break
    case "SEVEN_DAY_UTIL": state.sevenDayUtil = parseFloat(val) || 0; break
    case "SEVEN_DAY_RESET": state.sevenDayReset = val; break
    case "EXTRA_USAGE_ENABLED": state.extraUsageEnabled = (val === "true"); break
    case "USAGE_AGE": state.usageAge = parseInt(val) || 0; break
    case "USAGE_ERROR": state.usageError = val; break
    case "WEEK_MESSAGES": state.weekMessages = parseInt(val) || 0; break
    case "WEEK_SESSIONS": state.weekSessions = parseInt(val) || 0; break
    case "WEEK_TOKENS": state.weekTokens = parseFloat(val) || 0; break
    case "MONTH_TOKENS": state.monthTokens = parseFloat(val) || 0; break
    case "ALLTIME_SESSIONS": state.alltimeSessions = parseInt(val) || 0; break
    case "ALLTIME_MESSAGES": state.alltimeMessages = parseInt(val) || 0; break
    case "FIRST_SESSION": state.firstSession = val; break
    case "WEEK_MODELS":
        state.models = []
        if (val.length > 0) {
            var pairs = val.split(",")
            for (var i = 0; i < pairs.length; i++) {
                var kv = pairs[i].split(":")
                if (kv.length === 2)
                    state.models.push({ modelName: kv[0], modelTokens: parseInt(kv[1]) || 0 })
            }
        }
        break
    case "DAILY":
        var parts = val.split(",")
        var arr = []
        for (var j = 0; j < 7; j++)
            arr.push(j < parts.length ? (parseFloat(parts[j]) || 0) : 0)
        state.dailyTokens = arr
        break
    case "TODAY_COST": state.todayCost = parseFloat(val) || 0; break
    case "WEEK_COST": state.weekCost = parseFloat(val) || 0; break
    case "MONTH_COST": state.monthCost = parseFloat(val) || 0; break
    case "USD_EUR_RATE": state.usdEurRate = parseFloat(val) || 0; break
    case "DAILY_COSTS":
        var cparts = val.split(",")
        var carr = []
        for (var k = 0; k < 7; k++)
            carr.push(k < cparts.length ? (parseFloat(cparts[k]) || 0) : 0)
        state.dailyCosts = carr
        break
    }
    return state
}

function formatAge(seconds) {
    if (!(seconds > 0)) return "0m"
    var mins = Math.floor(seconds / 60)
    if (mins < 60) return mins + "m"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + "h " + (mins % 60) + "m"
    return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
}

function usageErrorLabel(code) {
    switch (code) {
    case "token_expired": return tr("Claude Code login expired")
    case "rate_limited": return tr("API rate limited")
    case "unauthorized": return tr("Not authorized")
    case "offline": return tr("No connection")
    case "no_credentials": return tr("Not signed in")
    case "bad_response": return tr("Unexpected API response")
    default: return code
    }
}

function usageWarning(age, err) {
    if (!err) return ""
    var reason = usageErrorLabel(err)
    if (age <= 0) return reason
    return formatAge(age) + " " + tr("old") + " \u00b7 " + reason
}
'

# ============================================================
echo "=== Test 1: formatTokens ==="
# ============================================================

test_format_tokens() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(run_js "${JS_HARNESS} console.log(formatTokens($input))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_format_tokens 0 "0" "formatTokens(0) = 0"
test_format_tokens 1 "1" "formatTokens(1) = 1"
test_format_tokens 999 "999" "formatTokens(999) = 999"
test_format_tokens 1000 "1.0K" "formatTokens(1000) = 1.0K"
test_format_tokens 1500 "1.5K" "formatTokens(1500) = 1.5K"
test_format_tokens 999999 "1000.0K" "formatTokens(999999) = 1000.0K"
test_format_tokens 1000000 "1.0M" "formatTokens(1M) = 1.0M"
test_format_tokens 1500000 "1.5M" "formatTokens(1.5M) = 1.5M"
test_format_tokens 1000000000 "1.0B" "formatTokens(1B) = 1.0B"
test_format_tokens 2500000000 "2.5B" "formatTokens(2.5B) = 2.5B"

# ============================================================
echo "=== Test 2: shortModelName ==="
# ============================================================

test_short_model() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(run_js "${JS_HARNESS} console.log(shortModelName('$input'))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_short_model "opus" "Opus" "shortModelName(opus) = Opus"
test_short_model "sonnet" "Sonnet" "shortModelName(sonnet) = Sonnet"
test_short_model "haiku" "Haiku" "shortModelName(haiku) = Haiku"
test_short_model "a" "A" "shortModelName(a) = A"

# Empty/null cases
RESULT_EMPTY=$(run_js "${JS_HARNESS} console.log(shortModelName(''))")
if [ "$RESULT_EMPTY" = "" ]; then pass "shortModelName('') = empty"; else fail "shortModelName('') expected empty, got '$RESULT_EMPTY'"; fi

RESULT_NULL=$(run_js "${JS_HARNESS} console.log(shortModelName(null))")
if [ "$RESULT_NULL" = "null" ]; then pass "shortModelName(null) = null"; else fail "shortModelName(null) expected null, got '$RESULT_NULL'"; fi

# ============================================================
echo "=== Test 3: progressColor ==="
# ============================================================

test_progress_color() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(run_js "${JS_HARNESS} console.log(progressColor($input))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_progress_color 0 "primary" "progressColor(0) = primary"
test_progress_color 50 "primary" "progressColor(50) = primary"
test_progress_color 51 "warning" "progressColor(51) = warning"
test_progress_color 80 "warning" "progressColor(80) = warning"
test_progress_color 81 "error" "progressColor(81) = error"
test_progress_color 100 "error" "progressColor(100) = error"

# ============================================================
echo "=== Test 4: formatTier ==="
# ============================================================

test_format_tier() {
    local input="$1" lang="$2" expected="$3" label="$4"
    local result
    result=$(run_js "${JS_HARNESS} testLang='$lang'; console.log(formatTier('$input'))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_format_tier "t3_max_20x_something" "en" "Max 20x" "formatTier max_20x"
test_format_tier "t2_max_5x_something" "en" "Max 5x" "formatTier max_5x"
test_format_tier "t1_pro_something" "en" "Pro" "formatTier pro"
test_format_tier "free_tier" "fr" "Gratuit" "formatTier free in French"
test_format_tier "team_tier" "es" "Equipo" "formatTier team in Spanish"
test_format_tier "enterprise_tier" "fr" "Entreprise" "formatTier enterprise in French"
test_format_tier "unknown" "en" "" "formatTier hides unknown"
test_format_tier "custom_plan" "en" "Custom Plan" "formatTier formats unrecognised tiers"

# ============================================================
echo "=== Test 5: formatCost ==="
# ============================================================

test_format_cost() {
    local usd="$1" lang="$2" rate="$3" expected="$4" label="$5"
    local result
    result=$(run_js "${JS_HARNESS} console.log(formatCost($usd, '$lang', $rate))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

# USD mode (non-French locale)
test_format_cost 0 "en" 0 "\$0.00" "formatCost(0) USD = \$0.00"
test_format_cost 5.5 "en" 0 "\$5.50" "formatCost(5.5) USD = \$5.50"
test_format_cost 15.3 "en" 0 "\$15.3" "formatCost(15.3) USD = \$15.3"
test_format_cost 150 "en" 0 "\$150" "formatCost(150) USD = \$150"
test_format_cost 1500 "en" 0 "\$1.5K" "formatCost(1500) USD = \$1.5K"

# EUR mode (French locale with rate)
test_format_cost 10 "fr" 0.92 "9.20 €" "formatCost(10) EUR = 9.20 €"
test_format_cost 100 "fr" 0.92 "92.0 €" "formatCost(100) EUR = 92.0 € (92<100 → toFixed(1))"
test_format_cost 1500 "fr" 0.92 "1.4K €" "formatCost(1500) EUR = 1.4K €"

# French locale but rate=0 → falls back to USD
test_format_cost 5 "fr" 0 "\$5.00" "formatCost(5) FR no rate = USD fallback"

# ============================================================
echo "=== Test 6: todayIndex ==="
# ============================================================

# todayIndex should match: Monday=0, Tuesday=1, ..., Sunday=6
EXPECTED_INDEX=$(date +%u)  # 1=Monday, 7=Sunday
EXPECTED_INDEX=$((EXPECTED_INDEX - 1))  # 0=Monday, 6=Sunday
ACTUAL_INDEX=$(run_js "${JS_HARNESS} console.log(todayIndex())")

if [ "$ACTUAL_INDEX" = "$EXPECTED_INDEX" ]; then
    pass "todayIndex() = $EXPECTED_INDEX (matches today)"
else
    fail "todayIndex() expected $EXPECTED_INDEX, got $ACTUAL_INDEX"
fi

# Test specific days via mocking
test_today_index_mock() {
    local js_dow="$1" expected="$2" label="$3"
    local result
    result=$(run_js "
        var _getDay = Date.prototype.getDay;
        Date.prototype.getDay = function() { return $js_dow; };
        ${JS_HARNESS}
        console.log(todayIndex());
        Date.prototype.getDay = _getDay;
    ")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_today_index_mock 0 6 "todayIndex Sunday (getDay=0) → 6"
test_today_index_mock 1 0 "todayIndex Monday (getDay=1) → 0"
test_today_index_mock 2 1 "todayIndex Tuesday (getDay=2) → 1"
test_today_index_mock 3 2 "todayIndex Wednesday (getDay=3) → 2"
test_today_index_mock 4 3 "todayIndex Thursday (getDay=4) → 3"
test_today_index_mock 5 4 "todayIndex Friday (getDay=5) → 4"
test_today_index_mock 6 5 "todayIndex Saturday (getDay=6) → 5"

# ============================================================
echo "=== Test 7: parseLine ==="
# ============================================================

test_parse_line() {
    local input="$1" field="$2" expected="$3" label="$4"
    local result
    result=$(run_js "${JS_HARNESS}
        var s = {};
        parseLine('$input', s);
        console.log(typeof s.$field === 'undefined' ? 'UNDEFINED' : JSON.stringify(s.$field));
    ")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

# Basic key=value parsing
test_parse_line "SUBSCRIPTION_TYPE=pro" "subscriptionType" '"pro"' "parseLine SUBSCRIPTION_TYPE"
test_parse_line "FIVE_HOUR_UTIL=42.5" "fiveHourUtil" '42.5' "parseLine FIVE_HOUR_UTIL float"
test_parse_line "WEEK_MESSAGES=100" "weekMessages" '100' "parseLine WEEK_MESSAGES int"
test_parse_line "EXTRA_USAGE_ENABLED=true" "extraUsageEnabled" 'true' "parseLine EXTRA_USAGE bool true"
test_parse_line "EXTRA_USAGE_ENABLED=false" "extraUsageEnabled" 'false' "parseLine EXTRA_USAGE bool false"

# Empty values default to 0
test_parse_line "WEEK_TOKENS=" "weekTokens" '0' "parseLine empty value defaults to 0"
test_parse_line "FIVE_HOUR_UTIL=" "fiveHourUtil" '0' "parseLine empty float defaults to 0"

# No equals sign — ignored
RESULT_NOEQUALS=$(run_js "${JS_HARNESS}
    var s = { weekTokens: 99 };
    parseLine('GARBAGE', s);
    console.log(s.weekTokens);
")
if [ "$RESULT_NOEQUALS" = "99" ]; then
    pass "parseLine no equals sign is ignored"
else
    fail "parseLine no equals sign should be ignored (got weekTokens=$RESULT_NOEQUALS)"
fi

# DAILY with fewer than 7 values — padded with zeros
RESULT_SHORT=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('DAILY=100,200', s);
    console.log(JSON.stringify(s.dailyTokens));
")
if [ "$RESULT_SHORT" = "[100,200,0,0,0,0,0]" ]; then
    pass "parseLine DAILY short array padded to 7"
else
    fail "parseLine DAILY short array expected [100,200,0,0,0,0,0], got $RESULT_SHORT"
fi

# DAILY with 7 values
RESULT_FULL=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('DAILY=1,2,3,4,5,6,7', s);
    console.log(JSON.stringify(s.dailyTokens));
")
if [ "$RESULT_FULL" = "[1,2,3,4,5,6,7]" ]; then
    pass "parseLine DAILY full 7 values"
else
    fail "parseLine DAILY full expected [1,2,3,4,5,6,7], got $RESULT_FULL"
fi

# DAILY_COSTS with fewer than 7 values
RESULT_COSTS_SHORT=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('DAILY_COSTS=0.50,1.20', s);
    console.log(JSON.stringify(s.dailyCosts));
")
if [ "$RESULT_COSTS_SHORT" = "[0.5,1.2,0,0,0,0,0]" ]; then
    pass "parseLine DAILY_COSTS short array padded to 7"
else
    fail "parseLine DAILY_COSTS short expected [0.5,1.2,0,0,0,0,0], got $RESULT_COSTS_SHORT"
fi

# WEEK_MODELS with valid pairs
RESULT_MODELS=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('WEEK_MODELS=opus:5000,sonnet:3000', s);
    console.log(JSON.stringify(s.models));
")
if [ "$RESULT_MODELS" = '[{"modelName":"opus","modelTokens":5000},{"modelName":"sonnet","modelTokens":3000}]' ]; then
    pass "parseLine WEEK_MODELS valid pairs"
else
    fail "parseLine WEEK_MODELS expected [{opus,5000},{sonnet,3000}], got $RESULT_MODELS"
fi

# WEEK_MODELS empty value
RESULT_MODELS_EMPTY=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('WEEK_MODELS=', s);
    console.log(JSON.stringify(s.models));
")
if [ "$RESULT_MODELS_EMPTY" = "[]" ]; then
    pass "parseLine WEEK_MODELS empty = empty array"
else
    fail "parseLine WEEK_MODELS empty expected [], got $RESULT_MODELS_EMPTY"
fi

# WEEK_MODELS with malformed entry (no colon) — skipped
RESULT_MODELS_BAD=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('WEEK_MODELS=opus:5000,badentry,sonnet:3000', s);
    console.log(JSON.stringify(s.models));
")
if [ "$RESULT_MODELS_BAD" = '[{"modelName":"opus","modelTokens":5000},{"modelName":"sonnet","modelTokens":3000}]' ]; then
    pass "parseLine WEEK_MODELS malformed entry skipped"
else
    fail "parseLine WEEK_MODELS malformed expected opus+sonnet only, got $RESULT_MODELS_BAD"
fi

# ============================================================
echo "=== Test 8: formatAge / usageWarning ==="
# ============================================================

test_expr() {
    local expr="$1" expected="$2" desc="$3" out
    out=$(run_js "${JS_HARNESS} console.log($expr)")
    if [ "$out" = "$expected" ]; then
        pass "$desc"
    else
        fail "$desc expected '$expected', got '$out'"
    fi
}

test_expr "formatAge(0)" "0m" "formatAge(0) = 0m"
test_expr "formatAge(-5)" "0m" "formatAge(negative) = 0m"
test_expr "formatAge(59)" "0m" "formatAge(59s) = 0m"
test_expr "formatAge(60)" "1m" "formatAge(60s) = 1m"
test_expr "formatAge(3540)" "59m" "formatAge(59m) = 59m"
test_expr "formatAge(3600)" "1h 0m" "formatAge(1h) = 1h 0m"
test_expr "formatAge(12990)" "3h 36m" "formatAge(3h36m) = 3h 36m"
test_expr "formatAge(86400)" "1d 0h" "formatAge(1d) = 1d 0h"
test_expr "formatAge(187200)" "2d 4h" "formatAge(2d4h) = 2d 4h"

# A healthy fetch must produce no warning at all, whatever the age is
test_expr "JSON.stringify(usageWarning(0, ''))" '""' "usageWarning silent when no error"
test_expr "JSON.stringify(usageWarning(99999, ''))" '""' "usageWarning silent on age alone"

test_expr "usageWarning(12990, 'token_expired')" \
    "3h 36m old · Claude Code login expired" "usageWarning stale token"
test_expr "usageWarning(0, 'no_credentials')" \
    "Not signed in" "usageWarning drops age when there is no cached data"
test_expr "usageWarning(120, 'offline')" \
    "2m old · No connection" "usageWarning offline"
test_expr "usageWarning(60, 'http_500')" \
    "1m old · http_500" "usageWarning passes unknown codes through"

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
