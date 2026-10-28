//@ pragma UseQApplication
//@ pragma AppId reel
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
// The theme is read from a generated file with XMLHttpRequest, which Qt
// refuses for local paths unless this is set.
//@ pragma Env QML_XHR_ALLOW_FILE_READ=1
//@ pragma Env QS_NO_RELOAD_POPUP=1
// These preferences are this app's, not quarry's — see quarry's Prefs.qml.
//@ pragma Env QS_PREFS_APP=reel

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import qs.modules.common
import qs.modules.widgets
import qs.modules.gallery
import qs.services
import qs.reel

/*
 * reel — a video player.
 *
 * Built from quarry by import, not copy: the theme, the widgets, the daemon
 * client and the video pane itself (VideoView) are quarry's own files,
 * symlinked in the way scree does it. What reel adds is the window around
 * them, its settings and keys (reel/Settings.qml), and through reeld the
 * memory a player needs: where you stopped, and what comes next in the folder.
 *
 * The title bar is ii-decor's, as on every other window (Settings → Look →
 * Title bar). Set to reel's own, the top row carries the same buttons,
 * through ii-decor-btn, so minimize and fullscreen behave as everywhere else.
 */
ShellRoot {
    id: shell

    /// The file on screen, as a path.
    property string path: ""
    readonly property string title: shell.path.split("/").pop()
    /// VideoView takes a quarry row; a local file is the simplest row there is.
    /// the viewer for the open file (an image, a PDF, text — reel/Viewers.qml), or null: the player's
    readonly property var viewer: Viewers.list.length >= 0 ? Viewers.viewerFor(shell.path) : null
    readonly property var item: shell.path.length > 0 && !shell.viewer
        ? ({ "id": shell.path, "family": "video", "url": "file://" + shell.path, "title": shell.title })
        : null
    readonly property var player: view.mediaPlayer
    readonly property var s: Settings.s
    property int pid: 0

    // ── files ────────────────────────────────────────────────────────────

    function open(p) {
        const next = String(p).replace(/^file:\/\//, "");
        if (next.length === 0 || next === shell.path) return;
        shell.saveProgress();
        shell.path = next;
        // not a video: its viewer takes it, and the arrows walk its kind of file
        if (Viewers.viewerFor(next)) { Viewers.folder(next); return; }
        view.rate = shell.s.defaultSpeed;
        Library.folder(next);
        if (!shell.s.resume || !shell.s.history) return;
        // Start where it was left. Asked before the file opens; if the answer
        // comes later, seek directly.
        Library.resumePoint(next, ms => {
            if (shell.path !== next || ms < 5000) return;
            if (shell.player.duration > 0) shell.player.position = ms;
            else view.startAt(ms);
            Toast.show(`Resumed at ${view.clock(ms)}`, "Start over", () => { shell.player.position = 0; });
        });
    }
    function step(delta) {
        if (shell.viewer) {
            const j = Viewers.siblingIndex + delta;
            if (j >= 0 && j < Viewers.siblings.length) shell.open(Viewers.siblings[j]);
            else shell.osd(delta > 0 ? "last_page" : "first_page", delta > 0 ? "Last one in the folder" : "First one in the folder");
            return;
        }
        const i = Library.index + delta;
        if (i >= 0 && i < Library.files.length) shell.open(Library.files[i]);
        else shell.osd(delta > 0 ? "last_page" : "first_page", delta > 0 ? "Last video in the folder" : "First video in the folder");
    }
    function saveProgress() {
        if (!shell.s.history) return;
        if (shell.path.length > 0 && shell.player)
            Library.report(shell.path, shell.player.position, shell.player.duration);
    }
    function windowButton(action) {
        if (shell.pid > 0) Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/ii-decor-btn`, action, String(shell.pid)]);
    }
    function quit() { shell.saveProgress(); Qt.quit(); }

    // ── the actions every key and button goes through ───────────────────

    function osd(icon, text) { if (shell.s.osd) osdPill.show(icon, text); }

    function seek(seconds) {
        if (!(shell.player.duration > 0)) return;
        view.nudge(seconds * 1000);
        shell.osd(seconds < 0 ? "fast_rewind" : "fast_forward", `${seconds > 0 ? "+" : "−"}${Math.abs(seconds)} s`);
    }
    function setVolume(v) {
        Prefs.videoVolume = Math.max(0, Math.min(1, v));
        Prefs.videoSound = true;
        shell.osd(Prefs.videoVolume === 0 ? "volume_off" : Prefs.videoVolume < 0.5 ? "volume_down" : "volume_up",
                  `Volume ${Math.round(Prefs.videoVolume * 100)} %`);
    }
    readonly property var speeds: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    function setSpeed(r) {
        view.rate = r;
        shell.osd("speed", `Speed ${r}×`);
    }
    function shiftSpeed(dir) {
        const i = shell.speeds.findIndex(v => v >= view.rate - 1e-6);
        const at = i < 0 ? shell.speeds.length - 1 : i;
        shell.setSpeed(shell.speeds[Math.max(0, Math.min(shell.speeds.length - 1, at + dir))]);
    }

    /// A track's name as a person would read it.
    function trackName(meta, n) {
        if (!meta) return `Track ${n}`;
        const title = meta.stringValue(MediaMetaData.Title);
        const lang = meta.stringValue(MediaMetaData.Language);
        return [title, lang].filter(x => x && x.length > 0).join(" · ") || `Track ${n}`;
    }
    function cycleAudio() {
        const tracks = shell.player.audioTracks;
        if (tracks.length < 2) { shell.osd("music_note", tracks.length ? "Only one audio track" : "No audio"); return; }
        const next = (shell.player.activeAudioTrack + 1) % tracks.length;
        shell.player.activeAudioTrack = next;
        shell.osd("music_note", shell.trackName(tracks[next], next + 1));
    }
    function cycleSubtitles() {
        const tracks = shell.player.subtitleTracks;
        if (tracks.length === 0) { shell.osd("subtitles_off", "No subtitles in this file"); return; }
        // off → 1 → 2 → … → off
        const next = shell.player.activeSubtitleTrack + 1 >= tracks.length ? -1 : shell.player.activeSubtitleTrack + 1;
        shell.player.activeSubtitleTrack = next;
        shell.osd(next < 0 ? "subtitles_off" : "subtitles", next < 0 ? "Subtitles off" : shell.trackName(tracks[next], next + 1));
    }
    readonly property var fits: ["fit", "fill", "stretch"]
    function cycleFit() {
        const next = shell.fits[(shell.fits.indexOf(shell.s.fit) + 1) % shell.fits.length];
        shell.s.fit = next;
        shell.osd("aspect_ratio", { "fit": "Fit", "fill": "Fill (crop)", "stretch": "Stretch" }[next]);
    }
    /// Only one sheet at a time; the same key closes it again.
    function togglePanel(which) {
        panels.current = panels.current === which ? "" : which;
    }

    function run(action) {
        switch (action) {
        case "toggle": view.toggle(); shell.osd(view.playing ? "pause" : "play_arrow", view.playing ? "Paused" : "Playing"); break;
        case "back": shell.seek(-shell.s.seekShort); break;
        case "forward": shell.seek(shell.s.seekShort); break;
        case "backLong": shell.seek(-shell.s.seekLong); break;
        case "forwardLong": shell.seek(shell.s.seekLong); break;
        case "frameBack": view.stepFrame(-1); break;
        case "frameForward": view.stepFrame(1); break;
        case "start": shell.player.position = 0; shell.osd("first_page", "From the start"); break;
        case "slower": shell.shiftSpeed(-1); break;
        case "faster": shell.shiftSpeed(1); break;
        case "speedReset": shell.setSpeed(1); break;
        case "loop": shell.s.loop = !shell.s.loop; shell.osd("repeat", view.looping ? "Loop on" : "Loop off"); break;
        case "volumeUp": shell.setVolume(Prefs.videoVolume + shell.s.volumeStep / 100); break;
        case "volumeDown": shell.setVolume(Prefs.videoVolume - shell.s.volumeStep / 100); break;
        case "mute": Prefs.videoSound = !Prefs.videoSound; shell.osd(Prefs.videoSound ? "volume_up" : "volume_off", Prefs.videoSound ? "Sound on" : "Muted"); break;
        case "audioTrack": shell.cycleAudio(); break;
        case "subtitles": shell.cycleSubtitles(); break;
        case "next": shell.step(1); break;
        case "previous": shell.step(-1); break;
        case "playlist": shell.togglePanel("playlist"); break;
        case "fullscreen": shell.windowButton("fullscreen"); break;
        case "fit": shell.cycleFit(); break;
        case "screenshot": view.grabFrame(); break;
        case "settings": shell.togglePanel("settings"); break;
        case "shortcuts": shell.togglePanel("shortcuts"); break;
        case "quit": shell.quit(); break;
        }
    }

    // ── accent: the theme's, or the one picked in settings ──────────────

    /// The palette as tinct wrote it, before reel tinted anything.
    property var themeColors: null
    function applyAccent() {
        if (!shell.themeColors) shell.themeColors = Scheme.colors;
        const t = shell.themeColors, a = shell.s.accent;
        let primary = t.primary, onPrimary = t.onPrimary;
        if (a === "secondary") { primary = t.secondary; onPrimary = t.onSecondary; }
        else if (a === "tertiary") { primary = t.tertiary; onPrimary = t.onTertiary; }
        else if (/^#[0-9a-fA-F]{6}$/.test(a)) {
            primary = a;
            const c = Qt.color(a);
            onPrimary = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b > 0.55 ? "#1a1a1a" : "#ffffff";
        }
        Scheme.colors = Object.assign({}, t, { "primary": primary, "onPrimary": onPrimary });
    }
    Connections {
        target: Scheme
        function onReloaded() { shell.themeColors = Scheme.colors; shell.applyAccent(); }
    }
    Connections {
        target: Settings.s
        function onAccentChanged() { shell.applyAccent(); }
    }

    Component.onCompleted: {
        // A player starts with sound and plays a file once; quarry's gallery
        // defaults are the opposite on purpose.
        Prefs.videoSound = true;
        if (Scheme.source === "tinct") shell.applyAccent();
        const first = Quickshell.env("REEL_OPEN") || "";
        if (first.length > 0) shell.open(first);
    }

    // Our own pid, for ii-decor-btn: the parent of a shell we start.
    Process {
        running: true
        command: ["sh", "-c", "echo $PPID"]
        stdout: StdioCollector {
            onStreamFinished: {
                shell.pid = parseInt(text) || 0;
                if (shell.s.startFullscreen) shell.windowButton("fullscreen");
            }
        }
    }

    // Progress is written while playing, so a crash or a killed window still
    // resumes close to where it was.
    Timer {
        interval: 5000
        repeat: true
        running: view.playing
        onTriggered: shell.saveProgress()
    }
    Connections {
        target: view
        function onPlayingChanged() { if (!view.playing) shell.saveProgress(); }
        function onEnded() {
            shell.saveProgress();
            switch (shell.s.endAction) {
            case "next": if (Library.hasNext) shell.step(1); break;
            case "loopFolder": if (Library.hasNext) shell.step(1); else if (Library.files.length > 0) shell.open(Library.files[0]); break;
            case "close": shell.quit(); break;
            }
        }
        function onFrameGrabbed(path) {
            if (shell.s.screenshotCopy)
                Quickshell.execDetached(["sh", "-c", "wl-copy --type \"$2\" < \"$1\"", "_", path, path.endsWith(".png") ? "image/png" : "image/jpeg"]);
            shell.osd("photo_camera", shell.s.screenshotCopy ? "Frame saved and copied" : "Frame saved");
        }
    }
    Connections {
        target: shell.player
        function onMediaStatusChanged() {
            if (shell.player.mediaStatus === MediaPlayer.LoadedMedia && shell.s.subtitlesOn && shell.player.subtitleTracks.length > 0)
                shell.player.activeSubtitleTrack = 0;
        }
    }

    // the viewers load after a file can already be open: give it its folder then
    Connections {
        target: Viewers
        function onListChanged() { if (shell.viewer && Viewers.siblings.length === 0) Viewers.folder(shell.path); }
    }
    IpcHandler {
        target: "reel"
        function open(path: string): void { shell.open(path); }
        function action(id: string): void { shell.run(id); }
        /// The window as drawn, written to `path` — for checking the look
        /// without capturing the screen.
        function shot(path: string): void { stage.grabToImage(r => r.saveToFile(path)); }
        function pause(): void { shell.player.pause(); }
        function panel(name: string): void { panels.current = name; }
        function settingsPage(name: string): void { panels.current = "settings"; settingsSheet.page = name; }
        function probe(): string {
            return JSON.stringify(Object.assign({ "path": shell.path, "index": Library.index, "files": Library.files.length,
                                                  "daemon": Client.connected, "scheme": Scheme.source,
                                                  "primary": String(Appearance.colors.colPrimary), "panel": panels.current,
                                                  "rate": view.rate, "volume": Prefs.videoVolume }, view.probe));
        }
    }

    // the real window buttons, drawn by the compositor over our top-right corner (ii-decor)
    Process {
        id: decor
        command: ["sh", "-c", "sleep 0.4; hyprctl iidecor integrate pid:$PPID overlay >/dev/null 2>&1 || true"]
    }
    Timer { interval: 200; running: win.visible; onTriggered: decor.running = true }


    FloatingWindow {


        // browser-like scrolling for every list in the window (Momentum.qml)


        MomentumInjector { root: parent }
        id: win
        // named from the start: the window rules (a picture floats) see the file the moment it maps
        title: (shell.path || Quickshell.env("REEL_OPEN") || "") !== "" ? `${(shell.path || Quickshell.env("REEL_OPEN")).split("/").pop()} — reel` : "reel"
        implicitWidth: 1280
        implicitHeight: 760
        color: "black"
        visible: true
        onVisibleChanged: if (!visible) shell.quit()

        Item {
            id: stage
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                event.accepted = true;
                if (shortcutsSheet.capture(event)) return;
                const name = Settings.keyName(event);
                const action = Settings.actionFor(name);
                if (action.length > 0) { shell.run(action); return; }
                // 1–9: jump to 10 … 90 %, as on every video site.
                if (/^[1-9]$/.test(name) && shell.player.duration > 0) {
                    shell.player.position = shell.player.duration * Number(name) / 10;
                    shell.osd("percent", `${Number(name) * 10} %`);
                    return;
                }
                if (name === "Esc" && panels.current.length > 0) { panels.current = ""; return; }
                event.accepted = false;
            }

            // an image, a PDF, text: the viewer for it, over an idle player
            Loader {
                id: viewerLoader
                anchors.fill: parent
                z: 2
                focus: active
                active: !!shell.viewer
                source: shell.viewer ? shell.viewer.url : ""
                onLoaded: { item.path = Qt.binding(() => shell.path); item.forceActiveFocus(); }
                Binding { target: viewerLoader.item; property: "accent"; value: Appearance.colors.colPrimary; when: !!viewerLoader.item }
                // where it is in its folder, and the files beside it (a viewer may load them ahead)
                Binding { target: viewerLoader.item; property: "index"; value: Viewers.siblingIndex; when: !!viewerLoader.item && "index" in viewerLoader.item }
                Binding { target: viewerLoader.item; property: "count"; value: Viewers.siblings.length; when: !!viewerLoader.item && "count" in viewerLoader.item }
                Binding { target: viewerLoader.item; property: "neighbours"; value: [Viewers.siblings[Viewers.siblingIndex + 1], Viewers.siblings[Viewers.siblingIndex - 1]]; when: !!viewerLoader.item && "neighbours" in viewerLoader.item }
                Connections { target: viewerLoader.item; ignoreUnknownSignals: true; function onStep(d) { shell.step(d); } }
            }

            VideoView {
                id: view
                anchors.fill: parent
                visible: !shell.viewer
                item: shell.item
                active: true
                // Loop and the clock are remembered: the bar's own buttons flip
                // them inside the pane, and the change is written back here.
                Binding on looping { value: shell.s.loop }
                onLoopingChanged: if (shell.s.loop !== looping) shell.s.loop = looping
                onShowRemainingChanged: { const want = showRemaining ? "remaining" : "elapsed"; if (shell.s.timeDisplay !== want) shell.s.timeDisplay = want; }

                fillMode: ({ "fit": VideoOutput.PreserveAspectFit, "fill": VideoOutput.PreserveAspectCrop,
                             "stretch": VideoOutput.Stretch })[shell.s.fit] ?? VideoOutput.PreserveAspectFit
                idleMs: shell.s.hideAfterMs
                framesDir: shell.s.screenshotDir.replace(/^~/, Quickshell.env("HOME"))
                showFrameButtons: shell.s.showFrameButtons
                showScreenshotButton: shell.s.showScreenshotButton
                showSpeedButton: shell.s.showSpeedButton
                showLoopButton: shell.s.showLoopButton
                filledPlay: shell.s.filledPlay
                framesFormat: shell.s.screenshotFormat
                framesByTitle: true
                Binding on showRemaining { value: shell.s.timeDisplay === "remaining" }
                // The top row, an open panel or menu is reel's own chrome: the
                // pane cannot see the pointer there, and used to hide everything.
                holdControls: topHover.hovered || panels.current.length > 0 || tracksMenu.visible || moreMenu.visible

                // "scrim": no box, the controls sit on a darkened edge of the
                // picture. "pill": quarry's own card.
                readonly property bool onPicture: shell.s.controlStyle !== "pill"
                barColor: onPicture ? "transparent" : Appearance.colors.colSurfaceContainerHighest
                barBorderColor: onPicture ? "transparent" : Appearance.colors.colOutlineVariant
                controlIconColor: onPicture ? "#ffffff" : Appearance.colors.colOnLayer1
                controlTextColor: onPicture ? "#ffffff" : Appearance.colors.colOnLayer1
                scrim: onPicture
            }

            // The top scrim, under the title (the bottom one is VideoView's
            // own, beneath its controls).
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 120
                opacity: view.controlsOpacity
                visible: opacity > 0.01 && view.onPicture
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.72) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            // A click on the picture: pause / play (Settings › Controls can turn it off).
            // A double-click: fullscreen, as in every player. The click waits out the
            // double-click time, so a double-click does not pause and play on its way.
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: if (shell.s.clickToPause) clickPause.restart()
                onDoubleTapped: { clickPause.stop(); shell.run("fullscreen"); }
            }
            Timer {
                id: clickPause
                interval: Qt.styleHints.mouseDoubleClickInterval
                onTriggered: shell.run("toggle")
            }
            // The wheel over the picture: volume.
            WheelHandler {
                enabled: !shell.viewer   // an image, a PDF or text has its own wheel (pan, zoom)
                onWheel: event => shell.setVolume(Prefs.videoVolume + (event.angleDelta.y > 0 ? 1 : -1) * shell.s.volumeStep / 100)
            }

            // Drop a file on the window to play it.
            DropArea {
                anchors.fill: parent
                onDropped: drop => { if (drop.hasUrls) shell.open(drop.urls[0].toString()); }
            }

            // ── the top: what is playing, the folder, the window ──────────
            Rectangle {
                id: topBar
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.leftMargin: view.onPicture ? 18 : 10
                anchors.rightMargin: view.onPicture ? 18 : 10
                anchors.topMargin: view.onPicture ? 12 : 10
                height: view.onPicture ? 44 : 52
                radius: Appearance.rounding.large
                color: view.onPicture ? "transparent" : Appearance.colors.colSurfaceContainerHighest
                border.width: view.onPicture ? 0 : 1
                border.color: Appearance.colors.colOutlineVariant
                opacity: view.controlsOpacity
                visible: opacity > 0.01 && shell.item !== null   // the start screen has its own toolbar
                readonly property color fg: view.onPicture ? "#ffffff" : Appearance.colors.colOnLayer1
                readonly property color hover: view.onPicture ? Qt.rgba(1, 1, 1, 0.14) : Appearance.colors.colLayer1Hover
                HoverHandler { id: topHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: view.onPicture ? 0 : 14
                    anchors.rightMargin: view.onPicture ? 0 : 10
                    spacing: 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: shell.s.showTitle ? 1 : 0
                        StyledText {
                            Layout.fillWidth: true
                            // the system title bar already names the file
                            visible: shell.s.titleBar !== "system"
                            text: shell.item ? shell.title.replace(/\.[^.]+$/, "") : "reel"
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: topBar.fg
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: shell.item !== null
                            text: {
                                const parts = shell.path.split("/");
                                const folder = parts.length > 1 ? parts[parts.length - 2] : "";
                                const ext = (shell.title.split(".").pop() || "").toUpperCase();
                                const speed = Math.abs(view.rate - 1) > 1e-6 ? `${view.rate}×` : "";
                                return [folder, Library.files.length > 1 ? `${Library.index + 1} of ${Library.files.length}` : "", ext, speed]
                                    .filter(s => s.length > 0).join("  ·  ");
                            }
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: topBar.fg
                            opacity: 0.68
                        }
                    }

                    IconButton {
                        icon: "skip_previous"; tooltip: `Previous in folder  (${Settings.keysFor("previous")[0] ?? ""})`; size: 36
                        visible: shell.s.showFolderButtons && Library.files.length > 1
                        enabled: Library.hasPrev
                        iconColor: topBar.fg; hoverColor: topBar.hover
                        onClicked: shell.run("previous")
                    }
                    IconButton {
                        icon: "skip_next"; tooltip: `Next in folder  (${Settings.keysFor("next")[0] ?? ""})`; size: 36
                        visible: shell.s.showFolderButtons && Library.files.length > 1
                        enabled: Library.hasNext
                        iconColor: topBar.fg; hoverColor: topBar.hover
                        onClicked: shell.run("next")
                    }
                    Repeater {
                        model: [{ "id": "playlist", "icon": "playlist_play", "tip": "Folder" },
                                { "id": "subtitlesMenu", "icon": "subtitles", "tip": "Audio and subtitles" },
                                { "id": "settings", "icon": "tune", "tip": "Settings" },
                                { "id": "moreMenu", "icon": "more_vert", "tip": "More" }]
                        delegate: IconButton {
                            id: topBtn
                            required property var modelData
                            readonly property var menu: modelData.id === "subtitlesMenu" ? tracksMenu : modelData.id === "moreMenu" ? moreMenu : null
                            readonly property bool on: menu ? menu.visible : panels.current === modelData.id
                            visible: shell.item !== null || modelData.id === "settings"
                            icon: modelData.icon
                            tooltip: topBtn.menu ? modelData.tip
                                : `${modelData.tip}  (${Settings.keysFor(modelData.id)[0] ?? ""})`
                            size: 36
                            toggled: on
                            toggledColor: Appearance.colors.colPrimary
                            iconColor: on ? Appearance.colors.colOnPrimary : topBar.fg
                            hoverColor: topBar.hover
                            onClicked: {
                                if (!topBtn.menu) { shell.togglePanel(modelData.id); return; }
                                const m = topBtn.menu;
                                if (m.visible) { m.close(); return; }
                                const at = topBtn.mapToItem(stage, topBtn.width / 2, topBtn.height);
                                m.x = Math.max(10, Math.min(stage.width - m.width - 10, at.x - m.width / 2));
                                m.y = at.y + 8;
                                m.open();
                            }
                        }
                    }
                    Item { Layout.preferredWidth: 14; visible: shell.s.titleBar !== "system" }

                    // The window's own buttons, when the title bar is reel's:
                    // the dots ii-decor draws on every other window, or icons.
                    WindowDots {
                        visible: shell.s.titleBar !== "system" && shell.s.windowButtons === "dots"
                        Layout.alignment: Qt.AlignVCenter
                        onPressed: action => action === "close" ? shell.quit() : shell.windowButton(action)
                    }
                    Repeater {
                        model: shell.s.titleBar !== "system" && shell.s.windowButtons === "icons"
                            ? [{ "id": "minimize", "icon": "remove" }, { "id": "fullscreen", "icon": "fullscreen" }, { "id": "close", "icon": "close" }] : []
                        delegate: IconButton {
                            required property var modelData
                            icon: modelData.icon; size: 32
                            iconColor: topBar.fg
                            hoverColor: modelData.id === "close" ? Appearance.colors.colErrorContainer : topBar.hover
                            onClicked: modelData.id === "close" ? shell.quit() : shell.windowButton(modelData.id)
                        }
                    }
                }
            }

            // ── audio and subtitle tracks ─────────────────────────────────
            MenuPopup {
                id: tracksMenu
                minWidth: 240

                MenuRow { text: "Audio"; icon: "music_note"; enabled: false }
                Repeater {
                    model: shell.player ? shell.player.audioTracks.length : 0
                    delegate: MenuRow {
                        required property int index
                        text: shell.trackName(shell.player.audioTracks[index], index + 1)
                        checked: shell.player.activeAudioTrack === index
                        onTriggered: { shell.player.activeAudioTrack = index; tracksMenu.close(); }
                    }
                }
                MenuRow { separator: true }
                MenuRow { text: "Subtitles"; icon: "subtitles"; enabled: false }
                MenuRow {
                    text: "Off"
                    checked: !!shell.player && shell.player.activeSubtitleTrack < 0
                    onTriggered: { shell.player.activeSubtitleTrack = -1; tracksMenu.close(); }
                }
                Repeater {
                    model: shell.player ? shell.player.subtitleTracks.length : 0
                    delegate: MenuRow {
                        required property int index
                        text: shell.trackName(shell.player.subtitleTracks[index], index + 1)
                        checked: shell.player.activeSubtitleTrack === index
                        onTriggered: { shell.player.activeSubtitleTrack = index; tracksMenu.close(); }
                    }
                }
            }

            // ── ⋮ : everything else you might want for this file ─────────
            MenuPopup {
                id: moreMenu
                minWidth: 250

                MenuRow {
                    text: "Show in folder"; icon: "folder_open"
                    onTriggered: { Quickshell.execDetached(["xdg-open", shell.path.replace(/\/[^\/]*$/, "")]); moreMenu.close(); }
                }
                MenuRow {
                    text: "Copy path"; icon: "content_copy"
                    onTriggered: { Quickshell.execDetached(["wl-copy", "--", shell.path]); shell.osd("content_copy", "Path copied"); moreMenu.close(); }
                }
                MenuRow {
                    text: "Save this frame"; icon: "photo_camera"; hint: Settings.keysFor("screenshot")[0] ?? ""
                    onTriggered: { moreMenu.close(); view.grabFrame(); }
                }
                MenuRow { separator: true }
                MenuRow {
                    text: "Loop this file"; icon: "repeat"; checked: view.looping; hint: Settings.keysFor("loop")[0] ?? ""
                    onTriggered: { shell.run("loop"); moreMenu.close(); }
                }
                MenuRow {
                    text: `Fit: ${({ "fit": "fit", "fill": "fill", "stretch": "stretch" })[shell.s.fit]}`; icon: "aspect_ratio"
                    hint: Settings.keysFor("fit")[0] ?? ""
                    onTriggered: shell.run("fit")
                }
                MenuRow {
                    text: "Start over"; icon: "restart_alt"
                    onTriggered: { shell.player.position = 0; Library.forget(shell.path); shell.osd("restart_alt", "From the start"); moreMenu.close(); }
                }
                MenuRow { separator: true }
                MenuRow {
                    text: "Keyboard shortcuts"; icon: "keyboard"; hint: Settings.keysFor("shortcuts")[0] ?? ""
                    onTriggered: { panels.current = "shortcuts"; moreMenu.close(); }
                }
                MenuRow {
                    text: "Settings"; icon: "tune"; hint: Settings.keysFor("settings")[0] ?? ""
                    onTriggered: { panels.current = "settings"; moreMenu.close(); }
                }
            }

            // ── the sheets: folder, settings, keys — one at a time ────────
            Item {
                id: panels
                property string current: ""
                anchors { top: topBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
                anchors.topMargin: 8
                anchors.bottomMargin: 120

                Playlist {
                    anchors { top: parent.top; bottom: parent.bottom }
                    side: shell.s.playlistSide
                    look: shell.s.panelStyle
                    open: panels.current === "playlist"
                    onClosed: panels.current = ""
                    onPicked: path => shell.open(path)
                }
                SettingsSheet {
                    id: settingsSheet
                    anchors.top: parent.top
                    height: Math.min(parent.height, implicitHeight)
                    side: shell.s.playlistSide
                    look: shell.s.panelStyle
                    open: panels.current === "settings"
                    onClosed: panels.current = ""
                    onShortcutsRequested: panels.current = "shortcuts"
                    onForgetHistory: Library.clearAll((err, p) => Toast.show(err ? `Could not forget: ${err}` : `Forgot ${p.removed} files`))
                }
                ShortcutsSheet {
                    id: shortcutsSheet
                    anchors { top: parent.top; bottom: parent.bottom }
                    side: shell.s.playlistSide
                    look: shell.s.panelStyle
                    open: panels.current === "shortcuts"
                    onClosed: panels.current = ""
                }
            }

            // ── preview: a still of the moment under the pointer on the timeline ──
            Item {
                id: preview
                readonly property real ms: view.scrubHoverMs
                readonly property bool wanted: shell.s.seekPreview && ms >= 0 && shell.path.length > 0
                // Whole seconds, so moving along the bar asks reeld for a
                // handful of frames instead of one per pixel.
                readonly property int sec: Math.floor(Math.max(0, ms) / 1000)
                property string source: ""
                property int shownSec: -1

                width: 220
                height: width * 9 / 16 + 26
                x: Math.max(8, Math.min(stage.width - width - 8, view.scrubHoverX - width / 2))
                y: view.scrubTopY - height - 6
                visible: wanted
                opacity: wanted ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                onSecChanged: if (wanted) ask.restart()
                onWantedChanged: if (wanted) ask.restart()
                Timer {
                    id: ask
                    interval: 90
                    onTriggered: {
                        const want = preview.sec, file = shell.path;
                        Library.still(file, want, 320, url => {
                            if (shell.path === file) { preview.source = url; preview.shownSec = want; }
                        });
                    }
                }

                Rectangle {
                    id: frame
                    width: parent.width
                    height: parent.width * 9 / 16
                    radius: Appearance.rounding.normal
                    color: "black"
                    border.width: 2
                    border.color: Qt.rgba(1, 1, 1, 0.85)
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: preview.source
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: frame.bottom
                    anchors.topMargin: 4
                    width: stamp.implicitWidth + 14
                    height: 22
                    radius: Appearance.rounding.full
                    color: Qt.rgba(0, 0, 0, 0.7)
                    StyledText {
                        id: stamp
                        anchors.centerIn: parent
                        text: view.clock(preview.ms)
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "#ffffff"
                    }
                }
            }

            Osd {
                id: osdPill
                anchors.horizontalCenter: parent.horizontalCenter
                y: ({ "top": 72, "center": (parent.height - height) / 2, "bottom": parent.height - height - 140 })[shell.s.osdPosition] ?? 72
            }

            // No file open: the library — what to pick up, what was watched.
            Home {
                anchors.fill: parent
                z: -1
                // not under a picture either: hidden there it still took clicks (one on the image opened a library file)
                visible: !shell.item && !shell.viewer
                onPicked: path => shell.open(path)
                onAction: id => shell.run(id)
            }

            Snackbar {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 120
            }
        }
    }
}
