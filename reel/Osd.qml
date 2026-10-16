import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets

/// What a key just did, for a moment, near the top of the picture:
/// "Volume 70 %", "+10 s", "Speed 1.5×". `show(icon, text)` restarts it.
Rectangle {
    id: root

    function show(icon, text) {
        root.icon = icon;
        root.text = text;
        root.opacity = 1;
        hide.restart();
    }
    property string icon: ""
    property string text: ""

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 44
    radius: Appearance.rounding.full
    color: Qt.rgba(0, 0, 0, 0.62)
    opacity: 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10
        MaterialSymbol {
            text: root.icon
            iconSize: 22
            fill: 1
            color: Appearance.colors.colPrimary
        }
        StyledText {
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: "#ffffff"
        }
    }
    Timer { id: hide; interval: 1100; onTriggered: root.opacity = 0 }
}
