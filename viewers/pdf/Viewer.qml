import QtQuick
import QtQuick.Controls
import QtQuick.Pdf
import QtQuick.LocalStorage

/*
 * PDF — Qt's own renderer (QtQuick.Pdf), no external program.
 *
 * ← → pages, Alt+← → the next PDF in the folder, + − zoom, W fit width,
 * Ctrl+F search (Enter / Shift+Enter: next / previous hit). Each document
 * opens on the page you left it on.
 */
FocusScope {
    id: v
    property string path: ""
    property color fg: "white"
    property color dim: "#aaffffff"
    property color accent: "#8ab4f8"
    property color panel: "#e61a1a1a"
    signal step(int delta)
    focus: true

    // ── where each document was left ──
    function db() { return LocalStorage.openDatabaseSync("reel-pdf", "1", "pages left", 100000); }
    function savedPage(p) {
        let n = 0;
        try { db().transaction(tx => { tx.executeSql("CREATE TABLE IF NOT EXISTS left(path TEXT PRIMARY KEY, page INT)"); const r = tx.executeSql("SELECT page FROM left WHERE path=?", [p]); if (r.rows.length) n = r.rows.item(0).page; }); } catch (e) {}
        return n;
    }
    function savePage(p, n) {
        try { db().transaction(tx => { tx.executeSql("CREATE TABLE IF NOT EXISTS left(path TEXT PRIMARY KEY, page INT)"); tx.executeSql("INSERT OR REPLACE INTO left VALUES(?, ?)", [p, n]); }); } catch (e) {}
    }

    PdfDocument {
        id: doc
        source: v.path ? "file://" + v.path : ""
        onStatusChanged: if (doc.status === PdfDocument.Ready) Qt.callLater(() => { view.scaleToWidth(view.width, view.height); const n = v.savedPage(v.path); if (n > 0 && n < pageCount) view.goToPage(n); })
    }
    Rectangle { anchors.fill: parent; color: "#2a2a2e" }

    PdfMultiPageView {
        id: view
        anchors { fill: parent; topMargin: 48 }
        document: doc
        searchString: search.text
        onCurrentPageChanged: if (v.path) v.savePage(v.path, currentPage)
    }

    Keys.onPressed: (e) => {
        const k = e.key, alt = e.modifiers & Qt.AltModifier, ctrl = e.modifiers & Qt.ControlModifier;
        if (alt && k === Qt.Key_Right) v.step(1);
        else if (alt && k === Qt.Key_Left) v.step(-1);
        else if (ctrl && k === Qt.Key_F) { search.forceActiveFocus(); search.selectAll(); }
        else if (k === Qt.Key_Right || k === Qt.Key_PageDown) view.goToPage(Math.min(doc.pageCount - 1, view.currentPage + 1));
        else if (k === Qt.Key_Left || k === Qt.Key_PageUp) view.goToPage(Math.max(0, view.currentPage - 1));
        else if (k === Qt.Key_Home) view.goToPage(0);
        else if (k === Qt.Key_End) view.goToPage(doc.pageCount - 1);
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) view.renderScale *= 1.2;
        else if (k === Qt.Key_Minus) view.renderScale /= 1.2;
        else if (k === Qt.Key_W) view.scaleToWidth(view.width, view.height);
        else { e.accepted = false; return; }
        e.accepted = true;
    }

    // ── the bar ──
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 48
        color: v.panel
        Row {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: doc.title || v.path.split("/").pop(); color: v.fg; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, v.width * 0.35) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: doc.pageCount > 0 ? `page ${view.currentPage + 1} of ${doc.pageCount}` : (doc.status === PdfDocument.Error ? "cannot be read" : "opening…"); color: v.dim; font.pixelSize: 12 }
        }
        Row {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 6
            component Btn: Rectangle {
                id: b
                property string label
                signal clicked()
                width: Math.max(32, bt.implicitWidth + 18); height: 32; radius: 16
                color: bh.hovered ? Qt.alpha(v.fg, 0.14) : Qt.alpha(v.fg, 0.06)
                Text { id: bt; anchors.centerIn: parent; text: b.label; color: v.fg; font.pixelSize: 14 }
                HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { b.clicked(); v.forceActiveFocus(); } }
            }
            Btn { label: "−"; onClicked: view.renderScale /= 1.2 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: Math.round(view.renderScale * 100) + " %"; color: v.dim; font.pixelSize: 12; width: 46; horizontalAlignment: Text.AlignHCenter }
            Btn { label: "+"; onClicked: view.renderScale *= 1.2 }
            Btn { label: "Fit width"; onClicked: view.scaleToWidth(view.width, view.height) }
            // search: hits highlighted on the pages
            Rectangle {
                width: 220; height: 32; radius: 16
                color: Qt.alpha(v.fg, 0.06)
                border.width: search.activeFocus ? 1 : 0; border.color: v.accent
                TextInput {
                    id: search
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: v.fg; font.pixelSize: 13
                    Keys.onReturnPressed: (e) => { if (e.modifiers & Qt.ShiftModifier) view.searchBack(); else view.searchForward(); }
                    Keys.onEscapePressed: { text = ""; v.forceActiveFocus(); }
                    Text { visible: !search.text && !search.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "Search (Ctrl+F)"; color: v.dim; font.pixelSize: 13 }
                }
            }
        }
    }
}
