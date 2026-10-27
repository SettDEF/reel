import QtQuick
import QtQuick.Controls

/*
 * TEXT — Markdown rendered, everything else as it is (monospace), JSON
 * pretty-printed. Read-only and selectable. + − change the size, ← → the
 * next file of the kind in the folder. Big files stop at 4 MB, and say so.
 * (Reads through XMLHttpRequest: reel sets QML_XHR_ALLOW_FILE_READ.)
 */
FocusScope {
    id: v
    property string path: ""
    property color fg: "white"
    property color dim: "#aaffffff"
    property color accent: "#8ab4f8"
    property color panel: "#1a1a1a"
    signal step(int delta)
    focus: true

    readonly property string ext: v.path.split(".").pop().toLowerCase()
    readonly property bool markdown: v.ext === "md" || v.ext === "markdown"
    property string body: ""
    property bool cut: false
    property int size: 15
    readonly property int limit: 4 * 1024 * 1024

    onPathChanged: {
        v.body = ""; v.cut = false;
        if (!v.path) return;
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            let t = x.responseText ?? "";
            if (t.length > v.limit) { t = t.slice(0, v.limit); v.cut = true; }
            if (v.ext === "json") { try { t = JSON.stringify(JSON.parse(t), null, 2); } catch (e) {} }
            v.body = t;
            flick.contentY = 0;
        };
        x.open("GET", "file://" + v.path);
        x.send();
    }

    Keys.onPressed: (e) => {
        const k = e.key;
        if (k === Qt.Key_Right && !(e.modifiers & Qt.ShiftModifier)) v.step(1);
        else if (k === Qt.Key_Left && !(e.modifiers & Qt.ShiftModifier)) v.step(-1);
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) v.size = Math.min(40, v.size + 1);
        else if (k === Qt.Key_Minus) v.size = Math.max(9, v.size - 1);
        else if (k === Qt.Key_Home) flick.contentY = 0;
        else if (k === Qt.Key_End) flick.contentY = Math.max(0, flick.contentHeight - flick.height);
        else { e.accepted = false; return; }
        e.accepted = true;
    }

    Rectangle { anchors.fill: parent; color: v.panel }

    Flickable {
        id: flick
        anchors { fill: parent; topMargin: 44 }
        contentWidth: width
        contentHeight: txt.implicitHeight + 60
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        TextEdit {
            id: txt
            x: Math.max(24, (flick.width - width) / 2)
            y: 24
            width: Math.min(flick.width - 48, v.markdown ? 860 : 1200)
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: v.markdown ? TextEdit.MarkdownText : TextEdit.PlainText
            text: v.body
            color: v.fg
            selectionColor: v.accent
            font.family: v.markdown ? "sans-serif" : "monospace"
            font.pixelSize: v.size
            onLinkActivated: (l) => Qt.openUrlExternally(l)
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 44
        color: Qt.darker(v.panel, 1.3)
        Text {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: v.path.split("/").pop() + (v.cut ? "   ·   only the first 4 MB" : "") + `   ·   ${v.body.split("\n").length} lines`
            color: v.dim
            font.pixelSize: 13
        }
    }
}
