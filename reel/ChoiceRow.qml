import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets

/// A setting with a few options: the label on top, the options underneath at
/// the full width — so neither has to be cut short to fit beside the other.
ColumnLayout {
    id: root
    property string icon: ""
    property string label: ""
    property string description: ""
    property var options: []
    property var current
    signal picked(var value)

    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 6
    Layout.bottomMargin: 8
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        MaterialSymbol {
            visible: root.icon.length > 0
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            text: root.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }
    }
    Choice {
        Layout.fillWidth: true
        Layout.leftMargin: root.icon.length > 0 ? 32 : 0
        options: root.options
        current: root.current
        onPicked: v => root.picked(v)
    }
}
