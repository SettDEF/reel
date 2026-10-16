pragma Singleton
import QtQuick
import Quickshell
import qs.services

/*
 * What reel remembers, through reeld — over quarry's own Client, which
 * shell.qml points at reeld's socket (QUARRY_SOCK).
 *
 * Every call degrades to "nothing remembered" when the daemon is not there:
 * a player that refuses to play because its bookkeeping is down would be
 * the worse failure.
 */
Singleton {
    id: root

    /// The folder playlist of the file on screen.
    property var files: []
    property int index: -1
    readonly property bool hasNext: root.index >= 0 && root.index < root.files.length - 1
    readonly property bool hasPrev: root.index > 0

    /// path -> { pos, dur, finished } for the playlist's rows, filled as asked.
    property var progress: ({})
    property int progressRevision: 0

    function folder(path) {
        Client.call("folder", { "path": path }, function (err, p) {
            if (err || !p) {
                root.files = [path];
                root.index = 0;
                return;
            }
            root.files = p.files;
            root.index = p.index;
            for (const f of p.files) root.fetchProgress(f);
        });
    }

    function fetchProgress(path) {
        Client.call("progress.get", { "path": path }, function (err, p) {
            if (err || !p) return;
            const next = root.progress;
            next[path] = p;
            root.progress = next;
            root.progressRevision++;
        });
    }

    /// Where `path` was left, in ms, or 0 — via callback(ms).
    function resumePoint(path, callback) {
        Client.call("progress.get", { "path": path }, function (err, p) {
            callback(!err && p && !p.finished ? Math.round(p.pos * 1000) : 0);
        });
    }

    function report(path, posMs, durMs) {
        if (!path || !(durMs > 0)) return;
        Client.call("progress.set", { "path": path, "pos": posMs / 1000, "dur": durMs / 1000 }, function (err, p) {
            if (err) return;
            const next = root.progress;
            next[path] = { "pos": p.finished ? 0 : posMs / 1000, "dur": durMs / 1000, "finished": p.finished };
            root.progress = next;
            root.progressRevision++;
        });
    }

    function forget(path) {
        Client.call("forget", { "path": path }, function () { root.fetchProgress(path); });
    }

    /// A still of `path` at `sec` seconds, `w` px wide — via callback(fileUrl).
    function still(path, sec, w, callback) {
        Client.call("thumb", { "path": path, "at": sec, "w": w }, function (err, p) {
            if (!err && p && p.path) callback("file://" + p.path);
        }, 20000);
    }
    /// What was watched, newest first — via callback([{ path, title, pos, dur, at, finished }]).
    function recent(limit, callback) {
        Client.call("recent", { "limit": limit }, function (err, p) {
            callback(!err && p ? p.items : []);
        });
    }
    function clearAll(callback) {
        Client.call("clear", {}, function (err, p) {
            if (!err) { root.progress = ({}); root.progressRevision++; }
            callback(err, p);
        });
    }

    /// A cached still of `path` for the playlist — via callback(fileUrl).
    function thumb(path, callback) {
        Client.call("thumb", { "path": path, "w": 320 }, function (err, p) {
            if (!err && p && p.path) callback("file://" + p.path);
        }, 60000);
    }
}
