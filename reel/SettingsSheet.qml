import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.widgets

/*
 * Everything reel lets you change, as a home page of categories — each with
 * a one-line summary of where it stands — and a page per category. Every
 * control writes straight into Settings, which saves itself.
 */
SidePanel {
    id: root

    signal shortcutsRequested()
    signal forgetHistory()
    readonly property var s: Settings.s

    /// "" is the home page; otherwise one of `pages`' ids.
    property string page: ""
    onOpenChanged: if (!open) page = ""
    onBack: page = ""

    readonly property var current: root.pages.find(p => p.id === root.page) || null
    title: root.current ? root.current.title : "Settings"
    icon: "tune"
    canGoBack: root.page.length > 0

    function label(options, v) { return (options.find(o => o.value === v) || {}).label ?? String(v); }

    // ── the options, kept here so pages and summaries say the same thing ──
    readonly property var endOptions: [{ "value": "next", "label": "Next video" }, { "value": "stop", "label": "Stop" },
                                       { "value": "loopFolder", "label": "Loop the folder" }, { "value": "close", "label": "Close reel" }]
    readonly property var accentOptions: [{ "value": "theme", "label": "Theme" }, { "value": "secondary", "label": "Secondary" },
                                          { "value": "tertiary", "label": "Tertiary" }, { "value": "#ff5f56", "label": "Red" },
                                          { "value": "#ff9f43", "label": "Orange" }, { "value": "#5aa9ff", "label": "Blue" },
                                          { "value": "#b388ff", "label": "Violet" }, { "value": "#71cf84", "label": "Green" }]
    readonly property var fitOptions: [{ "value": "fit", "label": "Fit" }, { "value": "fill", "label": "Fill (crop)" }, { "value": "stretch", "label": "Stretch" }]
    readonly property var dirOptions: [{ "value": "~/Pictures/Screenshots/reel", "label": "Pictures/Screenshots/reel" },
                                       { "value": "~/Pictures/reel", "label": "Pictures/reel" },
                                       { "value": "~/Videos/frames", "label": "Videos/frames" },
                                       { "value": "~/Desktop", "label": "Desktop" }]

    readonly property var pages: [
        { "id": "playback", "title": "Playback", "icon": "play_circle",
          "summary": `${root.s.resume ? "Resume" : "Start over"} · ${root.label(root.endOptions, root.s.endAction)} at the end · ${root.s.defaultSpeed}×` },
        { "id": "seeking", "title": "Seeking and sound", "icon": "fast_forward",
          "summary": `Steps of ${root.s.seekShort} s and ${root.s.seekLong < 60 ? root.s.seekLong + " s" : root.s.seekLong / 60 + " min"} · Volume ${root.s.volumeStep} %` },
        { "id": "picture", "title": "Picture and subtitles", "icon": "aspect_ratio",
          "summary": `${root.label(root.fitOptions, root.s.fit)} · Subtitles ${root.s.subtitlesOn ? "on" : "off"}` },
        { "id": "controls", "title": "Controls", "icon": "smart_button",
          "summary": `Hide after ${root.s.hideAfterMs / 1000} s · ${root.s.seekPreview ? "Timeline preview" : "No preview"}` },
        { "id": "look", "title": "Look", "icon": "palette",
          "summary": `${root.label(root.accentOptions, root.s.accent)} accent · ${root.s.titleBar === "system" ? "System title bar" : "Own title bar"}` },
        { "id": "screenshots", "title": "Screenshots", "icon": "photo_camera",
          "summary": `${root.s.screenshotFormat.toUpperCase()} · ${root.s.screenshotDir.replace(/^~\//, "")}${root.s.screenshotCopy ? " · Copied" : ""}` },
        { "id": "history", "title": "History", "icon": "history",
          "summary": root.s.history ? "Remembers where you stopped" : "Off" },
    ]
    readonly property var keysPage: [{ "id": "keys", "title": "Keyboard shortcuts", "icon": "keyboard", "summary": "View and change every key" }]

    /// As tall as what it shows (the window sets its height from this), not
    /// the whole window with half of it empty.
    implicitHeight: 12 + 30 + 8 + (pageLoader.item ? pageLoader.item.implicitHeight : 0) + 12

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Loader {
            id: pageLoader
            width: flick.width
            sourceComponent: ({ "": home, "playback": playback, "seeking": seeking, "picture": picture, "controls": controls,
                                "look": look, "screenshots": screenshots, "history": history })[root.page] ?? home
            onLoaded: flick.contentY = 0
        }
    }

    // ── home: the categories, as grouped lists ─────────────────────────
    Component {
        id: home
        ColumnLayout {
            spacing: 12
            Repeater {
                model: [root.pages, root.keysPage]
                delegate: Rectangle {
                    id: group
                    required property var modelData
                    readonly property var items: modelData
                    Layout.fillWidth: true
                    implicitHeight: col.implicitHeight
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    clip: true
                    ColumnLayout {
                        id: col
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: group.items
                            delegate: Rectangle {
                                id: cat
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 56
                                color: catHov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 1)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                // between rows, from the text's edge — not across the icons
                                Rectangle {
                                    visible: cat.index > 0
                                    anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 50 }
                                    height: 1
                                    color: Appearance.colors.colOutlineVariant
                                    opacity: 0.6
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 12
                                    spacing: 14
                                    MaterialSymbol {
                                        Layout.preferredWidth: 20
                                        text: cat.modelData.icon
                                        iconSize: 20
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: cat.modelData.title
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: cat.modelData.summary
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MaterialSymbol { text: "chevron_right"; iconSize: 18; color: Appearance.colors.colSubtext }
                                }
                                HoverHandler { id: catHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: cat.modelData.id === "keys" ? root.shortcutsRequested() : root.page = cat.modelData.id
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── the pages ────────────────────────────────────────────────────────
    Component {
        id: playback
        ColumnLayout {
            spacing: 2
            SettingRow {
                icon: "history"; label: "Resume where I stopped"
                description: "Opening a file again starts at the last position"
                hasSwitch: true; checked: root.s.resume
                onToggled: on => root.s.resume = on
            }
            ChoiceRow {
                icon: "queue_play_next"; label: "When a video ends"
                options: root.endOptions; current: root.s.endAction
                onPicked: v => root.s.endAction = v
            }
            ChoiceRow {
                icon: "speed"; label: "Speed a file starts at"
                options: [0.75, 1, 1.25, 1.5, 2].map(v => ({ "value": v, "label": `${v}×` }))
                current: root.s.defaultSpeed
                onPicked: v => root.s.defaultSpeed = v
            }
            SettingRow {
                icon: "fullscreen"; label: "Start in fullscreen"
                hasSwitch: true; checked: root.s.startFullscreen
                onToggled: on => root.s.startFullscreen = on
            }
        }
    }

    Component {
        id: seeking
        ColumnLayout {
            spacing: 2
            ChoiceRow {
                icon: "fast_forward"; label: "Short step"; description: "← / → and J / L"
                options: [3, 5, 10, 15, 30].map(v => ({ "value": v, "label": `${v} s` }))
                current: root.s.seekShort
                onPicked: v => root.s.seekShort = v
            }
            ChoiceRow {
                icon: "double_arrow"; label: "Long step"; description: "Shift + ← / →"
                options: [30, 60, 120, 300].map(v => ({ "value": v, "label": v < 60 ? `${v} s` : `${v / 60} min` }))
                current: root.s.seekLong
                onPicked: v => root.s.seekLong = v
            }
            ChoiceRow {
                icon: "volume_up"; label: "Volume step"; description: "↑ / ↓ and the mouse wheel"
                options: [2, 5, 10].map(v => ({ "value": v, "label": `${v} %` }))
                current: root.s.volumeStep
                onPicked: v => root.s.volumeStep = v
            }
        }
    }

    Component {
        id: picture
        ColumnLayout {
            spacing: 2
            ChoiceRow {
                icon: "aspect_ratio"; label: "How the picture fills the window"; description: "Z cycles through these"
                options: root.fitOptions; current: root.s.fit
                onPicked: v => root.s.fit = v
            }
            SettingRow {
                icon: "subtitles"; label: "Subtitles on by default"
                description: "Turn the first subtitle track on when a file has one"
                hasSwitch: true; checked: root.s.subtitlesOn
                onToggled: on => root.s.subtitlesOn = on
            }
        }
    }

    Component {
        id: controls
        ColumnLayout {
            spacing: 2
            ChoiceRow {
                icon: "timer"; label: "Hide the controls after"
                options: [1500, 2600, 4000, 8000].map(v => ({ "value": v, "label": `${v / 1000} s` }))
                current: root.s.hideAfterMs
                onPicked: v => root.s.hideAfterMs = v
            }
            SettingRow {
                icon: "touch_app"; label: "Click the picture to pause"
                description: "A double-click still goes fullscreen"
                hasSwitch: true; checked: root.s.clickToPause
                onToggled: on => root.s.clickToPause = on
            }
            SettingRow {
                icon: "preview"; label: "Preview on the timeline"
                description: "A still of that moment above the pointer"
                hasSwitch: true; checked: root.s.seekPreview
                onToggled: on => root.s.seekPreview = on
            }
            ChoiceRow {
                icon: "schedule"; label: "The clock shows"; description: "Clicking it switches too"
                options: [{ "value": "elapsed", "label": "Elapsed" }, { "value": "remaining", "label": "Time left" }]
                current: root.s.timeDisplay
                onPicked: v => root.s.timeDisplay = v
            }
            SettingRow {
                icon: "notifications"; label: "Show what a key did"
                description: "\"Volume 70 %\", \"+10 s\" for a moment"
                hasSwitch: true; checked: root.s.osd
                onToggled: on => root.s.osd = on
            }
            ChoiceRow {
                visible: root.s.osd
                icon: "vertical_align_center"; label: "Where it appears"
                options: [{ "value": "top", "label": "Top" }, { "value": "center", "label": "Middle" }, { "value": "bottom", "label": "Bottom" }]
                current: root.s.osdPosition
                onPicked: v => root.s.osdPosition = v
            }

            StyledText {
                Layout.topMargin: 12
                Layout.leftMargin: 12
                text: "BUTTONS"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }
            SettingRow {
                icon: "title"; label: "Title and folder at the top"
                hasSwitch: true; checked: root.s.showTitle
                onToggled: on => root.s.showTitle = on
            }
            SettingRow {
                icon: "skip_next"; label: "Previous / next video"
                hasSwitch: true; checked: root.s.showFolderButtons
                onToggled: on => root.s.showFolderButtons = on
            }
            SettingRow {
                icon: "frame_inspect"; label: "Frame step (while paused)"
                hasSwitch: true; checked: root.s.showFrameButtons
                onToggled: on => root.s.showFrameButtons = on
            }
            SettingRow {
                icon: "photo_camera"; label: "Save frame"
                hasSwitch: true; checked: root.s.showScreenshotButton
                onToggled: on => root.s.showScreenshotButton = on
            }
            SettingRow {
                icon: "slow_motion_video"; label: "Speed"
                hasSwitch: true; checked: root.s.showSpeedButton
                onToggled: on => root.s.showSpeedButton = on
            }
            SettingRow {
                icon: "repeat"; label: "Loop"
                hasSwitch: true; checked: root.s.showLoopButton
                onToggled: on => root.s.showLoopButton = on
            }
        }
    }

    Component {
        id: look
        ColumnLayout {
            spacing: 2
            ChoiceRow {
                icon: "palette"; label: "Accent colour"
                description: "Theme follows your wallpaper; the others are fixed"
                options: root.accentOptions; current: root.s.accent
                onPicked: v => root.s.accent = v
            }
            ChoiceRow {
                icon: "dock_to_bottom"; label: "Controls"
                options: [{ "value": "scrim", "label": "On the picture" }, { "value": "pill", "label": "In a card" }]
                current: root.s.controlStyle
                onPicked: v => root.s.controlStyle = v
            }
            SettingRow {
                icon: "radio_button_checked"; label: "Filled play button"
                hasSwitch: true; checked: root.s.filledPlay
                onToggled: on => root.s.filledPlay = on
            }
            ChoiceRow {
                icon: "web_asset"; label: "Title bar"
                description: "System is the bar your other windows have"
                options: [{ "value": "system", "label": "System" }, { "value": "own", "label": "reel's own" }]
                current: root.s.titleBar
                onPicked: v => root.s.titleBar = v
            }
            ChoiceRow {
                visible: root.s.titleBar !== "system"
                icon: "more_horiz"; label: "Window buttons"
                description: "Dots match the title bars of your other windows"
                options: [{ "value": "dots", "label": "Dots" }, { "value": "icons", "label": "Icons" }]
                current: root.s.windowButtons
                onPicked: v => root.s.windowButtons = v
            }
            ChoiceRow {
                icon: "side_navigation"; label: "Panels open on the"
                options: [{ "value": "right", "label": "Right" }, { "value": "left", "label": "Left" }]
                current: root.s.playlistSide
                onPicked: v => root.s.playlistSide = v
            }
            ChoiceRow {
                icon: "blur_on"; label: "Panels"
                options: [{ "value": "solid", "label": "Solid" }, { "value": "glass", "label": "See-through" }]
                current: root.s.panelStyle
                onPicked: v => root.s.panelStyle = v
            }
            SettingRow {
                icon: "photo_library"; label: "Thumbnails in the folder list"
                hasSwitch: true; checked: root.s.playlistThumbs
                onToggled: on => root.s.playlistThumbs = on
            }
        }
    }

    Component {
        id: screenshots
        ColumnLayout {
            spacing: 2
            ChoiceRow {
                icon: "folder"; label: "Save to"
                options: root.dirOptions; current: root.s.screenshotDir
                onPicked: v => root.s.screenshotDir = v
            }
            ChoiceRow {
                icon: "image"; label: "Format"
                options: [{ "value": "png", "label": "PNG — exact" }, { "value": "jpg", "label": "JPG — small" }]
                current: root.s.screenshotFormat
                onPicked: v => root.s.screenshotFormat = v
            }
            SettingRow {
                icon: "content_paste"; label: "Also copy it"
                description: "The frame is on the clipboard, ready to paste"
                hasSwitch: true; checked: root.s.screenshotCopy
                onToggled: on => root.s.screenshotCopy = on
            }
        }
    }

    Component {
        id: history
        ColumnLayout {
            spacing: 2
            SettingRow {
                icon: "history"; label: "Remember what I watched"
                description: "Where you stopped in each file, for resuming and the folder list"
                hasSwitch: true; checked: root.s.history
                onToggled: on => root.s.history = on
            }
            SettingRow {
                icon: "delete_sweep"; label: "Forget everything"
                description: "Every position and the list of what you watched"
                destructive: true
                onClicked: root.forgetHistory()
            }
        }
    }
}
