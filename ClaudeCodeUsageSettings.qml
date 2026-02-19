import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginSettings {
    id: root
    pluginId: "claudeCodeUsage"

    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) { return Tr.tr(key, lang) }

    StyledText {
        width: parent.width
        text: root.tr("Claude Code Usage")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.tr("Monitor your Claude Code subscription usage. Rate limits and subscription tier are detected automatically via the Anthropic API.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: root.tr("Refresh Interval")
        description: root.tr("How often to fetch usage data (seconds)")
        defaultValue: 60
        minimum: 30
        maximum: 300
        unit: "s"
        leftIcon: "schedule"
    }
}
