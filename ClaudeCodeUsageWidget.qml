import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginComponent {
    id: root

    // i18n
    property string lang: (SessionData.locale || Qt.locale().name).split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

    // Calendar week labels: Monday to Sunday (fixed order)
    property int refreshEpoch: 0
    readonly property var dayLabelsByLanguage: ({
        en: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"],
        fr: ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"],
        es: ["Lu", "Ma", "Mi", "Ju", "Vi", "Sá", "Do"]
    })
    property var dayLabels: dayLabelsByLanguage[lang] || dayLabelsByLanguage.en

    // Settings
    property int refreshInterval: (pluginData.refreshInterval || 2) * 60000
    property bool showPacing: pluginData.showPacing !== false
    property var customProfiles: pluginData.customProfiles || []
    // A refresh asked for while one is already in flight. onExited starts it,
    // so the request is queued rather than dropped.
    property bool rerunPending: false
    // Passed to the script as `--force`: manual refresh ignores the usage cache.
    property bool forceFetch: false
    // True while the run currently executing is one the user asked for. Read at
    // exit to decide whether anybody is waiting for a verdict.
    property bool forcedRunInFlight: false
    // "ok" | "fail" | "" - the outcome of the last manual refresh, shown on the
    // button for a few seconds.
    property string refreshResult: ""
    // Drives the spinner on the popout refresh button.
    readonly property bool refreshing: usageProcess.running

    // API usage data
    property string subscriptionType: ""
    property string rateLimitTier: ""
    property real fiveHourUtil: 0
    property string fiveHourReset: ""
    property real sevenDayUtil: 0
    property string sevenDayReset: ""
    property bool extraUsageEnabled: false
    // How much the rate limit numbers above can be trusted. usageError is empty
    // when the last fetch succeeded; otherwise usageAge is how old the numbers
    // being shown are, in seconds (0 = there is no data at all).
    property int usageAge: 0
    property string usageError: ""
    // Per-model weekly limits, the rows claude.ai shows under the all-models
    // one: [{ name, percent }]. Empty when the plan has no scoped model.
    property var weeklyScoped: []
    // First day (YYYY-MM-DD, local) of the window the week totals below cover.
    // It is the rate limit week, which does not start on Monday, so the totals
    // sit next to the 7-day ring measuring the same days.
    property string weekWindowStart: ""

    // Weekly state
    property int weekMessages: 0
    property int weekSessions: 0
    property real weekTokens: 0

    // Monthly state
    property real monthTokens: 0

    // All-time state
    property int alltimeSessions: 0
    property int alltimeMessages: 0
    property string firstSession: ""

    // Daily breakdown (rolling 7 days, computed from JSONL files)
    property var dailyTokens: [0, 0, 0, 0, 0, 0, 0]

    // Estimated API cost (in USD)
    property real todayCost: 0
    property real weekCost: 0
    property real monthCost: 0
    property var dailyCosts: [0, 0, 0, 0, 0, 0, 0]
    property real usdEurRate: 0

    // Chart hover state
    property int hoveredDay: -1

    // Model list
    ListModel {
        id: modelListData
    }

    // Profile selector state
    property string selectedProfile: "all"
    property var profileData: ({})
    // Shape per profile: { weekTokens, monthTokens, todayCost, weekCost, monthCost,
    //   daily:[7], dailyCosts:[7], weekModels:[{modelName,modelTokens}],
    //   fiveHourUtil, sevenDayUtil, fiveHourReset, sevenDayReset }

    ListModel {
        id: profileListModel
    }
    // First entry is always { name: "all" }; populated by PROFILES output field.

    // currentPd is a single reactive snapshot of the selected profile's data object.
    // Re-evaluated whenever selectedProfile or profileData changes.
    // All display* properties derive from this — ensures consistent re-evaluation.
    property var currentPd: {
        void (selectedProfile);
        void (profileData);
        if (selectedProfile === "all")
            return null;
        return profileData[selectedProfile] || null;
    }

    // Computed display values — switch between aggregate and per-profile data.
    property string displaySubscriptionType: currentPd && currentPd.subscriptionType ? currentPd.subscriptionType : subscriptionType
    property string displayRateLimitTier: currentPd && currentPd.rateLimitTier ? currentPd.rateLimitTier : rateLimitTier
    property real displayFiveHourUtil: currentPd && currentPd.fiveHourUtil !== undefined ? currentPd.fiveHourUtil : fiveHourUtil
    property string displayFiveHourReset: currentPd && currentPd.fiveHourReset !== undefined ? currentPd.fiveHourReset : fiveHourReset
    property real displaySevenDayUtil: currentPd && currentPd.sevenDayUtil !== undefined ? currentPd.sevenDayUtil : sevenDayUtil
    property string displaySevenDayReset: currentPd && currentPd.sevenDayReset !== undefined ? currentPd.sevenDayReset : sevenDayReset
    property int displayUsageAge: currentPd && currentPd.usageAge !== undefined ? currentPd.usageAge : usageAge
    property string displayUsageError: currentPd && currentPd.usageError !== undefined ? currentPd.usageError : usageError
    property var displayWeeklyScoped: currentPd && currentPd.weeklyScoped !== undefined ? currentPd.weeklyScoped : weeklyScoped
    property string displayWeekWindowStart: currentPd && currentPd.weekWindowStart !== undefined ? currentPd.weekWindowStart : weekWindowStart
    // "Since Aug 6" - which days the week totals in this card cover. Empty until
    // a window is known, so nothing is claimed before the first fetch lands.
    property string weekWindowLabel: {
        if (!displayWeekWindowStart)
            return "";
        var d = new Date(displayWeekWindowStart + "T00:00:00");
        if (isNaN(d.getTime()))
            return "";
        return tr("Since") + " " + Qt.formatDate(d, "MMM d");
    }

    // One line telling the user the rate limit numbers are not live, and why.
    // Empty while the fetch is healthy, which is the normal case.
    property string usageWarning: {
        if (!displayUsageError)
            return "";
        var reason = usageErrorLabel(displayUsageError);
        if (displayUsageAge <= 0)
            return reason;
        return formatAge(displayUsageAge) + " " + tr("old") + " · " + reason;
    }
    // Suffix for every rate limit percentage that came from a failed fetch, so a
    // number is never presented as live. The reason itself is printed once, in
    // the 5h card, rather than repeated under each ring.
    property string staleMark: usageWarning === "" ? "" : "?"
    property real displayWeekTokens: currentPd && currentPd.weekTokens !== undefined ? currentPd.weekTokens : weekTokens
    property int displayWeekMessages: currentPd && currentPd.weekMessages !== undefined ? currentPd.weekMessages : weekMessages
    property int displayWeekSessions: currentPd && currentPd.weekSessions !== undefined ? currentPd.weekSessions : weekSessions
    property real displayMonthTokens: currentPd && currentPd.monthTokens !== undefined ? currentPd.monthTokens : monthTokens
    property real displayTodayCost: currentPd && currentPd.todayCost !== undefined ? currentPd.todayCost : todayCost
    property real displayWeekCost: currentPd && currentPd.weekCost !== undefined ? currentPd.weekCost : weekCost
    property real displayMonthCost: currentPd && currentPd.monthCost !== undefined ? currentPd.monthCost : monthCost
    property var displayDailyTokens: currentPd && currentPd.daily ? currentPd.daily : dailyTokens

    // Per-profile daily tokens for chart overlay. Empty array when "all" selected.
    property var profileDailyTokens: currentPd && currentPd.daily ? currentPd.daily : []

    // Note: displayDailyCosts is intentionally NOT defined.
    // The tooltip cost line always shows aggregate dailyCosts per spec.
    // The Token Consumption card uses displayTodayCost/displayWeekCost/displayMonthCost instead.

    property string displayFiveHourCountdown: {
        if (!displayFiveHourReset)
            return "";
        var resetMs = new Date(displayFiveHourReset).getTime();
        var remaining = Math.max(0, resetMs - countdownNow);
        if (remaining <= 0)
            return tr("Resetting...");
        var hours = Math.floor(remaining / 3600000);
        var mins = Math.floor((remaining % 3600000) / 60000);
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m";
    }

    property string displaySevenDayCountdown: {
        if (!displaySevenDayReset)
            return "";
        var resetMs = new Date(displaySevenDayReset).getTime();
        var remaining = Math.max(0, resetMs - countdownNow);
        if (remaining <= 0)
            return tr("Resetting...");
        var days = Math.floor(remaining / 86400000);
        var hours = Math.floor((remaining % 86400000) / 3600000);
        var mins = Math.floor((remaining % 3600000) / 60000);
        if (days > 0)
            return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m";
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m";
    }

    // Pacing: whether usage is ahead of (over) or behind (under) a linear burn
    // rate for the time window. Each touches countdownNow so it recomputes on
    // the 60s timer below.
    property var fiveHourPace: {
        void (countdownNow);
        return paceInfo(displayFiveHourUtil, displayFiveHourReset, 18000000);
    }
    property var sevenDayPace: {
        void (countdownNow);
        return paceInfo(displaySevenDayUtil, displaySevenDayReset, 604800000);
    }
    // Pills are not profile-scoped — derive from aggregate 5h values.
    property var pillFivePace: {
        void (countdownNow);
        return paceInfo(fiveHourUtil, fiveHourReset, 18000000);
    }
    // Whether the taskbar pill should show the over-pace arrow/color. Shared by
    // the horizontal and vertical pills so they never diverge.
    readonly property bool pillOverPace: showPacing && (pillFivePace.status === "over" || pillFivePace.status === "over_quota")

    // Today's index in the calendar week (0=Monday, 6=Sunday)
    property int todayIndex: {
        void (countdownNow);
        var dow = new Date().getDay(); // 0=Sunday, 6=Saturday
        return dow === 0 ? 6 : dow - 1;
    }

    // Derived
    property real maxDaily: Math.max.apply(null, dailyTokens) || 1
    property bool isLoading: true

    // Live countdown
    property real countdownNow: Date.now()

    property string fiveHourCountdown: {
        if (!fiveHourReset)
            return "";
        var resetMs = new Date(fiveHourReset).getTime();
        var remaining = Math.max(0, resetMs - countdownNow);
        if (remaining <= 0)
            return tr("Resetting...");
        var hours = Math.floor(remaining / 3600000);
        var mins = Math.floor((remaining % 3600000) / 60000);
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m";
    }

    property string sevenDayCountdown: {
        if (!sevenDayReset)
            return "";
        var resetMs = new Date(sevenDayReset).getTime();
        var remaining = Math.max(0, resetMs - countdownNow);
        if (remaining <= 0)
            return tr("Resetting...");
        var days = Math.floor(remaining / 86400000);
        var hours = Math.floor((remaining % 86400000) / 3600000);
        var mins = Math.floor((remaining % 3600000) / 60000);
        if (days > 0)
            return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m";
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m";
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now();
            var elapsed = now - root.countdownNow;
            root.countdownNow = now;
            // Large gap (>2min) indicates wake from sleep — force immediate refresh
            if (elapsed > 120000 && !usageProcess.running) {
                usageProcess.running = true;
            }
        }
    }

    // Script path via PluginService
    property string scriptPath: PluginService.pluginDirectory + "/claudeCodeUsage/get-claude-usage"

    popoutWidth: 380
    popoutHeight: 740

    // --- Helpers ---

    function formatTokens(n) {
        if (n >= 1000000000)
            return (n / 1000000000).toFixed(1) + "B";
        if (n >= 1000000)
            return (n / 1000000).toFixed(1) + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(1) + "K";
        return Math.round(n).toString();
    }

    // Seconds → "45m" / "3h 37m" / "2d 4h". Used for how old stale numbers are.
    function formatAge(seconds) {
        if (!(seconds > 0))
            return "0m";
        var mins = Math.floor(seconds / 60);
        if (mins < 60)
            return mins + "m";
        var hours = Math.floor(mins / 60);
        if (hours < 24)
            return hours + "h " + (mins % 60) + "m";
        return Math.floor(hours / 24) + "d " + (hours % 24) + "h";
    }

    function usageErrorLabel(code) {
        switch (code) {
        case "token_expired":
            // The script renews the access token itself, so this only appears
            // when the refresh token is dead too - and then a `claude` run is
            // genuinely the only fix. Names it instead of just the fault.
            return tr("Claude Code login expired - run claude once");
        case "rate_limited":
            return tr("API rate limited");
        case "unauthorized":
            return tr("Not authorized");
        case "offline":
            return tr("No connection");
        case "no_credentials":
            return tr("Not signed in");
        case "bad_response":
            return tr("Unexpected API response");
        default:
            return code;
        }
    }

    function shortModelName(name) {
        if (!name || name.length === 0)
            return name;
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function progressColor(pct) {
        if (pct > 80)
            return Theme.error;
        if (pct > 50)
            return Theme.warning;
        return Theme.primary;
    }

    // Returns { timeFrac, delta, status } for a usage window.
    // status: over_quota | over | under | on | unknown
    function paceInfo(util, resetIso, windowMs) {
        util = util || 0;
        if (!resetIso)
            return util >= 100 ? {
                timeFrac: 1,
                delta: util,
                status: "over_quota"
            } : {
                timeFrac: 0,
                delta: 0,
                status: "unknown"
            };
        var resetMs = new Date(resetIso).getTime();
        if (isNaN(resetMs))
            return {
                timeFrac: 0,
                delta: 0,
                status: "unknown"
            };
        var remaining = resetMs - countdownNow;
        var timeFrac = (windowMs - remaining) / windowMs;
        if (timeFrac < 0)
            timeFrac = 0;
        else if (timeFrac > 1)
            timeFrac = 1;
        var delta = util - timeFrac * 100;
        var status;
        if (util >= 100)
            status = "over_quota";
        else if (delta >= 5)
            status = "over";
        else if (delta <= -5)
            status = "under";
        else
            status = "on";
        return {
            timeFrac: timeFrac,
            delta: delta,
            status: status
        };
    }

    function paceLabel(p) {
        if (!p)
            return "";
        if (p.status === "over_quota")
            return tr("Over quota");
        if (p.status === "over")
            return Math.round(p.delta) + "% " + tr("over pace");
        if (p.status === "under")
            return Math.round(-p.delta) + "% " + tr("under pace");
        if (p.status === "on")
            return tr("On pace");
        return "";
    }

    function paceColor(status) {
        if (status === "over_quota")
            return Theme.error;
        if (status === "over")
            return Theme.warning;
        return Theme.surfaceVariantText;
    }

    // Draws the pace tick — a short radial mark at the linear-burn position — on
    // a ring canvas. Shared by the 5h and 7d popout rings.
    function drawPaceTick(ctx, cx, cy, r, lw, pace) {
        if (!showPacing || !pace || pace.status === "unknown")
            return;
        var a = -Math.PI / 2 + 2 * Math.PI * Math.min(Math.max(pace.timeFrac, 0), 1);
        var ri = r - lw / 2 - 1, ro = r + lw / 2 + 1;
        ctx.beginPath();
        ctx.moveTo(cx + ri * Math.cos(a), cy + ri * Math.sin(a));
        ctx.lineTo(cx + ro * Math.cos(a), cy + ro * Math.sin(a));
        ctx.lineWidth = 2;
        ctx.lineCap = "butt";
        ctx.strokeStyle = Theme.surfaceText;
        ctx.stroke();
    }

    function formatCost(usd) {
        var useEur = lang === "fr" && usdEurRate > 0;
        var n = useEur ? usd * usdEurRate : usd;
        var sym = useEur ? "" : "$";
        var suffix = useEur ? " €" : "";
        if (n >= 1000)
            return sym + (n / 1000).toFixed(1) + "K" + suffix;
        if (n >= 100)
            return sym + Math.round(n) + suffix;
        if (n >= 10)
            return sym + n.toFixed(1) + suffix;
        return sym + n.toFixed(2) + suffix;
    }

    function formatTier(tier) {
        if (!tier || tier === "unknown")
            return "";
        if (tier.indexOf("max_20x") >= 0)
            return tr("Max") + " 20x";
        if (tier.indexOf("max_5x") >= 0)
            return tr("Max") + " 5x";
        if (tier.indexOf("max") >= 0)
            return tr("Max");
        if (tier.indexOf("pro") >= 0)
            return tr("Pro");
        if (tier.indexOf("free") >= 0)
            return tr("Free");
        if (tier.indexOf("team") >= 0)
            return tr("Team");
        if (tier.indexOf("enterprise") >= 0)
            return tr("Enterprise");
        return tier.replace(/_/g, " ").replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
    }

    function formatSubscription(subType, tier) {
        var tierLabel = formatTier(tier);
        if (!subType || subType === "unknown")
            return tierLabel;
        // Normalize subscriptionType like "claude_pro" → "Pro", "claude_max" → "Max"
        var subLabel = subType.replace(/^claude[_-]?/i, "").replace(/_/g, " ").replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
        // Prefer tier label if it adds info beyond subType
        if (tierLabel && tierLabel !== subLabel)
            return subLabel + " · " + tierLabel;
        return subLabel || tierLabel;
    }

    // Helper: parse "name:value,name:value,..." into profileData[name][field]
    // For numeric fields. Full object replacement ensures QML reactivity.
    function parseProfileSimple(val, field, isFloat) {
        var _pd = Object.assign({}, profileData);
        var entries = val.split(",");
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var colon = entry.indexOf(":");
            if (colon < 0)
                continue;
            var name = entry.substring(0, colon);
            var v = isFloat ? (parseFloat(entry.substring(colon + 1)) || 0) : (parseInt(entry.substring(colon + 1)) || 0);
            if (!_pd[name])
                _pd[name] = {};
            else
                _pd[name] = Object.assign({}, _pd[name]);
            _pd[name][field] = v;
        }
        return _pd;
    }

    // Uses indexOf(":") so ISO 8601 timestamps (which contain colons) are parsed correctly —
    // profile names never contain colons, so the first colon is always the name delimiter.
    // An empty value after ":" (e.g. "personal:") is stored as "" — means no data for that profile.
    function parseProfileString(val, field) {
        var _pd = Object.assign({}, profileData);
        var entries = val.split(",");
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var colon = entry.indexOf(":");
            if (colon < 0)
                continue;
            var name = entry.substring(0, colon);
            if (!_pd[name])
                _pd[name] = {};
            else
                _pd[name] = Object.assign({}, _pd[name]);
            _pd[name][field] = entry.substring(colon + 1);
        }
        return _pd;
    }
    // "Fable:6,Opus:12" -> [{ name: "Fable", percent: 6 }, ...]. The script strips
    // `,` `:` `|` from model names, so splitting on them here is safe.
    function parseScopedLimits(val) {
        var out = [];
        if (!val)
            return out;
        var entries = val.split(",");
        for (var i = 0; i < entries.length; i++) {
            var colon = entries[i].lastIndexOf(":");
            if (colon <= 0)
                continue;
            var name = entries[i].substring(0, colon);
            var pct = parseFloat(entries[i].substring(colon + 1));
            if (name === "" || isNaN(pct))
                continue;
            out.push({
                name: name,
                percent: pct
            });
        }
        return out;
    }

    function parseProfileBool(val, field) {
        var _pd = Object.assign({}, profileData);
        var entries = val.split(",");
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var colon = entry.indexOf(":");
            if (colon < 0)
                continue;
            var name = entry.substring(0, colon);
            if (!_pd[name])
                _pd[name] = {};
            else
                _pd[name] = Object.assign({}, _pd[name]);
            _pd[name][field] = entry.substring(colon + 1) === "true";
        }
        return _pd;
    }

    function parseLine(line) {
        var idx = line.indexOf("=");
        if (idx < 0)
            return;
        var key = line.substring(0, idx);
        var val = line.substring(idx + 1);

        switch (key) {
        case "SUBSCRIPTION_TYPE":
            subscriptionType = val;
            break;
        case "RATE_LIMIT_TIER":
            rateLimitTier = val;
            break;
        case "FIVE_HOUR_UTIL":
            fiveHourUtil = parseFloat(val) || 0;
            break;
        case "FIVE_HOUR_RESET":
            fiveHourReset = val;
            break;
        case "SEVEN_DAY_UTIL":
            sevenDayUtil = parseFloat(val) || 0;
            break;
        case "SEVEN_DAY_RESET":
            sevenDayReset = val;
            break;
        case "EXTRA_USAGE_ENABLED":
            extraUsageEnabled = (val === "true");
            break;
        case "USAGE_AGE":
            usageAge = parseInt(val) || 0;
            break;
        case "USAGE_ERROR":
            usageError = val;
            break;
        case "WEEKLY_SCOPED":
            weeklyScoped = parseScopedLimits(val);
            break;
        case "WEEK_WINDOW_START":
            weekWindowStart = val;
            break;
        case "WEEK_MESSAGES":
            weekMessages = parseInt(val) || 0;
            break;
        case "WEEK_SESSIONS":
            weekSessions = parseInt(val) || 0;
            break;
        case "WEEK_TOKENS":
            weekTokens = parseFloat(val) || 0;
            break;
        case "MONTH_TOKENS":
            monthTokens = parseFloat(val) || 0;
            break;
        case "ALLTIME_SESSIONS":
            alltimeSessions = parseInt(val) || 0;
            break;
        case "ALLTIME_MESSAGES":
            alltimeMessages = parseInt(val) || 0;
            break;
        case "FIRST_SESSION":
            firstSession = val;
            break;
        case "WEEK_MODELS":
            modelListData.clear();
            if (val.length > 0) {
                var wmpairs = val.split(",");
                for (var wmi = 0; wmi < wmpairs.length; wmi++) {
                    var wmeq = wmpairs[wmi].indexOf("=");
                    if (wmeq >= 0)
                        modelListData.append({
                            modelName: wmpairs[wmi].substring(0, wmeq),
                            modelTokens: parseInt(wmpairs[wmi].substring(wmeq + 1)) || 0
                        });
                }
            }
            break;
        case "DAILY":
            var parts = val.split(",");
            var arr = [];
            for (var j = 0; j < 7; j++)
                arr.push(j < parts.length ? (parseFloat(parts[j]) || 0) : 0);
            dailyTokens = arr;
            break;
        case "TODAY_COST":
            todayCost = parseFloat(val) || 0;
            break;
        case "WEEK_COST":
            weekCost = parseFloat(val) || 0;
            break;
        case "MONTH_COST":
            monthCost = parseFloat(val) || 0;
            break;
        case "USD_EUR_RATE":
            usdEurRate = parseFloat(val) || 0;
            break;
        case "DAILY_COSTS":
            var cparts = val.split(",");
            var carr = [];
            for (var k = 0; k < 7; k++)
                carr.push(k < cparts.length ? (parseFloat(cparts[k]) || 0) : 0);
            dailyCosts = carr;
            break;
        case "PROFILES":
            {
                profileListModel.clear();
                profileListModel.append({
                    name: "all"
                });
                var profs = val.split(",");
                for (var pi = 0; pi < profs.length; pi++)
                    profileListModel.append({
                        name: profs[pi]
                    });
                // Reset selectedProfile if it no longer exists in new profile list
                if (selectedProfile !== "all") {
                    var found = false;
                    for (var fi = 0; fi < profs.length; fi++)
                        if (profs[fi] === selectedProfile) {
                            found = true;
                            break;
                        }
                    if (!found)
                        selectedProfile = "all";
                }
                break;
            }
        case "PROFILE_WEEK_TOKENS":
            profileData = parseProfileSimple(val, "weekTokens", false);
            break;
        case "PROFILE_MONTH_TOKENS":
            profileData = parseProfileSimple(val, "monthTokens", false);
            break;
        case "PROFILE_WEEK_MESSAGES":
            profileData = parseProfileSimple(val, "weekMessages", false);
            break;
        case "PROFILE_WEEK_SESSIONS":
            profileData = parseProfileSimple(val, "weekSessions", false);
            break;
        case "PROFILE_TODAY_COST":
            profileData = parseProfileSimple(val, "todayCost", true);
            break;
        case "PROFILE_WEEK_COST":
            profileData = parseProfileSimple(val, "weekCost", true);
            break;
        case "PROFILE_MONTH_COST":
            profileData = parseProfileSimple(val, "monthCost", true);
            break;
        case "PROFILE_SUBSCRIPTION":
            profileData = parseProfileString(val, "subscriptionType");
            break;
        case "PROFILE_TIER":
            profileData = parseProfileString(val, "rateLimitTier");
            break;
        case "PROFILE_FIVE_HOUR_UTIL":
            profileData = parseProfileSimple(val, "fiveHourUtil", true);
            break;
        case "PROFILE_SEVEN_DAY_UTIL":
            profileData = parseProfileSimple(val, "sevenDayUtil", true);
            break;
        case "PROFILE_FIVE_HOUR_RESET":
            profileData = parseProfileString(val, "fiveHourReset");
            break;
        case "PROFILE_SEVEN_DAY_RESET":
            profileData = parseProfileString(val, "sevenDayReset");
            break;
        case "PROFILE_EXTRA_USAGE":
            profileData = parseProfileBool(val, "extraUsageEnabled");
            break;
        case "PROFILE_USAGE_AGE":
            profileData = parseProfileSimple(val, "usageAge", false);
            break;
        case "PROFILE_USAGE_ERROR":
            profileData = parseProfileString(val, "usageError");
            break;
        case "PROFILE_WEEK_WINDOW_START":
            profileData = parseProfileString(val, "weekWindowStart");
            break;
        case "PROFILE_WEEKLY_SCOPED":
            {
                // Pipe-separated because the value itself holds `Model:percent`
                // pairs joined by commas, same shape as PROFILE_WEEK_MODELS.
                var _pd4 = Object.assign({}, profileData);
                var blocks4 = val.split("|");
                for (var bi4 = 0; bi4 < blocks4.length; bi4++) {
                    var c4 = blocks4[bi4].indexOf(":");
                    if (c4 < 0)
                        continue;
                    var pname4 = blocks4[bi4].substring(0, c4);
                    if (!_pd4[pname4])
                        _pd4[pname4] = {};
                    else
                        _pd4[pname4] = Object.assign({}, _pd4[pname4]);
                    _pd4[pname4].weeklyScoped = parseScopedLimits(blocks4[bi4].substring(c4 + 1));
                }
                profileData = _pd4;
                break;
            }
        case "PROFILE_DAILY":
            {
                var _pd1 = Object.assign({}, profileData);
                var blocks1 = val.split("|");
                for (var bi1 = 0; bi1 < blocks1.length; bi1++) {
                    var blk1 = blocks1[bi1];
                    var c1 = blk1.indexOf(":");
                    if (c1 < 0)
                        continue;
                    var pname1 = blk1.substring(0, c1);
                    var csv1 = blk1.substring(c1 + 1);
                    if (!_pd1[pname1])
                        _pd1[pname1] = {};
                    else
                        _pd1[pname1] = Object.assign({}, _pd1[pname1]);
                    var parts1 = csv1.split(",");
                    var arr1 = [];
                    for (var di = 0; di < 7; di++)
                        arr1.push(di < parts1.length ? (parseFloat(parts1[di]) || 0) : 0);
                    _pd1[pname1].daily = arr1;
                }
                profileData = _pd1;
                break;
            }
        case "PROFILE_DAILY_COSTS":
            {
                var _pd2 = Object.assign({}, profileData);
                var blocks2 = val.split("|");
                for (var bi2 = 0; bi2 < blocks2.length; bi2++) {
                    var blk2 = blocks2[bi2];
                    var c2 = blk2.indexOf(":");
                    if (c2 < 0)
                        continue;
                    var pname2 = blk2.substring(0, c2);
                    var csv2 = blk2.substring(c2 + 1);
                    if (!_pd2[pname2])
                        _pd2[pname2] = {};
                    else
                        _pd2[pname2] = Object.assign({}, _pd2[pname2]);
                    var parts2 = csv2.split(",");
                    var arr2 = [];
                    for (var dci = 0; dci < 7; dci++)
                        arr2.push(dci < parts2.length ? (parseFloat(parts2[dci]) || 0) : 0);
                    _pd2[pname2].dailyCosts = arr2;
                }
                profileData = _pd2;
                break;
            }
        case "PROFILE_WEEK_MODELS":
            {
                var _pd3 = Object.assign({}, profileData);
                var blocks3 = val.split("|");
                for (var bi3 = 0; bi3 < blocks3.length; bi3++) {
                    var blk3 = blocks3[bi3];
                    var c3 = blk3.indexOf(":");
                    if (c3 < 0)
                        continue;
                    var pname3 = blk3.substring(0, c3);
                    var mcsv = blk3.substring(c3 + 1);
                    if (!_pd3[pname3])
                        _pd3[pname3] = {};
                    else
                        _pd3[pname3] = Object.assign({}, _pd3[pname3]);
                    var wms = [];
                    if (mcsv.length > 0) {
                        var mentries = mcsv.split(",");
                        for (var mi = 0; mi < mentries.length; mi++) {
                            var eq = mentries[mi].indexOf("=");
                            if (eq < 0)
                                continue;
                            wms.push({
                                modelName: mentries[mi].substring(0, eq),
                                modelTokens: parseInt(mentries[mi].substring(eq + 1)) || 0
                            });
                        }
                    }
                    _pd3[pname3].weekModels = wms;
                }
                profileData = _pd3;
                break;
            }
        }
    }

    // --- Data fetching ---

    // Start a run now, or queue one when a run is already in flight.
    function rerun() {
        if (usageProcess.running)
            rerunPending = true;
        else
            usageProcess.running = true;
    }

    // Manual refresh from the popout header. Skips the script's usage cache, so
    // it is also the way out of a stale warning once the login is fixed - the
    // refresh interval can be 15 minutes, which is a long time to stare at a
    // warning you have already dealt with.
    function refreshNow() {
        refreshResult = "";
        forceFetch = true;
        rerun();
    }

    // Pick up an added/removed profile now instead of waiting for the refresh timer
    onCustomProfilesChanged: rerun()

    Process {
        id: usageProcess
        // Wrapped in `timeout` as a watchdog. The refresh timer below skips a tick
        // while `running` is true, so a single run that never exits (a hung
        // `claude --version`, a stalled curl/find) freezes the widget on stale
        // values until the plugin is reloaded. Killing the run lets onExited fire.
        // `--force` makes the script skip its usage cache TTL, so the manual
        // refresh actually refetches instead of replaying the same cached
        // response. Profile arguments are `name=path`, never a bare flag.
        command: ["timeout", "120", "bash", root.scriptPath].concat(root.forceFetch ? ["--force"] : []).concat(root.customProfiles.filter(p => p && p.name && p.path).map(p => p.name + "=" + p.path))
        running: false

        stdout: SplitParser {
            onRead: data => root.parseLine(data.trim())
        }

        // A forced run is the only one a user is waiting on, so its outcome is
        // reported on the button. Without this a click that ends in the same
        // numbers - the usual case when the login is dead - looks like a button
        // that does nothing.
        onRunningChanged: {
            if (running)
                root.forcedRunInFlight = root.forceFetch;
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.isLoading = false;
                root.refreshEpoch++;
            }
            if (root.forcedRunInFlight) {
                root.forcedRunInFlight = false;
                root.refreshResult = (exitCode === 0 && root.usageError === "") ? "ok" : "fail";
                refreshResultTimer.restart();
            }
            // A run requested while another was in flight is honoured now. The
            // force flag survives until the run that was asked for has started,
            // otherwise a manual refresh queued behind a timer tick would lose it.
            if (root.rerunPending) {
                root.rerunPending = false;
                Qt.callLater(function() {
                    if (!usageProcess.running)
                        usageProcess.running = true;
                });
            } else {
                root.forceFetch = false;
            }
        }
    }

    // Lives on the widget, not in the popout: the popout may be closed before a
    // slow run finishes, and a dangling timer in a destroyed component would
    // leave refreshResult set forever.
    Timer {
        id: refreshResultTimer
        interval: 3000
        onTriggered: root.refreshResult = ""
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!usageProcess.running)
                usageProcess.running = true;
        }
    }

    // --- Taskbar pills (show 5h utilization) ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            // Dimmed with a "?" suffix while the numbers are not live, so the bar
            // never states a percentage it cannot back up. Details in the popout.
            opacity: root.usageError !== "" ? 0.6 : 1

            Canvas {
                id: hRing
                width: root.iconSize
                height: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
                renderStrategy: Canvas.Cooperative

                property real percent: root.fiveHourUtil
                onPercentChanged: requestPaint()
                onWidthChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = width / 2, cy = height / 2, r = width * 0.375, lw = width * 0.125;

                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                    ctx.lineWidth = lw;
                    ctx.strokeStyle = Theme.surfaceVariant;
                    ctx.stroke();

                    var pct = percent / 100;
                    if (pct > 0) {
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1));
                        ctx.lineWidth = lw;
                        ctx.strokeStyle = root.progressColor(percent);
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                }
            }

            StyledText {
                text: Math.round(root.fiveHourUtil) + "%" + (root.usageError !== "" ? "?" : (root.pillOverPace ? " ↑" : ""))
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: root.usageError === "" && root.pillOverPace ? root.paceColor(root.pillFivePace.status) : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS || 4
            opacity: root.usageError !== "" ? 0.6 : 1

            Canvas {
                id: vRing
                width: root.iconSize
                height: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
                renderStrategy: Canvas.Cooperative

                property real percent: root.fiveHourUtil
                onPercentChanged: requestPaint()
                onWidthChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = width / 2, cy = height / 2, r = width * 0.375, lw = width * 0.125;

                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                    ctx.lineWidth = lw;
                    ctx.strokeStyle = Theme.surfaceVariant;
                    ctx.stroke();

                    var pct = percent / 100;
                    if (pct > 0) {
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1));
                        ctx.lineWidth = lw;
                        ctx.strokeStyle = root.progressColor(percent);
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                }
            }

            StyledText {
                text: Math.round(root.fiveHourUtil) + "%" + (root.usageError !== "" ? "?" : (root.pillOverPace ? " ↑" : ""))
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: root.usageError === "" && root.pillOverPace ? root.paceColor(root.pillFivePace.status) : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- Popout ---

    // Profile selector components — declared at root scope for Loader access
    Component {
        id: profileTabsComponent
        Row {
            spacing: Theme.spacingXS

            Repeater {
                model: profileListModel
                delegate: Rectangle {
                    width: tabLabel.implicitWidth + Theme.spacingM * 2
                    height: 32
                    radius: 16
                    color: root.selectedProfile === name ? Theme.primary : Theme.surfaceVariant

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    StyledText {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: name === "all" ? root.tr("All") : name
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: root.selectedProfile === name ? Font.Medium : Font.Normal
                        color: root.selectedProfile === name ? Theme.primaryText : Theme.surfaceVariantText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedProfile = name
                    }
                }
            }
        }
    }

    Component {
        id: profileDropdownComponent
        Rectangle {
            // Note: z:100 on popup is scoped to subtree; cards below may overlap when open.
            // Acceptable for >5 profiles (rare case). Full modal overlay is out of scope.
            width: parent ? parent.width : 0
            height: 36
            radius: 8
            color: Theme.surfaceVariant

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tr("Profile") + ":"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.selectedProfile === "all" ? root.tr("All") : root.selectedProfile
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: profileDropdownPopup.visible = !profileDropdownPopup.visible
            }

            MouseArea {
                id: profileDropdownOverlay
                visible: profileDropdownPopup.visible
                anchors.fill: root
                z: 99
                onClicked: profileDropdownPopup.visible = false
            }

            Rectangle {
                id: profileDropdownPopup
                visible: false
                z: 100
                anchors.top: parent.bottom
                anchors.topMargin: 4
                anchors.left: parent.left
                width: parent.width
                height: dropdownCol.implicitHeight + Theme.spacingS * 2
                radius: 8
                color: Theme.surfaceContainer

                Column {
                    id: dropdownCol
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: 2

                    Repeater {
                        model: profileListModel
                        delegate: Rectangle {
                            width: parent.width
                            height: 28
                            radius: 4
                            color: root.selectedProfile === name ? Theme.primary : "transparent"

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingXS
                                text: name === "all" ? root.tr("All") : name
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.selectedProfile === name ? Theme.primaryText : Theme.surfaceText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedProfile = name;
                                    profileDropdownPopup.visible = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: root.tr("Claude Code Usage")
            detailsText: {
                var label = root.formatSubscription(root.displaySubscriptionType, root.displayRateLimitTier);
                return label ? root.tr("Subscription") + ": " + label : "";
            }
            showCloseButton: true

            // Manual refresh, styled after the close button next to it. Spins
            // while a run is in flight, which is also the only feedback that a
            // click did anything when the numbers come back unchanged.
            headerActions: Component {
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: refreshArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.12) : "transparent"

                    DankIcon {
                        id: refreshIcon
                        anchors.centerIn: parent
                        // The icon carries the verdict for a few seconds: a check
                        // when the numbers are live again, an error mark when the
                        // fetch failed and the warning below still stands.
                        name: root.refreshResult === "ok" ? "check" : root.refreshResult === "fail" ? "error" : "refresh"
                        size: Theme.iconSize - 4
                        color: {
                            if (root.refreshResult === "fail")
                                return Theme.error;
                            if (root.refreshResult === "ok")
                                return Theme.primary;
                            return refreshArea.containsMouse ? Theme.primary : Theme.surfaceVariantText;
                        }

                        RotationAnimator {
                            target: refreshIcon
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            running: root.refreshing
                            onRunningChanged: {
                                if (!running)
                                    refreshIcon.rotation = 0;
                            }
                        }
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshNow()
                    }
                }
            }

            Column {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingL

                // --- Profile selector (tabs ≤5 entries, dropdown >5) ---
                // Hidden when only one real profile (e.g. default only, no CCS instances)
                // count > 2 means "All" + at least 2 real profiles
                Item {
                    width: parent.width
                    height: profileSelectorLoader.height
                    visible: profileListModel.count > 2

                    Loader {
                        id: profileSelectorLoader
                        width: parent.width
                        // Explicit height binding — Loader defaults to 0 without this
                        height: item ? item.implicitHeight : 0
                        sourceComponent: profileListModel.count <= 5 ? profileTabsComponent : profileDropdownComponent
                    }
                }

                // --- 5h Rate Window card ---
                StyledRect {
                    width: parent.width
                    height: fiveHourContent.implicitHeight + Theme.spacingS * 2
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: fiveHourContent
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingM

                        Canvas {
                            id: fiveHourRing
                            width: 100
                            height: 100
                            anchors.verticalCenter: parent.verticalCenter
                            renderStrategy: Canvas.Cooperative

                            property real percent: root.displayFiveHourUtil
                            onPercentChanged: requestPaint()
                            property var pace: root.fiveHourPace
                            onPaceChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var cx = width / 2, cy = height / 2, r = 38, lw = 8;

                                ctx.beginPath();
                                ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                ctx.lineWidth = lw;
                                ctx.strokeStyle = Theme.surfaceVariant;
                                ctx.stroke();

                                var pct = percent / 100;
                                if (pct > 0) {
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1));
                                    ctx.lineWidth = lw;
                                    ctx.strokeStyle = root.progressColor(percent);
                                    ctx.lineCap = "round";
                                    ctx.stroke();
                                }

                                root.drawPaceTick(ctx, cx, cy, r, lw, pace);
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: Math.round(root.displayFiveHourUtil) + "%" + root.staleMark
                                font.pixelSize: Theme.fontSizeXLarge
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }
                        }

                        Column {
                            width: Math.max(0, parent.width - fiveHourRing.width - parent.spacing)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: root.tr("5h Rate Window")
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                width: parent.width
                                text: Math.round(root.displayFiveHourUtil) + "%" + root.staleMark + " " + root.tr("used")
                                font.pixelSize: Theme.fontSizeMedium
                                color: root.progressColor(root.displayFiveHourUtil)
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                width: parent.width
                                text: root.paceLabel(root.fiveHourPace)
                                visible: root.showPacing && root.usageWarning === "" && text !== ""
                                font.pixelSize: Theme.fontSizeMedium
                                color: root.paceColor(root.fiveHourPace.status)
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                width: parent.width
                                text: root.displayFiveHourCountdown ? root.tr("Resets in") + " " + root.displayFiveHourCountdown : ""
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                // Hidden while the numbers are not live: the reset time comes
                                // from the same stale response, so it counts down to an instant
                                // that has already passed and reads "Resetting..." forever.
                                visible: root.usageWarning === "" && root.displayFiveHourCountdown !== ""
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                width: parent.width
                                text: root.usageWarning
                                visible: root.usageWarning !== ""
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.error
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // --- 7-Day Usage card ---
                StyledRect {
                    width: parent.width
                    height: sevenDayContent.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: sevenDayContent
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        Canvas {
                            id: weeklySmallRing
                            width: 72
                            height: 72
                            anchors.verticalCenter: parent.verticalCenter
                            renderStrategy: Canvas.Cooperative

                            property real percent: root.displaySevenDayUtil
                            onPercentChanged: requestPaint()
                            property var pace: root.sevenDayPace
                            onPaceChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var cx = width / 2, cy = height / 2, r = 28, lw = 6;

                                ctx.beginPath();
                                ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                ctx.lineWidth = lw;
                                ctx.strokeStyle = Theme.surfaceVariant;
                                ctx.stroke();

                                var pct = percent / 100;
                                if (pct > 0) {
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1));
                                    ctx.lineWidth = lw;
                                    ctx.strokeStyle = root.progressColor(percent);
                                    ctx.lineCap = "round";
                                    ctx.stroke();
                                }

                                root.drawPaceTick(ctx, cx, cy, r, lw, pace);
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: Math.round(root.displaySevenDayUtil) + "%" + root.staleMark
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }
                        }

                        Column {
                            width: Math.max(0, parent.width - weeklySmallRing.width - parent.spacing)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: root.tr("7-Day Usage") + " · " + Math.round(root.displaySevenDayUtil) + "%" + root.staleMark
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                            }
                            // One row per model that has its own weekly cap. The
                            // all-models ring can sit at 71% while a single model
                            // is at 6%, so these are not derivable from it.
                            Repeater {
                                model: root.displayWeeklyScoped
                                StyledText {
                                    required property var modelData
                                    width: parent.width
                                    text: modelData.name + " · " + Math.round(modelData.percent) + "%" + root.staleMark
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: root.progressColor(modelData.percent)
                                    wrapMode: Text.WordWrap
                                }
                            }
                            StyledText {
                                width: parent.width
                                text: root.paceLabel(root.sevenDayPace)
                                visible: root.showPacing && root.usageWarning === "" && text !== ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.paceColor(root.sevenDayPace.status)
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                width: parent.width
                                text: {
                                    var parts = [];
                                    if (root.displayWeekSessions > 0)
                                        parts.push(root.displayWeekSessions + " " + root.tr("sessions"));
                                    if (root.displayWeekMessages > 0)
                                        parts.push(root.displayWeekMessages + " " + root.tr("msgs"));
                                    if (root.weekWindowLabel !== "")
                                        parts.push(root.weekWindowLabel);
                                    return parts.join(" · ");
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                visible: text !== ""
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                width: parent.width
                                text: root.displaySevenDayCountdown ? root.tr("Resets in") + " " + root.displaySevenDayCountdown : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                visible: root.usageWarning === "" && root.displaySevenDayCountdown !== ""
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // --- Token Consumption card ---
                StyledRect {
                    width: parent.width
                    height: consumptionCol.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: consumptionCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        StyledText {
                            text: root.tr("Token Consumption")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Row {
                            width: parent.width

                            Column {
                                width: parent.width / 3
                                spacing: 4

                                StyledText {
                                    text: root.tr("Today")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                StyledText {
                                    text: root.formatTokens(root.displayDailyTokens[root.todayIndex])
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                StyledText {
                                    text: root.formatCost(root.displayTodayCost)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: root.displayTodayCost > 0
                                }
                            }

                            Column {
                                width: parent.width / 3
                                spacing: 4

                                StyledText {
                                    text: root.tr("Week")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                StyledText {
                                    text: root.formatTokens(root.displayWeekTokens)
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                StyledText {
                                    text: root.formatCost(root.displayWeekCost)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: root.displayWeekCost > 0
                                }
                            }

                            Column {
                                width: parent.width / 3
                                spacing: 4

                                StyledText {
                                    text: root.tr("Month")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                StyledText {
                                    text: root.formatTokens(root.displayMonthTokens)
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                StyledText {
                                    text: root.formatCost(root.displayMonthCost)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: root.displayMonthCost > 0
                                }
                            }
                        }
                    }
                }

                // --- Daily activity card ---
                StyledRect {
                    width: parent.width
                    height: dailyCol.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: dailyCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: root.tr("Daily Activity")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Item {
                            width: parent.width
                            height: 70

                            Row {
                                id: chartRow
                                anchors.fill: parent
                                spacing: 4

                                Repeater {
                                    model: 7
                                    delegate: Column {
                                        width: (chartRow.width - 6 * 4) / 7
                                        height: chartRow.height
                                        spacing: 2

                                        Item {
                                            width: parent.width
                                            height: parent.height - dayLabel.height - 2

                                            // Background bar: total tokens (always shown)
                                            Rectangle {
                                                id: totalBar
                                                anchors.bottom: parent.bottom
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: Math.max(parent.width - 4, 4)
                                                height: root.maxDaily > 0 ? Math.max(root.dailyTokens[index] / root.maxDaily * parent.height, root.dailyTokens[index] > 0 ? 3 : 0) : 0
                                                radius: 2
                                                color: root.selectedProfile === "all" ? (index === root.todayIndex ? Theme.primary : Theme.surfaceVariant) : Theme.surfaceVariant
                                                opacity: root.hoveredDay >= 0 && index !== root.hoveredDay ? 0.4 : 1.0

                                                Behavior on opacity {
                                                    NumberAnimation {
                                                        duration: 120
                                                    }
                                                }
                                            }

                                            // Overlay bar: profile tokens (shown only when a profile is selected)
                                            Rectangle {
                                                visible: root.selectedProfile !== "all" && root.profileDailyTokens.length > 0
                                                anchors.bottom: parent.bottom
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: Math.max(parent.width - 4, 4)
                                                height: root.maxDaily > 0 && root.profileDailyTokens.length > index ? Math.max(root.profileDailyTokens[index] / root.maxDaily * parent.height, root.profileDailyTokens[index] > 0 ? 3 : 0) : 0
                                                radius: 2
                                                color: Theme.primary
                                                opacity: root.hoveredDay >= 0 && index !== root.hoveredDay ? 0.4 : 1.0

                                                Behavior on opacity {
                                                    NumberAnimation {
                                                        duration: 120
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: root.dailyTokens[index] > 0
                                                onEntered: root.hoveredDay = index
                                                onExited: root.hoveredDay = -1
                                            }
                                        }

                                        StyledText {
                                            id: dayLabel
                                            text: root.dayLabels[index]
                                            font.pixelSize: 11
                                            color: index === root.hoveredDay ? Theme.primary : index === root.todayIndex ? Theme.primary : Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Tooltip on hover — child of StyledRect to avoid clip issues
                    Rectangle {
                        id: chartTooltip
                        visible: root.hoveredDay >= 0 && root.dailyTokens[root.hoveredDay] > 0
                        z: 10

                        x: {
                            var colW = (chartRow.width - 6 * 4) / 7;
                            var cx = root.hoveredDay * (colW + 4) + colW / 2 - width / 2;
                            var chartX = chartRow.mapToItem(chartTooltip.parent, 0, 0).x;
                            var raw = chartX + cx;
                            return Math.max(Theme.spacingM, Math.min(raw, parent.width - width - Theme.spacingM));
                        }
                        y: {
                            var chartY = chartRow.mapToItem(chartTooltip.parent, 0, 0).y;
                            return chartY - height - 2;
                        }

                        width: tooltipCol.width + Theme.spacingS * 2
                        height: tooltipCol.height + Theme.spacingXS * 2
                        radius: 4
                        color: Theme.surfaceContainer

                        Column {
                            id: tooltipCol
                            anchors.centerIn: parent
                            spacing: 1

                            // Line 1: total tokens (with "total" suffix when a profile is selected)
                            StyledText {
                                text: {
                                    if (root.hoveredDay < 0)
                                        return "";
                                    var t = root.formatTokens(root.dailyTokens[root.hoveredDay]);
                                    return root.selectedProfile !== "all" ? t + " " + root.tr("total") : t;
                                }
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            // Line 2: profile tokens (only when a profile is selected and has data)
                            StyledText {
                                visible: root.selectedProfile !== "all" && root.hoveredDay >= 0 && root.profileDailyTokens.length > root.hoveredDay && root.profileDailyTokens[root.hoveredDay] > 0
                                text: {
                                    if (root.hoveredDay < 0 || root.profileDailyTokens.length <= root.hoveredDay)
                                        return "";
                                    return root.formatTokens(root.profileDailyTokens[root.hoveredDay]) + " " + root.selectedProfile;
                                }
                                font.pixelSize: 11
                                color: Theme.primary
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            // Line 3: total cost (always shown when > 0, uses aggregate dailyCosts)
                            StyledText {
                                visible: root.hoveredDay >= 0 && root.dailyCosts[root.hoveredDay] > 0
                                text: root.hoveredDay >= 0 ? root.formatCost(root.dailyCosts[root.hoveredDay]) : ""
                                font.pixelSize: 11
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // --- Model breakdown card ---
                StyledRect {
                    width: parent.width
                    height: modelCardCol.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    visible: {
                        if (root.selectedProfile === "all")
                            return modelListData.count > 0;
                        var pd = root.profileData[root.selectedProfile];
                        return pd && pd.weekModels && pd.weekModels.length > 0;
                    }

                    Column {
                        id: modelCardCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: root.tr("Models This Week")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Column {
                            id: modelCol
                            width: parent.width
                            spacing: Theme.spacingS

                            Repeater {
                                id: modelRepeater
                                model: {
                                    if (root.selectedProfile === "all")
                                        return modelListData;
                                    var pd = root.profileData[root.selectedProfile];
                                    return (pd && pd.weekModels) ? pd.weekModels : [];
                                }
                                delegate: Column {
                                    width: modelCol.width
                                    spacing: 3

                                    // When model is a ListModel, role names are direct properties.
                                    // When model is a JS array, values are accessed via modelData.
                                    property string _modelName: modelListData === modelRepeater.model ? modelName : (modelData ? modelData.modelName : "")
                                    property int _modelTokens: modelListData === modelRepeater.model ? modelTokens : (modelData ? (modelData.modelTokens || 0) : 0)

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingXS

                                        StyledText {
                                            text: root.shortModelName(_modelName)
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            text: root.formatTokens(_modelTokens)
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 4
                                        radius: 2
                                        color: Theme.surfaceVariant

                                        Rectangle {
                                            width: root.displayWeekTokens > 0 ? parent.width * Math.min(_modelTokens / root.displayWeekTokens, 1) : 0
                                            height: parent.height
                                            radius: 2
                                            color: Theme.primary
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- All-time footer card ---
                StyledRect {
                    width: parent.width
                    height: allTimeRow.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    visible: root.selectedProfile === "all" && (root.alltimeSessions > 0 || root.alltimeMessages > 0)

                    Row {
                        id: allTimeRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        DankIcon {
                            id: allTimeIcon
                            name: "calendar_today"
                            size: 14
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            width: Math.max(0, parent.width - allTimeIcon.width - parent.spacing)
                            text: {
                                var parts = [];
                                if (root.firstSession && root.firstSession !== "unknown")
                                    parts.push(root.tr("Since") + " " + root.firstSession);
                                parts.push(root.alltimeSessions + " " + root.tr("sessions"));
                                parts.push(root.alltimeMessages.toLocaleString() + " " + root.tr("msgs"));
                                return parts.join("  ·  ");
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Bottom padding to match sides (compensates Column spacing)
                Item {
                    width: 1
                    height: 1
                }
            }
        }
    }
}
