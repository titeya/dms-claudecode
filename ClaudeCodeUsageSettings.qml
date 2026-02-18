import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "claudeCodeUsage"

    StyledText {
        width: parent.width
        text: "Claude Code Usage"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Monitor your Claude Code subscription usage with session and weekly token tracking."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "How often to fetch usage data (seconds)"
        defaultValue: 30
        minimum: 10
        maximum: 120
        unit: "s"
        leftIcon: "schedule"
    }

    SliderSetting {
        settingKey: "weeklyBudget"
        label: "Weekly Token Budget"
        description: "Weekly token target in millions (sets the 100% mark on the progress ring)"
        defaultValue: 5
        minimum: 1
        maximum: 100
        unit: "M"
        leftIcon: "data_usage"
    }
}
