pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * reel's own settings, in ~/.config/reel/settings.json.
 *
 * Separate from quarry's Prefs (which reel shares by symlink and which only
 * knows quarry's keys). Written by the settings sheet; edits by hand are
 * picked up live.
 */
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("HOME")}/.config/reel/settings.json`
    property alias s: adapter

    // ── the actions, and the keys they start on ─────────────────────────
    /*
     * One table: what an action is called, where it sits in the shortcut
     * sheet, and its default keys. A key is written as the sheet shows it —
     * "Shift+Right", "Space", "?" — and `keys` in the file overrides an
     * action's list entirely.
     */
    readonly property var actions: [
        { "id": "toggle",       "group": "Playback", "label": "Play / pause",              "keys": ["Space", "K"] },
        { "id": "back",         "group": "Playback", "label": "Back (short step)",          "keys": ["Left", "J"] },
        { "id": "forward",      "group": "Playback", "label": "Forward (short step)",       "keys": ["Right", "L"] },
        { "id": "backLong",     "group": "Playback", "label": "Back (long step)",           "keys": ["Shift+Left"] },
        { "id": "forwardLong",  "group": "Playback", "label": "Forward (long step)",        "keys": ["Shift+Right"] },
        { "id": "frameBack",    "group": "Playback", "label": "One frame back",             "keys": [","] },
        { "id": "frameForward", "group": "Playback", "label": "One frame forward",          "keys": ["."] },
        { "id": "start",        "group": "Playback", "label": "Back to the start",          "keys": ["Home", "0"] },
        { "id": "slower",       "group": "Playback", "label": "Slower",                     "keys": ["["] },
        { "id": "faster",       "group": "Playback", "label": "Faster",                     "keys": ["]"] },
        { "id": "speedReset",   "group": "Playback", "label": "Normal speed",               "keys": ["Backspace"] },
        { "id": "loop",         "group": "Playback", "label": "Loop this file",             "keys": ["R"] },
        { "id": "volumeUp",     "group": "Sound",    "label": "Volume up",                  "keys": ["Up"] },
        { "id": "volumeDown",   "group": "Sound",    "label": "Volume down",                "keys": ["Down"] },
        { "id": "mute",         "group": "Sound",    "label": "Mute",                       "keys": ["M"] },
        { "id": "audioTrack",   "group": "Sound",    "label": "Next audio track",           "keys": ["A"] },
        { "id": "subtitles",    "group": "Sound",    "label": "Next subtitle track / off",  "keys": ["C"] },
        { "id": "next",         "group": "Folder",   "label": "Next video",                 "keys": ["N"] },
        { "id": "previous",     "group": "Folder",   "label": "Previous video",             "keys": ["P"] },
        { "id": "playlist",     "group": "Folder",   "label": "Show the folder",            "keys": ["Tab"] },
        { "id": "fullscreen",   "group": "Window",   "label": "Fullscreen",                 "keys": ["F"] },
        { "id": "fit",          "group": "Window",   "label": "Fit / fill / stretch",       "keys": ["Z"] },
        { "id": "screenshot",   "group": "Window",   "label": "Save this frame",            "keys": ["S"] },
        { "id": "settings",     "group": "Window",   "label": "Settings",                   "keys": ["O"] },
        { "id": "shortcuts",    "group": "Window",   "label": "Keyboard shortcuts",         "keys": ["?", "F1"] },
        { "id": "quit",         "group": "Window",   "label": "Close",                      "keys": ["Q", "Ctrl+W"] },
    ]

    /// The keys an action answers to now: the file's override, else the default.
    function keysFor(id) {
        const o = root.s.keys || {};
        if (Array.isArray(o[id])) return o[id];
        const a = root.actions.find(x => x.id === id);
        return a ? a.keys : [];
    }
    /// The action a key belongs to, or "".
    function actionFor(key) {
        for (const a of root.actions)
            if (root.keysFor(a.id).indexOf(key) >= 0) return a.id;
        return "";
    }
    /// Give `id` exactly these keys; any other action holding one of them loses it.
    function bind(id, keys) {
        const o = Object.assign({}, root.s.keys || {});
        for (const a of root.actions) {
            if (a.id === id) continue;
            const mine = root.keysFor(a.id);
            const left = mine.filter(k => keys.indexOf(k) < 0);
            if (left.length !== mine.length) o[a.id] = left;
        }
        o[id] = keys;
        root.s.keys = o;
    }
    function resetKeys() { root.s.keys = ({}); }

    /// A key event as the table writes it: "Ctrl+Shift+Left", "Space", "?".
    function keyName(event) {
        const named = {
            [Qt.Key_Space]: "Space", [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up",
            [Qt.Key_Down]: "Down", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "PageUp",
            [Qt.Key_PageDown]: "PageDown", [Qt.Key_Backspace]: "Backspace", [Qt.Key_Delete]: "Delete",
            [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab", [Qt.Key_Return]: "Enter", [Qt.Key_Enter]: "Enter",
            [Qt.Key_Escape]: "Esc", [Qt.Key_Insert]: "Insert",
        };
        let base = named[event.key];
        if (!base && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) base = "F" + (event.key - Qt.Key_F1 + 1);
        const printable = event.text && event.text.length === 1 && event.text.charCodeAt(0) > 32;
        if (!base && printable) base = event.text.toUpperCase();
        if (!base) return "";
        const mods = [];
        if (event.modifiers & Qt.ControlModifier) mods.push("Ctrl");
        if (event.modifiers & Qt.AltModifier) mods.push("Alt");
        // Shift is part of a printed symbol ("?" is Shift+/), so it is only
        // named for keys that do not print.
        if ((event.modifiers & Qt.ShiftModifier) && (!printable || /^[A-Z]$/.test(base) && mods.length > 0)) mods.push("Shift");
        return mods.concat([base]).join("+");
    }

    FileView {
        id: view
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeTimer.restart()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: adapter

            // playback
            property bool resume: true
            // when a file ends: "next" | "stop" | "loopFolder" | "close"
            property string endAction: "next"
            // remember positions and what was watched
            property bool history: true
            property bool startFullscreen: false
            property bool clickToPause: true      // a click on the picture pauses / plays
            // the loop button, remembered
            property bool loop: false
            property real defaultSpeed: 1.0
            // seeking, in seconds
            property int seekShort: 10
            property int seekLong: 60
            property int volumeStep: 5
            // picture: "fit" | "fill" | "stretch"
            property string fit: "fit"
            // subtitles: turn the first track on when a file has one
            property bool subtitlesOn: false
            // controls
            property int hideAfterMs: 2600
            property bool osd: true
            // where it appears: "top" | "center" | "bottom"
            property string osdPosition: "top"
            // the clock left of the timeline: "elapsed" | "remaining"
            property string timeDisplay: "elapsed"
            // a still above the timeline where the pointer is
            property bool seekPreview: true
            property bool showTitle: true
            property bool showFolderButtons: true
            property bool showFrameButtons: true
            property bool showScreenshotButton: true
            property bool showSpeedButton: true
            property bool showLoopButton: true
            // look: "scrim" (controls on the picture) | "pill" (quarry's card)
            property string controlStyle: "scrim"
            // accent: "theme" | "secondary" | "tertiary" | "#rrggbb"
            property string accent: "theme"
            property bool filledPlay: true
            // the title bar: "system" (ii-decor's, as on every other window) | "own" (reel's row)
            property string titleBar: "system"
            // reel's own window buttons: "dots" (as ii-decor) | "icons"
            property string windowButtons: "dots"
            // folder sheet
            property string playlistSide: "right"
            // panels: "solid" | "glass" (the picture shows through)
            property string panelStyle: "solid"
            property bool playlistThumbs: true
            // screenshots
            property string screenshotDir: "~/Pictures/Screenshots/reel"
            // "png" (lossless) | "jpg" (small)
            property string screenshotFormat: "png"
            // also put the frame on the clipboard
            property bool screenshotCopy: true
            // action id -> [key, …]; only what differs from the defaults
            property var keys: ({})
        }
    }
    Timer {
        id: writeTimer
        interval: 400
        onTriggered: view.writeAdapter()
    }
}
