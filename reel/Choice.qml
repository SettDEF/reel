import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets

/// A small set of options as chips; the current one filled with the accent.
///   Choice { options: [{ "value": "fit", "label": "Fit" }, …]; current: x; onPicked: v => … }
Flow {
    id: root
    property var options: []
    property var current
    signal picked(var value)
    spacing: 6

    Repeater {
        model: root.options
        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool on: root.current === modelData.value
            width: label.implicitWidth + 22
            height: 30
            radius: Appearance.rounding.full
            color: chip.on ? Appearance.colors.colPrimary
                 : hov.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
            Behavior on color { ColorAnimation { duration: 120 } }
            StyledText {
                id: label
                anchors.centerIn: parent
                text: chip.modelData.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: chip.on ? Font.DemiBold : Font.Normal
                color: chip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(chip.modelData.value) }
        }
    }
}
