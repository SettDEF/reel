import QtQuick

/*
 * IMAGES — reel's picture viewer.
 *
 * Opens fitted. Mouse wheel zooms at the pointer; on a touchpad pinch zooms and
 * two fingers pan (Ctrl + scroll zooms too); drag pans; double-click toggles
 * fit / 100 %. The picture never leaves a gap at an edge it could fill, and is
 * centred while smaller than the window. Pixels stay crisp from 200 %, SVGs are
 * drawn again at the size shown. The neighbours (`neighbours`, set by reel)
 * load ahead, so the next one is there at once.
 *
 * Keys: ← → previous / next, Ctrl+← → first / last, + − (Ctrl+↑ ↓) zoom, 0 fit,
 * F fill, 1 / 2 actual / double size, Shift+arrows / hjkl pan, R / Shift+R or
 * Alt+→ ← rotate, H or Alt+↑↓ flip, S slideshow (4 s), I info. Wheel: zoom;
 * Ctrl finer, Shift sideways, Alt previous / next. Other Ctrl / Alt chords go
 * to reel. Plain QtQuick only, as every viewer should be.
 */
FocusScope {
    id: v
    property string path: ""
    property var neighbours: []
    property int index: -1
    property int count: 0
    property color fg: "white"
    property color dim: "#aaffffff"
    property color accent: "#8ab4f8"
    property color panel: "#cc1a1a1a"
    signal step(int delta)
    focus: true
    clip: true

    // ── state: the scale (screen px per image px) and where the picture's corner is ──
    property real s: 1
    property real ox: 0
    property real oy: 0
    /// "fit" follows the window; "free" is wherever the user zoomed
    property string mode: "fit"
    property int turn: 0
    property bool flipped: false
    property bool slideshow: false
    property bool info: true

    readonly property bool animated: /\.(gif|webp)$/i.test(v.path) && anim.frameCount > 1
    readonly property bool vector: /\.svgz?$/i.test(v.path)
    readonly property var pic: v.animated ? anim : still
    // an SVG's own size comes from a copy drawn at it (the shown one is redrawn at the zoom)
    readonly property var sized: v.vector ? probe : v.pic
    readonly property real picW: v.sized.implicitWidth > 0 ? v.sized.implicitWidth : v.sized.sourceSize.width
    readonly property real picH: v.sized.implicitHeight > 0 ? v.sized.implicitHeight : v.sized.sourceSize.height
    readonly property real natW: v.turn % 2 ? v.picH : v.picW
    readonly property real natH: v.turn % 2 ? v.picW : v.picH
    readonly property bool ready: v.natW > 0 && v.natH > 0 && v.width > 0
    /// fitted: whole picture in the window, small ones at their own size
    readonly property real fitScale: v.ready ? Math.min(v.width / v.natW, v.height / v.natH, 1) : 1
    readonly property real fillScale: v.ready ? Math.max(v.width / v.natW, v.height / v.natH) : 1
    readonly property real minScale: Math.min(v.fitScale, 1) * 0.5
    readonly property real maxScale: 64
    readonly property real shownW: v.natW * v.s
    readonly property real shownH: v.natH * v.s

    function clampPos() {
        v.ox = v.shownW <= v.width ? (v.width - v.shownW) / 2 : Math.min(0, Math.max(v.width - v.shownW, v.ox));
        v.oy = v.shownH <= v.height ? (v.height - v.shownH) / 2 : Math.min(0, Math.max(v.height - v.shownH, v.oy));
    }
    /// scale `to`, keeping the image point under (px, py) where it is
    function scaleAt(to, px, py) {
        to = Math.max(v.minScale, Math.min(v.maxScale, to));
        const k = to / v.s;
        v.ox = px - (px - v.ox) * k;
        v.oy = py - (py - v.oy) * k;
        v.s = to;
        v.clampPos();
    }
    function zoomAt(f, px, py) { v.mode = "free"; v.scaleAt(v.s * f, px, py); }
    function fit() { v.mode = "fit"; v.s = v.fitScale; v.clampPos(); }
    function fill() { v.mode = "free"; v.scaleAt(v.fillScale, v.width / 2, v.height / 2); }
    function actualAt(px, py) { v.mode = "free"; v.scaleAt(1, px, py); }
    function pan(dx, dy) { v.ox += dx; v.oy += dy; v.clampPos(); }

    // smooth steps for keys and double-click: the same anchor, animated
    property real animTo: 1
    property real animPx: 0
    property real animPy: 0
    function zoomSmooth(to, px, py) {
        v.mode = "free";
        v.animTo = Math.max(v.minScale, Math.min(v.maxScale, to));
        v.animPx = px; v.animPy = py;
        zoomAnim.from = v.s; zoomAnim.to = v.animTo;
        zoomAnim.restart();
    }
    NumberAnimation {
        id: zoomAnim
        target: zoomProxy; property: "value"
        duration: 160; easing.type: Easing.OutCubic
    }
    QtObject {
        id: zoomProxy
        property real value: 1
        onValueChanged: if (zoomAnim.running) v.scaleAt(value, v.animPx, v.animPy)
    }

    onPathChanged: { v.turn = 0; v.flipped = false; v.mode = "fit"; v.s = 0.0001; v.svgSize = Qt.size(0, 0); v.showInfo(); }
    onReadyChanged: if (v.ready && v.mode === "fit") v.fit()
    onFitScaleChanged: if (v.mode === "fit") v.fit()
    onWidthChanged: v.mode === "fit" ? v.fit() : v.clampPos()
    onHeightChanged: v.mode === "fit" ? v.fit() : v.clampPos()
    onTurnChanged: v.fit()

    Keys.onPressed: (e) => {
        const k = e.key, shift = e.modifiers & Qt.ShiftModifier, ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier, cx = v.width / 2, cy = v.height / 2;
        // with a modifier: Ctrl+arrows first / last (Ctrl+↑↓ zoom), Alt+arrows rotate (Alt+↑↓ flip), Ctrl+R / Ctrl+Shift+R rotate
        if (ctrl && (k === Qt.Key_Left || k === Qt.Key_Home)) { v.step(-Math.max(1, v.index)); e.accepted = true; return; }
        if (ctrl && (k === Qt.Key_Right || k === Qt.Key_End)) { v.step(Math.max(1, v.count - 1 - v.index)); e.accepted = true; return; }
        if (ctrl && k === Qt.Key_Up) { v.zoomSmooth(v.s * 1.5, cx, cy); e.accepted = true; v.showInfo(); return; }
        if (ctrl && k === Qt.Key_Down) { v.zoomSmooth(v.s / 1.5, cx, cy); e.accepted = true; v.showInfo(); return; }
        if (alt && k === Qt.Key_Right) { v.turn = (v.turn + 1) % 4; e.accepted = true; return; }
        if (alt && k === Qt.Key_Left) { v.turn = (v.turn + 3) % 4; e.accepted = true; return; }
        if (alt && (k === Qt.Key_Up || k === Qt.Key_Down)) { v.flipped = !v.flipped; e.accepted = true; return; }
        // other Ctrl / Alt chords (Ctrl+C copy, Ctrl+Q …) are reel's
        if ((ctrl || alt) && !(k === Qt.Key_Plus || k === Qt.Key_Equal || k === Qt.Key_Minus || k === Qt.Key_0 || k === Qt.Key_R)) { e.accepted = false; return; }
        const zoomed = v.shownW > v.width + 1 || v.shownH > v.height + 1;
        const stepPx = Math.max(60, Math.min(v.width, v.height) / 6);
        if ((shift || zoomed) && (k === Qt.Key_Left || k === Qt.Key_H && !shift)) v.pan(stepPx, 0);
        else if ((shift || zoomed) && (k === Qt.Key_Right || k === Qt.Key_L)) v.pan(-stepPx, 0);
        else if ((shift || zoomed) && (k === Qt.Key_Up || k === Qt.Key_K)) v.pan(0, stepPx);
        else if ((shift || zoomed) && (k === Qt.Key_Down || k === Qt.Key_J)) v.pan(0, -stepPx);
        else if (k === Qt.Key_Right || k === Qt.Key_Space || k === Qt.Key_PageDown) v.step(1);
        else if (k === Qt.Key_Left || k === Qt.Key_Backspace || k === Qt.Key_PageUp) v.step(-1);
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) v.zoomSmooth(v.s * 1.5, cx, cy);
        else if (k === Qt.Key_Minus) v.zoomSmooth(v.s / 1.5, cx, cy);
        else if (k === Qt.Key_0) v.fit();
        else if (k === Qt.Key_F) v.mode === "fit" ? v.fill() : v.fit();
        else if (k === Qt.Key_1) v.zoomSmooth(1, cx, cy);
        else if (k === Qt.Key_2) v.zoomSmooth(2, cx, cy);
        else if (k === Qt.Key_R) v.turn = (v.turn + (shift ? 3 : 1)) % 4;
        else if (k === Qt.Key_H) v.flipped = !v.flipped;
        else if (k === Qt.Key_S) v.slideshow = !v.slideshow;
        else if (k === Qt.Key_I) v.info = !v.info;
        else if (k === Qt.Key_Home) v.step(-Math.max(1, v.index));
        else if (k === Qt.Key_End) v.step(Math.max(1, v.count - 1 - v.index));
        else { e.accepted = false; return; }
        e.accepted = true;
        v.showInfo();
    }
    Timer { interval: 4000; repeat: true; running: v.slideshow && v.visible; onTriggered: v.step(1) }

    Rectangle { anchors.fill: parent; color: "#0b0b0d" }

    // ── the picture ──
    Item {
        id: frame
        x: v.ox; y: v.oy
        width: v.shownW; height: v.shownH
        visible: v.ready

        // transparency shows as a soft checkerboard (opaque pictures cover it)
        Image {
            anchors.fill: parent
            fillMode: Image.Tile
            smooth: false
            source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect width='16' height='16' fill='%23202024'/><rect width='8' height='8' fill='%232c2c31'/><rect x='8' y='8' width='8' height='8' fill='%232c2c31'/></svg>"
        }

        Item {
            id: turnBox
            anchors.centerIn: parent
            width: (v.turn % 2 ? v.natH : v.natW) * v.s
            height: (v.turn % 2 ? v.natW : v.natH) * v.s
            rotation: v.turn * 90
            transform: Scale { origin.x: turnBox.width / 2; origin.y: 0; xScale: v.flipped ? -1 : 1 }

            Image {
                id: still
                anchors.fill: parent
                visible: !v.animated
                source: !v.path ? "" : "file://" + v.path
                asynchronous: true
                cache: false
                autoTransform: true
                fillMode: Image.Stretch
                // crisp pixels when zoomed in, smooth (and mipmapped) when shrunk
                smooth: v.vector || v.s < 2
                mipmap: !v.vector && v.s < 1
                // SVGs drawn at the size shown (settled, not on every wheel tick)
                sourceSize: v.vector && svgSize.width > 0 ? svgSize : undefined
            }
            AnimatedImage {
                id: anim
                anchors.fill: parent
                visible: v.animated
                source: /\.(gif|webp)$/i.test(v.path) ? "file://" + v.path : ""
                smooth: v.s < 2
                fillMode: Image.Stretch
            }
        }
    }
    property size svgSize: Qt.size(0, 0)
    Image { id: probe; visible: false; source: v.vector ? "file://" + v.path : ""; asynchronous: true }
    Timer {
        id: svgTimer
        interval: 150
        onTriggered: v.svgSize = Qt.size(Math.min(16384, Math.round((v.turn % 2 ? v.natH : v.natW) * v.s)), Math.min(16384, Math.round((v.turn % 2 ? v.natW : v.natH) * v.s)))
    }
    onSChanged: if (v.vector) svgTimer.restart()

    // the next and previous ones, decoded ahead (not shown)
    Repeater {
        model: v.neighbours.filter(p => p && !/\.(gif|svgz?)$/i.test(p)).slice(0, 2)
        Image { visible: false; asynchronous: true; autoTransform: true; source: "file://" + modelData; sourceSize: Qt.size(Math.round(v.width * 2), Math.round(v.height * 2)) }
    }

    // ── input ──
    DragHandler {
        id: drag
        target: null
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        property real lx: 0
        property real ly: 0
        onActiveChanged: { lx = 0; ly = 0; }
        onTranslationChanged: { v.pan(translation.x - lx, translation.y - ly); lx = translation.x; ly = translation.y; }
        cursorShape: active ? Qt.ClosedHandCursor : (v.shownW > v.width + 1 || v.shownH > v.height + 1 ? Qt.OpenHandCursor : Qt.ArrowCursor)
    }
    PinchHandler {
        id: pinch
        target: null
        property real base: 1
        onActiveChanged: if (active) base = v.s
        onActiveScaleChanged: { v.mode = "free"; v.scaleAt(base * activeScale, centroid.position.x, centroid.position.y); }
        onTranslationChanged: {}
    }
    WheelHandler {
        // a mouse wheel zooms; a touchpad pans, Ctrl + touchpad zooms
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (w) => {
            const touch = w.pixelDelta.x !== 0 || w.pixelDelta.y !== 0;
            if (touch && !(w.modifiers & Qt.ControlModifier)) {
                v.pan(w.pixelDelta.x, w.pixelDelta.y);
            } else {
                const d = w.angleDelta.y !== 0 ? w.angleDelta.y / 120 : w.pixelDelta.y / 40;
                if (w.modifiers & Qt.ShiftModifier) v.pan(d * 120, 0);          // Shift+wheel: sideways
                else if (w.modifiers & Qt.AltModifier) wheelStep.go(d);         // Alt+wheel: previous / next picture
                else v.zoomAt(Math.pow(w.modifiers & Qt.ControlModifier ? 1.05 : 1.2, d), w.x, w.y);   // Ctrl: finer
            }
            v.showInfo();
        }
    }
    // Alt+wheel walks the folder: one picture per notch, not a burst from a touchpad
    QtObject {
        id: wheelStep
        property real last: 0
        function go(d) { const now = Date.now(); if (now - last < 180 || d === 0) return; last = now; v.step(d > 0 ? -1 : 1); }
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: (pt) => {
            if (v.mode === "fit" && Math.abs(v.s - 1) > 0.01) v.zoomSmooth(1, pt.position.x, pt.position.y);
            else { v.mode = "fit"; v.zoomSmooth(v.fitScale, pt.position.x, pt.position.y); fitAfter.restart(); }
        }
        onTapped: v.forceActiveFocus()
    }
    Timer { id: fitAfter; interval: 170; onTriggered: v.fit() }
    HoverHandler { onPointChanged: v.showInfo() }

    // ── what it is, where in the folder; fades when the pointer rests ──
    function showInfo() { infoBox.shown = true; infoHide.restart(); }
    Timer { id: infoHide; interval: 2200; onTriggered: infoBox.shown = false }
    Rectangle {
        id: infoBox
        property bool shown: true
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        implicitWidth: infoRow.implicitWidth + 24; implicitHeight: 30; radius: 15
        color: v.panel
        opacity: v.info && (shown || v.slideshow) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        Row {
            id: infoRow
            anchors.centerIn: parent
            spacing: 14
            Text { text: v.path.split("/").pop(); color: v.fg; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideMiddle; width: Math.min(implicitWidth, v.width * 0.4) }
            Text { visible: v.picW > 0; text: `${v.picW} × ${v.picH}`; color: v.dim; font.pixelSize: 12 }
            Text { text: v.mode === "fit" ? `fit · ${Math.round(v.s * 100)} %` : `${Math.round(v.s * 100)} %`; color: v.mode === "fit" ? v.dim : v.accent; font.pixelSize: 12 }
            Text { visible: v.count > 1 && v.index >= 0; text: `${v.index + 1} / ${v.count}`; color: v.dim; font.pixelSize: 12 }
            Text { visible: v.slideshow; text: "slideshow"; color: v.accent; font.pixelSize: 12 }
        }
    }

    // where the window is in a zoomed picture
    Rectangle {
        id: mini
        readonly property bool want: v.ready && (v.shownW > v.width * 1.05 || v.shownH > v.height * 1.05)
        readonly property real k: Math.min(150 / v.natW, 110 / v.natH)
        anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
        width: v.natW * k + 8; height: v.natH * k + 8; radius: 8
        color: v.panel
        opacity: want && infoBox.opacity > 0 ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        Image {
            x: 4; y: 4; width: v.natW * mini.k; height: v.natH * mini.k
            source: v.animated || !v.path || !mini.want ? "" : "file://" + v.path
            sourceSize: Qt.size(300, 300)
            asynchronous: true; autoTransform: true
            rotation: v.turn * 90
            fillMode: Image.PreserveAspectFit
            opacity: 0.85
        }
        Rectangle {
            x: 4 + Math.max(0, -v.ox / v.s * mini.k)
            y: 4 + Math.max(0, -v.oy / v.s * mini.k)
            width: Math.min(v.natW, v.width / v.s) * mini.k
            height: Math.min(v.natH, v.height / v.s) * mini.k
            color: "transparent"; border.width: 1.5; border.color: v.accent; radius: 2
        }
    }

    Text {
        anchors.centerIn: parent
        visible: v.pic.status === Image.Error
        text: "This picture cannot be read (" + v.path.split(".").pop() + ")."
        color: v.dim
        font.pixelSize: 14
    }
    Text {
        anchors.centerIn: parent
        visible: v.pic.status === Image.Loading
        text: "Loading…"
        color: v.dim
        font.pixelSize: 13
    }
}
