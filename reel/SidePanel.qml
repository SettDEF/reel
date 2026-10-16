import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets

/// The frame every sheet in reel shares: a card at one side of the window
/// with a heading and a close button. Content goes in as children.
Rectangle {
    id: root

    property string title: ""
    property string icon: ""
    property bool open: false
    /// "right" | "left"
    property string side: "right"
    default property alias content: body.data
    /// A subpage is showing: the heading gets a back arrow.
    property bool canGoBack: false
    /// "solid" | "glass" — glass lets the picture show through.
    property string look: "solid"
    signal closed()
    signal back()

    readonly property real margin: 10
    width: Math.min(400, parent.width * 0.45)
    x: root.side === "left"
        ? (root.open ? root.margin : -width - root.margin)
        : (root.open ? parent.width - width - root.margin : parent.width + root.margin)
    visible: root.side === "left" ? x + width > 0 : x < parent.width
    Behavior on x { NumberAnimation { duration: Appearance.animDur(220); easing.type: Easing.OutCubic } }

    color: root.look === "glass" ? Qt.rgba(Appearance.colors.colLayer1.r, Appearance.colors.colLayer1.g, Appearance.colors.colLayer1.b, 0.78) : Appearance.colors.colLayer1
    radius: Appearance.rounding.large
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    // Clicks inside never reach the picture underneath (pause, fullscreen …).
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconButton {
                visible: root.canGoBack
                icon: "arrow_back"; size: 30; tooltip: "Back"
                onClicked: root.back()
            }
            MaterialSymbol {
                visible: root.icon.length > 0 && !root.canGoBack
                text: root.icon
                iconSize: 20
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            IconButton {
                icon: "close"; size: 30; tooltip: "Close  (Esc)"
                onClicked: root.closed()
            }
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
