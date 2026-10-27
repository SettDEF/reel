pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * VIEWERS — what reel opens besides video.
 *
 * A viewer is a folder with a manifest and the QML it names:
 *
 *   viewers/<id>/manifest.json   { "id", "name", "exts": ["pdf"], "entry": "Viewer.qml" }
 *   viewers/<id>/Viewer.qml      an Item with `property string path`,
 *                                `signal step(int delta)` (arrow keys: next file)
 *
 * Shipped ones live beside shell.qml; yours in ~/.local/share/reel/viewers and
 * win over a shipped one with the same id. A file whose extension no viewer
 * claims is a video (or audio) and goes to the player, as before.
 */
Singleton {
    id: root

    readonly property string appDir: Quickshell.shellDir + "/viewers"
    readonly property string userDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/reel/viewers"
    /// [{ id, name, exts, url, user }]
    property var list: []

    function extOf(path) {
        const name = String(path).split("/").pop();
        const i = name.lastIndexOf(".");
        return i > 0 ? name.slice(i + 1).toLowerCase() : "";
    }
    /// the viewer for a file, or null (the player's)
    function viewerFor(path) {
        const e = root.extOf(path);
        if (!e) return null;
        return root.list.find(v => v.exts.includes(e)) ?? null;
    }

    function rescan() { scan.running = false; scan.running = true; }
    Process {
        id: scan
        running: true
        // one line per manifest: <dir>\t<json on one line>
        command: ["sh", "-c", 'for d in "$1" "$2"; do for m in "$d"/*/manifest.json; do [ -f "$m" ] && printf "%s\\t%s\\n" "$(dirname "$m")" "$(tr -d "\\n" < "$m")"; done; done', "sh", root.appDir, root.userDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const byId = {};
                for (const line of this.text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const dir = line.slice(0, tab);
                    try {
                        const m = JSON.parse(line.slice(tab + 1));
                        if (!m.id || !Array.isArray(m.exts)) continue;
                        byId[m.id] = { id: m.id, name: m.name ?? m.id, exts: m.exts.map(x => String(x).toLowerCase()),
                                       url: "file://" + dir + "/" + (m.entry ?? "Viewer.qml"), user: dir.startsWith(root.userDir) };
                    } catch (e) { console.warn(`reel: viewer manifest in ${dir}: ${e}`); }
                }
                root.list = Object.values(byId);
            }
        }
    }

    // ── the files beside one, that the same viewer opens: for the arrow keys ──
    property var siblings: []
    property int siblingIndex: -1
    function folder(path) {
        const v = root.viewerFor(path);
        if (!v) { root.siblings = []; root.siblingIndex = -1; return; }
        sib.want = path;
        sib.exts = v.exts;
        sib.command = ["sh", "-c", 'find "$1" -maxdepth 1 -type f -printf "%f\\n" 2>/dev/null', "sh", path.slice(0, path.lastIndexOf("/"))];
        sib.running = false; sib.running = true;
    }
    Process {
        id: sib
        property string want: ""
        property var exts: []
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = sib.want.slice(0, sib.want.lastIndexOf("/"));
                const names = this.text.split("\n").filter(n => n && sib.exts.includes(root.extOf(n)));
                // natural order: page2 before page10
                names.sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" }));
                root.siblings = names.map(n => dir + "/" + n);
                root.siblingIndex = root.siblings.indexOf(sib.want);
            }
        }
    }
}
