import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.widgets

/*
 * The window buttons ii-decor draws on every other window — minimize,
 * maximize, close as coloured dots — for a window that draws its own bar.
 *
 * The colours are read from ii-decor's own config, so they follow whatever
 * the shell's Glass settings wrote there; the glyphs appear while the pointer
 * is over the group, as on the real bar.
 */
Row {
    id: root

    /// "minimize" | "maximize" | "fullscreen" | "close"
    signal pressed(string action)

    property real dot: 13
    spacing: 8

    property var decor: ({})
    FileView {
        path: `${Quickshell.env("HOME")}/.config/hypr/ii-decor.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.decor = JSON.parse(text()); } catch (e) {} }
    }

    /// ii-decor writes "rgb(ffb4ab)" / "rgba(ffb4abff)".
    function hyprColor(s, fallback) {
        const m = /^rgba?\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})?\)$/.exec(String(s || ""));
        return m ? "#" + (m[2] || "ff") + m[1] : fallback;
    }

    readonly property var buttons: [
        { "id": "minimize", "glyph": "remove", "tip": "Minimize",
          "color": root.hyprColor(root.decor.colors?.minimize, Appearance.colors.colTertiary) },
        { "id": "fullscreen", "glyph": "add", "tip": "Fullscreen  (f)",
          "color": root.hyprColor(root.decor.colors?.maximize, Appearance.colors.colPrimary) },
        { "id": "close", "glyph": "close", "tip": "Close  (q)",
          "color": root.hyprColor(root.decor.colors?.close, Appearance.colors.colError) },
    ]

    HoverHandler { id: groupHover }

    Repeater {
        model: root.buttons
        delegate: Rectangle {
            id: d
            required property var modelData
            width: root.dot
            height: root.dot
            radius: width / 2
            color: modelData.color
            scale: ma.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }

            MaterialSymbol {
                anchors.centerIn: parent
                text: d.modelData.glyph
                iconSize: root.dot - 3
                fill: 1
                color: Qt.rgba(0, 0, 0, 0.62)
                opacity: groupHover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pressed(d.modelData.id)
            }
            StyledToolTip {
                visible: ma.containsMouse
                text: d.modelData.tip
            }
        }
    }
}
