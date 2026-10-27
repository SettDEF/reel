import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.widgets
import qs.services

/*
 * What reel shows with no file open, laid out like the other apps of this
 * desktop (Vitals, Kalends, Dotos): a sidebar with the library's views and
 * the folders you watch from, a page toolbar that sits BELOW the compositor's
 * window-button pill, the page, and a status bar.
 *
 * Everything comes from reeld (recent + progress); nothing is kept here
 * except which view, folder, search and layout are showing.
 */
Rectangle {
    id: root
    signal picked(string path)
    /// a reel action by id ("settings", "shortcuts", …), run by the shell
    signal action(string id)

    color: Appearance.colors.colLayer0Base
    property var items: []
    property bool loaded: false

    // what is showing
    property string view: "home"          // home | continue | watched | all
    property string folderFilter: ""      // a folder path, or "" for all
    property string search: ""
    property string layout: "grid"        // grid | list

    function refresh() { Library.recent(200, list => { root.items = list; root.loaded = true; }); }
    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()
    Connections {
        target: Client
        function onReady() { root.refresh(); }
    }

    // ── helpers ──
    function ago(at) {
        const s = Date.now() / 1000 - at;
        if (s < 3600) return `${Math.max(1, Math.round(s / 60))} min ago`;
        if (s < 86400) return `${Math.round(s / 3600)} h ago`;
        if (s < 86400 * 7) return `${Math.round(s / 86400)} d ago`;
        return new Date(at * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }
    function dur(s) {
        if (!(s > 0)) return "—";
        if (s < 60) return `${Math.round(s)} s`;
        if (s < 3600) return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;
        return `${Math.floor(s / 3600)}:${String(Math.floor(s % 3600 / 60)).padStart(2, "0")}:${String(Math.round(s % 60)).padStart(2, "0")}`;
    }
    function dirOf(p) { return p.replace(/\/[^\/]*$/, ""); }
    function baseName(p) { const parts = p.split("/"); return parts[parts.length - 1] || p; }
    function name(i) { return (i.title || root.baseName(i.path)).replace(/\.[^.]+$/, ""); }
    function isUnfinished(i) { return !i.finished && i.pos > 5 && i.dur > 0; }
    function progress(i) { return i.finished ? 1 : i.dur > 0 ? Math.min(1, i.pos / i.dur) : 0; }

    readonly property var unfinished: root.items.filter(i => root.isUnfinished(i))
    readonly property var watched: root.items.filter(i => i.finished)
    /// folders by how many of their videos you watched, most first
    readonly property var folders: {
        const m = {};
        for (const i of root.items) { const d = root.dirOf(i.path); m[d] = (m[d] ?? 0) + 1; }
        return Object.keys(m).map(d => ({ path: d, n: m[d] })).sort((a, b) => b.n - a.n).slice(0, 8);
    }
    /// what the page lists, after view, folder and search
    readonly property var shown: {
        let l = root.view === "continue" ? root.unfinished
            : root.view === "watched" ? root.watched : root.items;
        if (root.folderFilter) l = l.filter(i => root.dirOf(i.path) === root.folderFilter);
        const q = root.search.trim().toLowerCase();
        if (q) l = l.filter(i => i.path.toLowerCase().includes(q));
        return l;
    }
    readonly property string pageTitle: root.folderFilter ? root.baseName(root.folderFilter)
        : ({ home: "Library", continue: "Continue watching", watched: "Watched", all: "All videos" })[root.view]

    // Open… : the desktop's own file picker
    Process {
        id: picker
        command: ["zenity", "--file-selection", "--title=Open in Reel",
                  "--file-filter=Videos and pictures | *.mp4 *.mkv *.webm *.mov *.avi *.m4v *.gif *.png *.jpg *.jpeg *.webp *.pdf",
                  "--file-filter=All files | *"]
        stdout: StdioCollector { onStreamFinished: { const p = this.text.trim(); if (p) root.picked(p); } }
    }

    // ── a thumbnail that asks reeld for a still once, when first shown ──
    component Still: Rectangle {
        id: st
        property var item
        property string url: ""
        color: Qt.rgba(0, 0, 0, 0.35)
        clip: true
        Component.onCompleted: {
            const i = st.item;
            // where you stopped, for unfinished ones; a tenth in otherwise
            const at = root.isUnfinished(i) ? i.pos : (i.dur > 0 ? i.dur * 0.1 : 1);
            Library.still(i.path, at, 480, u => st.url = u);
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: "movie"; iconSize: 28
            color: Qt.alpha(Appearance.colors.colOnLayer1, 0.25)
        }
        Image {
            id: img
            anchors.fill: parent
            source: st.url
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 480
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }

    // ── sidebar entry ──
    component Entry: Rectangle {
        id: entry
        property string icon: ""
        property string label: ""
        property int count: -1
        property bool sel: false
        signal hit()
        Layout.fillWidth: true
        implicitHeight: 38
        radius: Appearance.rounding.small
        color: entry.sel ? Qt.alpha(Appearance.colors.colPrimary, 0.16)
            : entryHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: entryHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: entry.hit() }
        Rectangle {
            visible: entry.sel
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 3; height: 18; radius: 1.5
            color: Appearance.colors.colPrimary
        }
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
            spacing: 10
            MaterialSymbol {
                text: entry.icon; iconSize: 20; fill: entry.sel ? 1 : 0
                color: entry.sel ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: entry.label
                elide: Text.ElideRight
                font.weight: entry.sel ? Font.DemiBold : Font.Normal
                color: entry.sel ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer0
            }
            StyledText {
                visible: entry.count >= 0
                text: String(entry.count)
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    component SectionLabel: StyledText {
        Layout.topMargin: 14
        Layout.leftMargin: 12
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
        color: Appearance.colors.colSubtext
    }

    // ── a video card (grid) ──
    component Card: Rectangle {
        id: card
        required property var modelData
        width: grid.cellWidth - 14
        height: grid.cellHeight - 14
        radius: Appearance.rounding.normal
        color: cardHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        border.width: 1
        border.color: cardHov.hovered ? Qt.alpha(Appearance.colors.colPrimary, 0.5) : Appearance.colors.colOutlineVariant
        Behavior on color { ColorAnimation { duration: 120 } }
        Still {
            id: pic
            item: card.modelData
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            height: (card.width - 2) * 9 / 16
            radius: Appearance.rounding.normal
            topLeftRadius: Appearance.rounding.normal; topRightRadius: Appearance.rounding.normal
            bottomLeftRadius: 0; bottomRightRadius: 0
            // length, bottom right, as on every video site
            Rectangle {
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                visible: card.modelData.dur > 0
                width: lenText.implicitWidth + 10; height: 20; radius: 5
                color: Qt.rgba(0, 0, 0, 0.72)
                StyledText {
                    id: lenText
                    anchors.centerIn: parent
                    text: root.dur(card.modelData.dur)
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: "white"
                }
            }
            Rectangle {
                visible: card.modelData.finished
                anchors { left: parent.left; top: parent.top; margins: 8 }
                width: watchedRow.implicitWidth + 12; height: 22; radius: 11
                color: Qt.rgba(0, 0, 0, 0.72)
                RowLayout {
                    id: watchedRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol { text: "check"; iconSize: 14; color: "white" }
                    StyledText { text: "Watched"; font.pixelSize: Appearance.font.pixelSize.smallest; color: "white" }
                }
            }
            // how far you got
            Rectangle {
                visible: !card.modelData.finished && card.modelData.pos > 5
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 4
                color: Qt.rgba(1, 1, 1, 0.22)
                Rectangle {
                    height: parent.height
                    width: parent.width * root.progress(card.modelData)
                    color: Appearance.colors.colPrimary
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 48; height: 48; radius: 24
                color: Appearance.colors.colPrimary
                opacity: cardHov.hovered ? 1 : 0
                scale: cardHov.hovered ? 1 : 0.85
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"; fill: 1; iconSize: 30
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
        ColumnLayout {
            anchors { left: parent.left; right: parent.right; top: pic.bottom; margins: 12; topMargin: 10 }
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.name(card.modelData)
                elide: Text.ElideRight
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: [root.isUnfinished(card.modelData) ? `${root.dur(card.modelData.dur - card.modelData.pos)} left` : "",
                       root.baseName(root.dirOf(card.modelData.path)), root.ago(card.modelData.at)]
                    .filter(s => s.length > 0).join("  ·  ")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        HoverHandler { id: cardHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.picked(card.modelData.path) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.openMenu(card.modelData, card) }
    }

    // ── right-click menu on a video ──
    property var menuItem: null
    function openMenu(item, anchorItem) {
        root.menuItem = item;
        const at = anchorItem.mapToItem(root, anchorItem.width / 2, 40);
        itemMenu.x = Math.max(10, Math.min(root.width - itemMenu.width - 10, at.x - itemMenu.width / 2));
        itemMenu.y = Math.min(root.height - 200, at.y);
        itemMenu.open();
    }
    MenuPopup {
        id: itemMenu
        minWidth: 230
        MenuRow { text: root.menuItem && root.isUnfinished(root.menuItem) ? "Resume" : "Play"; icon: "play_arrow"; onTriggered: { itemMenu.close(); root.picked(root.menuItem.path); } }
        MenuRow { text: "Show this folder"; icon: "folder"; onTriggered: { itemMenu.close(); root.folderFilter = root.dirOf(root.menuItem.path); root.view = "all"; } }
        MenuRow { text: "Open folder in Files"; icon: "folder_open"; onTriggered: { itemMenu.close(); Qt.openUrlExternally("file://" + root.dirOf(root.menuItem.path)); } }
        MenuRow { separator: true }
        MenuRow { text: "Remove from history"; icon: "delete"; destructive: true; onTriggered: { itemMenu.close(); Library.forget(root.menuItem.path); root.items = root.items.filter(i => i.path !== root.menuItem.path); } }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ───────────────────────── sidebar ─────────────────────────
        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 248
            color: Appearance.colors.colLayer1Base

            ColumnLayout {
                anchors { fill: parent; margins: 12; topMargin: 16 }
                spacing: 2

                // the app
                RowLayout {
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 12
                    spacing: 10
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 34; radius: 10
                        color: Appearance.colors.colPrimaryContainer
                        MaterialSymbol { anchors.centerIn: parent; text: "movie"; fill: 1; iconSize: 20; color: Appearance.colors.colOnPrimaryContainer }
                    }
                    ColumnLayout {
                        spacing: 0
                        StyledText { text: "Reel"; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                        StyledText { text: "Player · Viewer"; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                    }
                }

                // Open…
                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: openHov.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol { text: "file_open"; iconSize: 19; color: Appearance.colors.colOnPrimary }
                        StyledText { text: "Open file…"; font.weight: Font.DemiBold; color: Appearance.colors.colOnPrimary }
                    }
                    HoverHandler { id: openHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: picker.running = true }
                }

                Entry { icon: "home"; label: "Library"; sel: root.view === "home" && !root.folderFilter; onHit: { root.view = "home"; root.folderFilter = ""; } }
                Entry { icon: "play_circle"; label: "Continue watching"; count: root.unfinished.length; sel: root.view === "continue" && !root.folderFilter; onHit: { root.view = "continue"; root.folderFilter = ""; } }
                Entry { icon: "check_circle"; label: "Watched"; count: root.watched.length; sel: root.view === "watched" && !root.folderFilter; onHit: { root.view = "watched"; root.folderFilter = ""; } }
                Entry { icon: "history"; label: "History"; count: root.items.length; sel: root.view === "all" && !root.folderFilter; onHit: { root.view = "all"; root.folderFilter = ""; } }

                SectionLabel { visible: root.folders.length > 0; text: "FOLDERS" }
                Repeater {
                    model: root.folders
                    delegate: Entry {
                        required property var modelData
                        icon: "folder"
                        label: root.baseName(modelData.path)
                        count: modelData.n
                        sel: root.folderFilter === modelData.path
                        onHit: { root.folderFilter = modelData.path; root.view = "all"; }
                    }
                }

                Item { Layout.fillHeight: true }

                Entry { icon: "keyboard"; label: "Keyboard shortcuts"; onHit: root.action("shortcuts") }
                Entry { icon: "tune"; label: "Settings"; onHit: root.action("settings") }
            }
            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Appearance.colors.colOutlineVariant; opacity: 0.6 }
        }

        // ───────────────────────── the page ─────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // toolbar: title left, tools in a row BELOW the window-button pill
            Item {
                Layout.fillWidth: true
                implicitHeight: 74
                ColumnLayout {
                    anchors { left: parent.left; right: tools.left; verticalCenter: parent.verticalCenter; leftMargin: 24; rightMargin: 16 }
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: root.pageTitle
                        elide: Text.ElideRight
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.folderFilter ? root.folderFilter
                            : `${root.shown.length} ${root.shown.length === 1 ? "video" : "videos"}${root.search ? "  ·  matching “" + root.search + "”" : ""}`
                        elide: Text.ElideLeft
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
                RowLayout {
                    id: tools
                    // the pill: top 4 px, 22 px tall, at the right edge
                    anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 32 }
                    height: 36
                    spacing: 6
                    MaterialTextField {
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 36
                        leadingIcon: "search"
                        placeholder: "Search history"
                        onEdited: t => root.search = t
                        onCleared: root.search = ""
                    }
                    Rectangle {
                        implicitWidth: 76; implicitHeight: 36
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer1
                        border.width: 1; border.color: Appearance.colors.colOutlineVariant
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            IconButton { icon: "grid_view"; size: 32; iconSize: 18; tooltip: "Cards"; toggled: root.layout === "grid"; onClicked: root.layout = "grid" }
                            IconButton { icon: "view_list"; size: 32; iconSize: 18; tooltip: "List"; toggled: root.layout === "list"; onClicked: root.layout = "list" }
                        }
                    }
                    IconButton { icon: "refresh"; size: 36; tooltip: "Reload"; onClicked: root.refresh() }
                }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Appearance.colors.colOutlineVariant; opacity: 0.6 }
            }

            // ── page body ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // nothing watched yet
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.loaded && root.items.length === 0
                    spacing: 10
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 84; implicitHeight: 84; radius: 26
                        color: Appearance.colors.colPrimaryContainer
                        MaterialSymbol { anchors.centerIn: parent; text: "movie"; fill: 1; iconSize: 42; color: Appearance.colors.colOnPrimaryContainer }
                    }
                    StyledText { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6; text: "Nothing watched yet"; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                    StyledText { Layout.alignment: Qt.AlignHCenter; text: "Open a file, drop one on the window, or run  reel <file>"; color: Appearance.colors.colSubtext }
                }
                // a search or folder with no match
                StyledText {
                    anchors.centerIn: parent
                    visible: root.items.length > 0 && root.shown.length === 0
                    text: root.search ? `Nothing matches “${root.search}”` : "Nothing here yet"
                    color: Appearance.colors.colSubtext
                }

                // ── grid ──
                GridView {
                    id: grid
                    anchors { fill: parent; leftMargin: 17; rightMargin: 3; topMargin: 10 }
                    visible: root.layout === "grid" && root.shown.length > 0
                    clip: true
                    readonly property int cols: Math.max(1, Math.floor(width / 270))
                    cellWidth: Math.floor(width / cols)
                    cellHeight: (cellWidth - 16) * 9 / 16 + 80
                    cacheBuffer: cellHeight * 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.shown
                    // the header grows once the history arrives; without this the
                    // view stays scrolled past it and the resume row never shows
                    onModelChanged: Qt.callLater(grid.positionViewAtBeginning)
                    // the Library page leads with what you can pick up again
                    header: Item {
                        width: grid.width
                        height: contRow.visible ? contRow.height + 36 : 0
                        ColumnLayout {
                            id: contRow
                            visible: root.view === "home" && !root.folderFilter && !root.search && root.unfinished.length > 0
                            width: parent.width - 14
                            spacing: 10
                            RowLayout {
                                Layout.topMargin: 6
                                StyledText { text: "Pick up where you left off"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                                Item { Layout.fillWidth: true }
                                StyledText {
                                    text: "See all"
                                    color: seeAllHov.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    HoverHandler { id: seeAllHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.view = "continue" }
                                }
                            }
                            // wide "resume" tiles: picture left, what is left right
                            Flow {
                                Layout.fillWidth: true
                                spacing: 12
                                Repeater {
                                    model: root.unfinished.slice(0, Math.max(2, Math.floor((contRow.width + 12) / 372)))
                                    delegate: Rectangle {
                                        id: rt
                                        required property var modelData
                                        width: 360; height: 104
                                        radius: Appearance.rounding.normal
                                        color: rtHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                                        border.width: 1
                                        border.color: rtHov.hovered ? Qt.alpha(Appearance.colors.colPrimary, 0.5) : Appearance.colors.colOutlineVariant
                                        Still {
                                            id: rtPic
                                            item: rt.modelData
                                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 8 }
                                            width: height * 16 / 9
                                            radius: Appearance.rounding.small
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 36; height: 36; radius: 18
                                                color: Qt.rgba(0, 0, 0, 0.55)
                                                MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; fill: 1; iconSize: 24; color: "white" }
                                            }
                                        }
                                        ColumnLayout {
                                            anchors { left: rtPic.right; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 14 }
                                            spacing: 4
                                            StyledText { Layout.fillWidth: true; text: root.name(rt.modelData); elide: Text.ElideRight; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                                            StyledText { Layout.fillWidth: true; text: `${root.dur(rt.modelData.dur - rt.modelData.pos)} left · ${root.baseName(root.dirOf(rt.modelData.path))}`; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 4
                                                implicitHeight: 4; radius: 2
                                                color: Qt.alpha(Appearance.colors.colOnLayer1, 0.12)
                                                Rectangle { height: parent.height; radius: 2; width: parent.width * root.progress(rt.modelData); color: Appearance.colors.colPrimary }
                                            }
                                        }
                                        HoverHandler { id: rtHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.picked(rt.modelData.path) }
                                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.openMenu(rt.modelData, rt) }
                                    }
                                }
                            }
                            StyledText { Layout.topMargin: 14; text: "Recently watched"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                        }
                    }
                    delegate: Card {}
                }

                // ── list: a table ──
                ColumnLayout {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18; topMargin: 8 }
                    visible: root.layout === "list" && root.shown.length > 0
                    spacing: 0
                    // column heads
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        spacing: 14
                        Item { implicitWidth: 96 }
                        StyledText { Layout.fillWidth: true; text: "NAME"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; color: Appearance.colors.colSubtext }
                        StyledText { Layout.preferredWidth: 160; text: "FOLDER"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; color: Appearance.colors.colSubtext }
                        StyledText { Layout.preferredWidth: 120; text: "PROGRESS"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; color: Appearance.colors.colSubtext }
                        StyledText { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "LENGTH"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; color: Appearance.colors.colSubtext }
                        StyledText { Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; text: "WATCHED"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; color: Appearance.colors.colSubtext }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colOutlineVariant; opacity: 0.6 }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.shown
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 62
                            radius: Appearance.rounding.small
                            color: rowHov.hovered ? Appearance.colors.colLayer1Hover : row.index % 2 ? Qt.alpha(Appearance.colors.colLayer1, 0.4) : "transparent"
                            RowLayout {
                                anchors { fill: parent; leftMargin: 0; rightMargin: 0 }
                                spacing: 14
                                Still {
                                    item: row.modelData
                                    Layout.leftMargin: 4
                                    implicitWidth: 92; implicitHeight: 52
                                    radius: Appearance.rounding.verysmall
                                }
                                StyledText { Layout.fillWidth: true; text: root.name(row.modelData); elide: Text.ElideMiddle; color: Appearance.colors.colOnLayer0 }
                                StyledText { Layout.preferredWidth: 160; text: root.baseName(root.dirOf(row.modelData.path)); elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                                RowLayout {
                                    Layout.preferredWidth: 120
                                    spacing: 8
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 4; radius: 2
                                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.12)
                                        Rectangle { height: parent.height; radius: 2; width: parent.width * root.progress(row.modelData); color: row.modelData.finished ? Appearance.colors.colSubtext : Appearance.colors.colPrimary }
                                    }
                                    StyledText {
                                        Layout.preferredWidth: 36
                                        horizontalAlignment: Text.AlignRight
                                        text: row.modelData.finished ? "✓" : `${Math.round(100 * root.progress(row.modelData))}%`
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                                StyledText { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: root.dur(row.modelData.dur); font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                                StyledText { Layout.preferredWidth: 90; Layout.rightMargin: 4; horizontalAlignment: Text.AlignRight; text: root.ago(row.modelData.at); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                            }
                            HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.picked(row.modelData.path) }
                            TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.openMenu(row.modelData, row) }
                        }
                    }
                }
            }

            // ── status bar ──
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                color: Appearance.colors.colLayer1Base
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Appearance.colors.colOutlineVariant; opacity: 0.6 }
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    spacing: 14
                    Rectangle { implicitWidth: 7; implicitHeight: 7; radius: 3.5; color: root.loaded ? Appearance.colors.colSuccess : Appearance.colors.colSubtext }
                    StyledText {
                        text: root.loaded ? `${root.items.length} in history  ·  ${root.unfinished.length} to finish  ·  ${root.watched.length} watched` : "Connecting to reeld…"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: "Drop a file anywhere to play it"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
