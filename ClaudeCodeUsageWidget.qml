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
    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) { return Tr.tr(key, lang) }

    // Rolling 7-day labels (index 0 = 6 days ago, index 6 = today)
    property var dayLabels: {
        var frDays = ["Di", "Lu", "Ma", "Me", "Je", "Ve", "Sa"]
        var enDays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        var days = lang === "fr" ? frDays : enDays
        var labels = []
        var now = new Date()
        for (var i = 6; i >= 0; i--) {
            var d = new Date(now.getTime() - i * 86400000)
            labels.push(days[d.getDay()])
        }
        return labels
    }

    // Settings
    property int refreshInterval: (pluginData.refreshInterval || 60) * 1000

    // API usage data
    property string subscriptionType: ""
    property string rateLimitTier: ""
    property real fiveHourUtil: 0
    property string fiveHourReset: ""
    property real sevenDayUtil: 0
    property string sevenDayReset: ""
    property bool extraUsageEnabled: false

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

    // Model list
    ListModel { id: modelListData }

    // Today is always the last element in rolling 7-day window
    property int todayIndex: 6

    // Derived
    property real maxDaily: Math.max.apply(null, dailyTokens) || 1
    property bool isLoading: true

    // Live countdown
    property real countdownNow: Date.now()

    property string fiveHourCountdown: {
        if (!fiveHourReset) return ""
        var resetMs = new Date(fiveHourReset).getTime()
        var remaining = Math.max(0, resetMs - countdownNow)
        if (remaining <= 0) return tr("Resetting...")
        var hours = Math.floor(remaining / 3600000)
        var mins = Math.floor((remaining % 3600000) / 60000)
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
    }

    property string sevenDayCountdown: {
        if (!sevenDayReset) return ""
        var resetMs = new Date(sevenDayReset).getTime()
        var remaining = Math.max(0, resetMs - countdownNow)
        if (remaining <= 0) return tr("Resetting...")
        var days = Math.floor(remaining / 86400000)
        var hours = Math.floor((remaining % 86400000) / 3600000)
        var mins = Math.floor((remaining % 3600000) / 60000)
        if (days > 0) return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m"
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.countdownNow = Date.now()
    }

    // Script path via PluginService
    property string scriptPath: PluginService.pluginDirectory + "/claudeCodeUsage/get-claude-usage"

    popoutWidth: 380
    popoutHeight: 660

    // --- Helpers ---

    function formatTokens(n) {
        if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
        if (n >= 1000) return (n / 1000).toFixed(1) + "K"
        return Math.round(n).toString()
    }

    function shortModelName(name) {
        if (name.indexOf("opus") >= 0) return "Opus"
        if (name.indexOf("sonnet") >= 0) return "Sonnet"
        if (name.indexOf("haiku") >= 0) return "Haiku"
        return name
    }

    function progressColor(pct) {
        if (pct > 80) return Theme.error
        if (pct > 50) return Theme.warning
        return Theme.primary
    }

    function formatTier(tier) {
        if (tier.indexOf("max_20x") >= 0) return "Max 20x"
        if (tier.indexOf("max_5x") >= 0) return "Max 5x"
        if (tier.indexOf("pro") >= 0) return "Pro"
        if (tier.indexOf("free") >= 0) return "Free"
        return tier
    }

    function parseLine(line) {
        var idx = line.indexOf("=")
        if (idx < 0) return
        var key = line.substring(0, idx)
        var val = line.substring(idx + 1)

        switch (key) {
        case "SUBSCRIPTION_TYPE": subscriptionType = val; break
        case "RATE_LIMIT_TIER": rateLimitTier = val; break
        case "FIVE_HOUR_UTIL": fiveHourUtil = parseFloat(val) || 0; break
        case "FIVE_HOUR_RESET": fiveHourReset = val; break
        case "SEVEN_DAY_UTIL": sevenDayUtil = parseFloat(val) || 0; break
        case "SEVEN_DAY_RESET": sevenDayReset = val; break
        case "EXTRA_USAGE_ENABLED": extraUsageEnabled = (val === "true"); break
        case "WEEK_MESSAGES": weekMessages = parseInt(val) || 0; break
        case "WEEK_SESSIONS": weekSessions = parseInt(val) || 0; break
        case "WEEK_TOKENS": weekTokens = parseFloat(val) || 0; break
        case "MONTH_TOKENS": monthTokens = parseFloat(val) || 0; break
        case "ALLTIME_SESSIONS": alltimeSessions = parseInt(val) || 0; break
        case "ALLTIME_MESSAGES": alltimeMessages = parseInt(val) || 0; break
        case "FIRST_SESSION": firstSession = val; break
        case "WEEK_MODELS":
            modelListData.clear()
            if (val.length > 0) {
                var pairs = val.split(",")
                for (var i = 0; i < pairs.length; i++) {
                    var kv = pairs[i].split(":")
                    if (kv.length === 2)
                        modelListData.append({ modelName: kv[0], modelTokens: parseInt(kv[1]) || 0 })
                }
            }
            break
        case "DAILY":
            var parts = val.split(",")
            var arr = []
            for (var j = 0; j < 7; j++)
                arr.push(j < parts.length ? (parseFloat(parts[j]) || 0) : 0)
            dailyTokens = arr
            break
        }
    }

    // --- Data fetching ---

    Process {
        id: usageProcess
        command: ["bash", root.scriptPath]
        running: false

        stdout: SplitParser {
            onRead: data => root.parseLine(data.trim())
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
        }
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!usageProcess.running)
                usageProcess.running = true
        }
    }

    // --- Taskbar pills (show 5h utilization) ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Canvas {
                id: hRing
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                renderStrategy: Canvas.Cooperative

                property real percent: root.fiveHourUtil
                onPercentChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var cx = width / 2, cy = height / 2, r = 7.5, lw = 2.5

                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                    ctx.lineWidth = lw
                    ctx.strokeStyle = Theme.surfaceVariant
                    ctx.stroke()

                    var pct = percent / 100
                    if (pct > 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1))
                        ctx.lineWidth = lw
                        ctx.strokeStyle = root.progressColor(percent)
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }
                }
            }

            StyledText {
                text: Math.round(root.fiveHourUtil) + "%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS || 4

            Canvas {
                id: vRing
                width: 20
                height: 20
                anchors.horizontalCenter: parent.horizontalCenter
                renderStrategy: Canvas.Cooperative

                property real percent: root.fiveHourUtil
                onPercentChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var cx = width / 2, cy = height / 2, r = 7.5, lw = 2.5

                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                    ctx.lineWidth = lw
                    ctx.strokeStyle = Theme.surfaceVariant
                    ctx.stroke()

                    var pct = percent / 100
                    if (pct > 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1))
                        ctx.lineWidth = lw
                        ctx.strokeStyle = root.progressColor(percent)
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }
                }
            }

            StyledText {
                text: Math.round(root.fiveHourUtil) + "%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- Popout ---

    popoutContent: Component {
        PopoutComponent {
            headerText: root.tr("Claude Code Usage")
            detailsText: root.rateLimitTier ? root.tr("Subscription") + " : " + root.formatTier(root.rateLimitTier) : ""
            showCloseButton: true

            Column {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingL

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

                            property real percent: root.fiveHourUtil
                            onPercentChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var cx = width / 2, cy = height / 2, r = 38, lw = 8

                                ctx.beginPath()
                                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                ctx.lineWidth = lw
                                ctx.strokeStyle = Theme.surfaceVariant
                                ctx.stroke()

                                var pct = percent / 100
                                if (pct > 0) {
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1))
                                    ctx.lineWidth = lw
                                    ctx.strokeStyle = root.progressColor(percent)
                                    ctx.lineCap = "round"
                                    ctx.stroke()
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: Math.round(root.fiveHourUtil) + "%"
                                font.pixelSize: Theme.fontSizeXLarge
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            StyledText {
                                text: root.tr("5h Rate Window")
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: Math.round(root.fiveHourUtil) + "% " + root.tr("used")
                                font.pixelSize: Theme.fontSizeMedium
                                color: root.progressColor(root.fiveHourUtil)
                            }
                            StyledText {
                                text: root.fiveHourCountdown ? root.tr("Resets in") + " " + root.fiveHourCountdown : ""
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                visible: root.fiveHourCountdown !== ""
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

                            property real percent: root.sevenDayUtil
                            onPercentChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var cx = width / 2, cy = height / 2, r = 28, lw = 6

                                ctx.beginPath()
                                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                ctx.lineWidth = lw
                                ctx.strokeStyle = Theme.surfaceVariant
                                ctx.stroke()

                                var pct = percent / 100
                                if (pct > 0) {
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1))
                                    ctx.lineWidth = lw
                                    ctx.strokeStyle = root.progressColor(percent)
                                    ctx.lineCap = "round"
                                    ctx.stroke()
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: Math.round(root.sevenDayUtil) + "%"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            StyledText {
                                text: root.tr("7-Day Usage") + " · " + Math.round(root.sevenDayUtil) + "%"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: {
                                    var parts = []
                                    if (root.weekSessions > 0) parts.push(root.weekSessions + " " + root.tr("sessions"))
                                    if (root.weekMessages > 0) parts.push(root.weekMessages + " " + root.tr("msgs"))
                                    return parts.join(" · ")
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.sevenDayCountdown ? root.tr("Resets in") + " " + root.sevenDayCountdown : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                visible: root.sevenDayCountdown !== ""
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
                                    text: root.formatTokens(root.dailyTokens[6])
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                    anchors.horizontalCenter: parent.horizontalCenter
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
                                    text: root.formatTokens(root.weekTokens)
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    anchors.horizontalCenter: parent.horizontalCenter
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
                                    text: root.formatTokens(root.monthTokens)
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    anchors.horizontalCenter: parent.horizontalCenter
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

                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: Math.max(parent.width - 4, 4)
                                                height: root.maxDaily > 0
                                                    ? Math.max(root.dailyTokens[index] / root.maxDaily * parent.height, root.dailyTokens[index] > 0 ? 3 : 0)
                                                    : 0
                                                radius: 2
                                                color: index === root.todayIndex ? Theme.primary : Theme.surfaceVariant
                                            }
                                        }

                                        StyledText {
                                            id: dayLabel
                                            text: root.dayLabels[index]
                                            font.pixelSize: 11
                                            color: index === root.todayIndex ? Theme.primary : Theme.surfaceVariantText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Model breakdown card ---
                StyledRect {
                    width: parent.width
                    height: modelCardCol.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    visible: modelListData.count > 0

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
                                model: modelListData
                                delegate: Column {
                                    width: modelCol.width
                                    spacing: 3

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingXS

                                        StyledText {
                                            text: root.shortModelName(modelName)
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            text: root.formatTokens(modelTokens)
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
                                            width: root.weekTokens > 0
                                                ? parent.width * Math.min(modelTokens / root.weekTokens, 1)
                                                : 0
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
                    visible: root.alltimeSessions > 0 || root.alltimeMessages > 0

                    Row {
                        id: allTimeRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "calendar_today"
                            size: 14
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: {
                                var parts = []
                                if (root.firstSession && root.firstSession !== "unknown")
                                    parts.push(root.tr("Since") + " " + root.firstSession)
                                parts.push(root.alltimeSessions + " " + root.tr("sessions"))
                                parts.push(root.alltimeMessages.toLocaleString() + " " + root.tr("msgs"))
                                return parts.join("  ·  ")
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Bottom padding to match sides (compensates Column spacing)
                Item { width: 1; height: 1 }
            }
        }
    }
}
