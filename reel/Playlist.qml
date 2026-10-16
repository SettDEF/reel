import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets

/*
 * The folder as a playlist: every video next to the open one, in natural
 * order, each with a still and how far you got.
 */
SidePanel {
    id: root
    title: Library.files.length > 1 ? `In this folder  ·  ${Library.index + 1} / ${Library.files.length}` : "In this folder"
    icon: "playlist_play"

    signal picked(string path)

    function dur(s) {
        if (s < 60) return `${Math.round(s)} s`;
        if (s < 3600) return `${Math.round(s / 60)} min`;
        return `${Math.floor(s / 3600)} h ${Math.round(s % 3600 / 60)} min`;
    }

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 4
            model: Library.files
            currentIndex: Library.index
            boundsBehavior: Flickable.StopAtBounds
            Component.onCompleted: positionViewAtIndex(Library.index, ListView.Center)

            delegate: Rectangle {
                id: row
                required property string modelData
                required property int index
                readonly property bool current: row.index === Library.index
                readonly property var prog: Library.progressRevision >= 0 ? Library.progress[row.modelData] : null
                property string still: ""

                width: ListView.view.width
                height: 64
                radius: Appearance.rounding.normal
                color: row.current ? Appearance.colors.colSecondaryContainer
                     : hov.hovered ? Appearance.colors.colLayer1Hover : "transparent"

                Component.onCompleted: if (Settings.s.playlistThumbs) Library.thumb(row.modelData, url => row.still = url)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 10

                    // the still, with the watched share along its bottom edge
                    Rectangle {
                        visible: Settings.s.playlistThumbs
                        Layout.preferredWidth: 92
                        Layout.preferredHeight: 52
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: row.still
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            height: 3
                            width: parent.width * (row.prog && row.prog.dur > 0 ? (row.prog.finished ? 1 : row.prog.pos / row.prog.dur) : 0)
                            color: Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.split("/").pop()
                            elide: Text.ElideMiddle
                            color: row.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            font.weight: row.current ? Font.DemiBold : Font.Normal
                        }
                        StyledText {
                            text: !row.prog || !(row.prog.dur > 0) ? ""
                                : row.prog.finished ? "Watched"
                                : row.prog.pos > 0 ? `${Math.round(100 * row.prog.pos / row.prog.dur)} % · ${root.dur(row.prog.dur)}`
                                : root.dur(row.prog.dur)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.picked(row.modelData) }
            }
        }
}
