import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets
import qs.services

/*
 * What reel shows with no file open: the videos you did not finish, as cards
 * to pick up where you stopped, and everything you watched recently.
 * Both come from reeld; nothing here is kept in the window.
 */
Rectangle {
    id: root
    signal picked(string path)

    color: Appearance.colors.colLayer0Base
    property var items: []
    readonly property var unfinished: root.items.filter(i => !i.finished && i.pos > 5 && i.dur > 0)

    function refresh() { Library.recent(40, list => root.items = list); }
    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()
    Connections {
        target: Client
        function onReady() { root.refresh(); }
    }

    function ago(at) {
        const s = Date.now() / 1000 - at;
        if (s < 3600) return `${Math.max(1, Math.round(s / 60))} min ago`;
        if (s < 86400) return `${Math.round(s / 3600)} h ago`;
        if (s < 86400 * 7) return `${Math.round(s / 86400)} d ago`;
        return new Date(at * 1000).toLocaleDateString();
    }
    function dur(s) {
        if (s < 60) return `${Math.round(s)} s`;
        if (s < 3600) return `${Math.round(s / 60)} min`;
        return `${Math.floor(s / 3600)} h ${Math.round(s % 3600 / 60)} min`;
    }
    function folder(p) { const parts = p.split("/"); return parts.length > 1 ? parts[parts.length - 2] : ""; }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: 80
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: Math.max(24, (flick.width - width) / 2)
            width: Math.min(1100, flick.width - 48)
            spacing: 14

            // ── nothing yet ──
            ColumnLayout {
                visible: root.items.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 120
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "movie"
                    iconSize: 56
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Drop a video here, or open one with  reel <file>"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }

            // ── continue watching ──
            StyledText {
                visible: root.unfinished.length > 0
                text: "Continue watching"
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Flow {
                visible: root.unfinished.length > 0
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: root.unfinished.slice(0, 8)
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        property string still: ""
                        width: 250
                        height: still.length >= 0 ? 250 * 9 / 16 + 62 : 0
                        radius: Appearance.rounding.large
                        color: cardHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Component.onCompleted: Library.still(card.modelData.path, card.modelData.pos, 400, url => card.still = url)

                        Rectangle {
                            id: pic
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                            height: (card.width - 12) * 9 / 16
                            radius: Appearance.rounding.normal
                            color: "black"
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: card.still
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            // how far you got
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 4
                                color: Qt.rgba(1, 1, 1, 0.25)
                                Rectangle {
                                    height: parent.height
                                    width: parent.width * Math.min(1, card.modelData.pos / card.modelData.dur)
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 46; height: 46; radius: 23
                                color: Appearance.colors.colPrimary
                                opacity: cardHov.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "play_arrow"; fill: 1; iconSize: 28
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                        ColumnLayout {
                            anchors { left: parent.left; right: parent.right; top: pic.bottom; margins: 10; topMargin: 8 }
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.title.replace(/\.[^.]+$/, "")
                                elide: Text.ElideRight
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: `${root.dur(card.modelData.dur - card.modelData.pos)} left  ·  ${root.folder(card.modelData.path)}`
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        HoverHandler { id: cardHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.picked(card.modelData.path) }
                    }
                }
            }

            // ── recently watched ──
            StyledText {
                visible: root.items.length > 0
                Layout.topMargin: 10
                text: "Recently watched"
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Repeater {
                model: root.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: Appearance.rounding.normal
                    color: rowHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12
                        MaterialSymbol {
                            text: row.modelData.finished ? "check_circle" : "play_circle"
                            iconSize: 22
                            fill: row.modelData.finished ? 1 : 0
                            color: row.modelData.finished ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                elide: Text.ElideMiddle
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.path.replace(/\/[^\/]*$/, "")
                                elide: Text.ElideLeft
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        StyledText {
                            text: row.modelData.finished ? "Watched" : row.modelData.dur > 0 ? `${Math.round(100 * row.modelData.pos / row.modelData.dur)} %` : ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.preferredWidth: 90
                            horizontalAlignment: Text.AlignRight
                            text: root.ago(row.modelData.at)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.picked(row.modelData.path) }
                }
            }
        }
    }
}
