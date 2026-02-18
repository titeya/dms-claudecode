import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    property int refreshInterval: (pluginData.refreshInterval || 30) * 1000
    property real weeklyBudget: (pluginData.weeklyBudget || 5) * 1000000

    // Session state
    property int sessionMessages: 0
    property real sessionInput: 0
    property real sessionOutput: 0
    property real sessionCacheRead: 0
    property real sessionCacheWrite: 0
    property real sessionTotal: 0

    // Weekly state
    property int weekMessages: 0
    property int weekSessions: 0
    property int weekToolCalls: 0
    property real weekTokens: 0

    // All-time state
    property int alltimeSessions: 0
    property int alltimeMessages: 0
    property string firstSession: ""

    // Daily breakdown (Mon..Sun)
    property var dailyTokens: [0, 0, 0, 0, 0, 0, 0]

    // Model list
    ListModel { id: modelListData }

    // Adjusted daily: supplement today with live session tokens
    property int todayIndex: (new Date().getDay() + 6) % 7
    property var adjustedDaily: {
        var arr = dailyTokens.slice()
        arr[todayIndex] = arr[todayIndex] + sessionInput + sessionOutput
        return arr
    }

    // Derived
    property real weeklyPercent: weeklyBudget > 0 ? Math.min((weekTokens + sessionInput + sessionOutput) / weeklyBudget * 100, 100) : 0
    property real maxDaily: Math.max.apply(null, adjustedDaily) || 1
    property bool isLoading: true

    // Script path via PluginService
    property string scriptPath: PluginService.pluginDirectory + "/claudeCodeUsage/get-claude-usage"

    popoutWidth: 380
    popoutHeight: 560

    // --- Helpers ---

    function formatTokens(n) {
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

    function parseLine(line) {
        var idx = line.indexOf("=")
        if (idx < 0) return
        var key = line.substring(0, idx)
        var val = line.substring(idx + 1)

        switch (key) {
        case "SESSION_MESSAGES": sessionMessages = parseInt(val) || 0; break
        case "SESSION_INPUT": sessionInput = parseFloat(val) || 0; break
        case "SESSION_OUTPUT": sessionOutput = parseFloat(val) || 0; break
        case "SESSION_CACHE_READ": sessionCacheRead = parseFloat(val) || 0; break
        case "SESSION_CACHE_WRITE": sessionCacheWrite = parseFloat(val) || 0; break
        case "SESSION_TOTAL": sessionTotal = parseFloat(val) || 0; break
        case "WEEK_MESSAGES": weekMessages = parseInt(val) || 0; break
        case "WEEK_SESSIONS": weekSessions = parseInt(val) || 0; break
        case "WEEK_TOOL_CALLS": weekToolCalls = parseInt(val) || 0; break
        case "WEEK_TOKENS": weekTokens = parseFloat(val) || 0; break
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
            usageProcess.running = true
        }
    }

    // --- Taskbar pills ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Canvas {
                id: hRing
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                renderStrategy: Canvas.Cooperative

                property real percent: root.weeklyPercent
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
                text: root.formatTokens(root.weekTokens + root.sessionInput + root.sessionOutput)
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

                property real percent: root.weeklyPercent
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
                text: root.formatTokens(root.weekTokens + root.sessionInput + root.sessionOutput)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- Popout ---

    popoutContent: Component {
        PopoutComponent {
            headerText: "Claude Code Usage"
            detailsText: "Cloud subscription monitor"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // --- Weekly overview with large ring ---
                Item {
                    width: parent.width
                    height: 120

                    Canvas {
                        id: popoutRing
                        width: 100
                        height: 100
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        renderStrategy: Canvas.Cooperative

                        property real percent: root.weeklyPercent
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
                            text: Math.round(root.weeklyPercent) + "%"
                            font.pixelSize: Theme.fontSizeXLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: popoutRing.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: parent.right
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "This Week"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: root.formatTokens(root.weekTokens + root.sessionInput + root.sessionOutput) + " tokens"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.primary
                        }
                        StyledText {
                            text: root.weekSessions + " sessions · " + root.weekMessages + " msgs"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            text: root.weekToolCalls + " tool calls"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                // --- Daily activity chart ---
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Daily Activity"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        leftPadding: Theme.spacingS
                    }

                    StyledRect {
                        width: parent.width
                        height: 80
                        color: Theme.surfaceContainer

                        Row {
                            id: chartRow
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
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
                                                ? Math.max(root.adjustedDaily[index] / root.maxDaily * parent.height, root.adjustedDaily[index] > 0 ? 3 : 0)
                                                : 0
                                            radius: 2
                                            color: index === root.todayIndex ? Theme.primary : Theme.surfaceVariant
                                        }
                                    }

                                    StyledText {
                                        id: dayLabel
                                        text: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"][index]
                                        font.pixelSize: 10
                                        color: index === root.todayIndex ? Theme.primary : Theme.surfaceVariantText
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Current session ---
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Current Session"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        leftPadding: Theme.spacingS
                    }

                    StyledRect {
                        width: parent.width
                        height: sessionGrid.implicitHeight + Theme.spacingS * 2
                        color: Theme.surfaceContainer

                        Grid {
                            id: sessionGrid
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            columns: 2
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingXS

                            StyledText { text: "Messages"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: root.sessionMessages.toString(); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }

                            StyledText { text: "Input"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: root.formatTokens(root.sessionInput); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }

                            StyledText { text: "Output"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: root.formatTokens(root.sessionOutput); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }

                            StyledText { text: "Cache read"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: root.formatTokens(root.sessionCacheRead); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }

                            StyledText { text: "Cache write"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: root.formatTokens(root.sessionCacheWrite); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }

                            StyledText { text: "Total"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; font.weight: Font.Bold }
                            StyledText { text: root.formatTokens(root.sessionTotal); font.pixelSize: Theme.fontSizeSmall; color: Theme.primary; font.weight: Font.Bold }
                        }
                    }
                }

                // --- Model breakdown ---
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: modelListData.count > 0

                    StyledText {
                        text: "Models This Week"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        leftPadding: Theme.spacingS
                    }

                    StyledRect {
                        width: parent.width
                        height: modelCol.implicitHeight + Theme.spacingS * 2
                        color: Theme.surfaceContainer

                        Column {
                            id: modelCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingXS

                            Repeater {
                                model: modelListData
                                delegate: Column {
                                    width: modelCol.width - Theme.spacingS * 2
                                    spacing: 2

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

                // --- All-time footer ---
                Row {
                    width: parent.width
                    leftPadding: Theme.spacingS
                    spacing: Theme.spacingXS

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
                                parts.push("Since " + root.firstSession)
                            parts.push(root.alltimeSessions + " sessions")
                            parts.push(root.alltimeMessages.toLocaleString() + " msgs")
                            return parts.join("  ·  ")
                        }
                        font.pixelSize: 11
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
