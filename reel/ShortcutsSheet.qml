import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets

/*
 * Every action and its keys — the cheat sheet and the editor in one.
 *
 * "+" listens for the next key and adds it; a key chip removes itself when
 * clicked. A key already used elsewhere moves here (Settings.bind takes it
 * from the other action), and the sheet says so.
 */
SidePanel {
    id: root
    title: "Keyboard shortcuts"
    icon: "keyboard"

    /// The action waiting for a key, or "".
    property string listening: ""
    property string note: ""
    readonly property int rev: Settings.s.keys ? Object.keys(Settings.s.keys).length + JSON.stringify(Settings.s.keys).length : 0

    onOpenChanged: if (!open) listening = ""

    /// Called by the window with every key while listening; true = taken.
    function capture(event) {
        if (root.listening.length === 0) return false;
        if (event.key === Qt.Key_Escape) { root.listening = ""; return true; }
        // A bare modifier is not a key yet.
        if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R].indexOf(event.key) >= 0) return true;
        const name = Settings.keyName(event);
        if (name.length === 0) return true;
        const was = Settings.actionFor(name);
        const keys = Settings.keysFor(root.listening).filter(k => k !== name).concat([name]);
        Settings.bind(root.listening, keys);
        const label = id => (Settings.actions.find(a => a.id === id) || {}).label;
        root.note = was && was !== root.listening ? `${name} moved from “${label(was)}”` : "";
        root.listening = "";
        return true;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                visible: root.note.length > 0 || root.listening.length > 0
                text: root.listening.length > 0 ? "Press a key …  (Esc cancels)" : root.note
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: ["Playback", "Sound", "Folder", "Window"]
                delegate: ColumnLayout {
                    id: group
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.topMargin: 10
                        text: group.modelData
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: Settings.actions.filter(a => a.group === group.modelData)
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property var keys: root.rev >= 0 ? Settings.keysFor(modelData.id) : []
                            readonly property bool waiting: root.listening === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: Appearance.rounding.small
                            color: row.waiting ? Appearance.colors.colSecondaryContainer
                                 : rowHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                            HoverHandler { id: rowHov }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.label
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOnLayer1
                                }
                                Repeater {
                                    model: row.keys
                                    delegate: Rectangle {
                                        id: keyChip
                                        required property string modelData
                                        implicitWidth: keyText.implicitWidth + 16
                                        implicitHeight: 26
                                        radius: 6
                                        color: chipHov.hovered ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2
                                        border.width: 1
                                        border.color: Appearance.colors.colOutlineVariant
                                        StyledText {
                                            id: keyText
                                            anchors.centerIn: parent
                                            text: keyChip.modelData
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: chipHov.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                                        }
                                        HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: Settings.bind(row.modelData.id, row.keys.filter(k => k !== keyChip.modelData))
                                        }
                                        StyledToolTip { visible: chipHov.hovered; text: "Remove this key" }
                                    }
                                }
                                IconButton {
                                    icon: "add"; size: 28; iconSize: 16
                                    tooltip: "Add a key"
                                    toggled: row.waiting
                                    onClicked: { root.note = ""; root.listening = row.waiting ? "" : row.modelData.id; }
                                }
                            }
                        }
                    }
                }
            }

            TextButton {
                Layout.topMargin: 12
                text: "Reset all keys"
                onClicked: { Settings.resetKeys(); root.note = "Every key is back to its default"; }
            }
        }
    }
}
