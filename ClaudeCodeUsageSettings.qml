import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginSettings {
    id: root
    pluginId: "claudeCodeUsage"

    property string lang: (SessionData.locale || Qt.locale().name).split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

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
        description: root.tr("How often to fetch usage data (minutes)")
        defaultValue: 2
        minimum: 2
        maximum: 15

        unit: "min"
        leftIcon: "schedule"
    }

    ToggleSetting {
        settingKey: "showPacing"
        label: root.tr("Show pacing")
        description: root.tr("Show whether usage is ahead of or behind the time window")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "countBridged"
        label: root.tr("Count other clients")
        description: root.tr("Also count agents that reach this subscription through a bridge, not only Claude Code")
        defaultValue: true
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    Column {
        id: customProfilesSetting

        width: parent.width
        spacing: Theme.spacingM

        property var items: []
        property bool isLoading: false
        readonly property real nameColumnWidth: Math.min(130, Math.max(100, width * 0.27))
        readonly property real actionWidth: 92

        Component.onCompleted: loadValue()

        function loadValue() {
            isLoading = true;
            items = root.loadValue("customProfiles", []);
            isLoading = false;
        }

        function saveItems(newItems) {
            items = newItems;
            if (!isLoading)
                root.saveValue("customProfiles", items);
        }

        function addItem() {
            var name = profileNameInput.text.trim();
            var path = profilePathInput.text.trim();
            if (!name || !path)
                return;

            saveItems(items.concat([{
                name: name,
                path: path
            }]));
            profileNameInput.text = "";
            profilePathInput.text = "";
            profileNameInput.forceActiveFocus();
        }

        function removeItem(index) {
            var updatedItems = items.slice();
            updatedItems.splice(index, 1);
            saveItems(updatedItems);
        }

        StyledText {
            text: root.tr("Custom Profiles")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: root.tr("Track extra Claude config directories. Point at a CLAUDE_CONFIG_DIR (the folder containing projects/). ~/.claude, Claude Code Switcher and claude-code-profiles are detected automatically.")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: customProfilesSetting.nameColumnWidth
                text: root.tr("Name")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width - customProfilesSetting.nameColumnWidth - customProfilesSetting.actionWidth - parent.spacing * 2
                text: root.tr("Config directory")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            Item {
                width: customProfilesSetting.actionWidth
                height: 1
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankTextField {
                id: profileNameInput
                width: customProfilesSetting.nameColumnWidth
                placeholderText: "work"
                Keys.onReturnPressed: customProfilesSetting.addItem()
            }

            DankTextField {
                id: profilePathInput
                width: parent.width - customProfilesSetting.nameColumnWidth - customProfilesSetting.actionWidth - parent.spacing * 2
                placeholderText: "~/.ccp/data/work"
                Keys.onReturnPressed: customProfilesSetting.addItem()
            }

            DankButton {
                width: customProfilesSetting.actionWidth
                height: 40
                text: root.tr("Add")
                onClicked: customProfilesSetting.addItem()
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingS

            Repeater {
                model: customProfilesSetting.items

                StyledRect {
                    required property int index
                    required property var modelData

                    width: parent.width
                    height: 44
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                    border.width: 0

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS

                        StyledText {
                            width: customProfilesSetting.nameColumnWidth
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name || ""
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width - customProfilesSetting.nameColumnWidth - customProfilesSetting.actionWidth - parent.spacing * 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.path || ""
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideMiddle
                        }

                        Rectangle {
                            width: customProfilesSetting.actionWidth
                            height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            color: removeArea.containsMouse ? Theme.errorHover : Theme.error
                            radius: Theme.cornerRadius

                            StyledText {
                                anchors.centerIn: parent
                                text: root.tr("Remove")
                                color: Theme.onError
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: removeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: customProfilesSetting.removeItem(index)
                            }
                        }
                    }
                }
            }

            StyledText {
                text: root.tr("No items added yet")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                visible: customProfilesSetting.items.length === 0
            }
        }
    }
}
