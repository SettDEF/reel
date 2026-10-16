//! reeld — reel's daemon.
//!
//! What a video player has to remember between runs, and the work it should
//! not do on the UI thread:
//!
//! - **progress**: where you stopped in every file, so it opens there again;
//! - **recent**: what you watched, newest first;
//! - **folder**: the other videos next to a file, in natural order
//!   ("ep 2" before "ep 10"), which is the playlist;
//! - **thumb**: a still from a file at a time, through ffmpeg, cached.
//!
//! Speaks quarry's wire protocol — one JSON frame per line,
//! `{"t":"req","id":1,"m":"progress.get","p":{...}}` answered by
//! `{"t":"res","id":1,"ok":true,"p":{...}}` — so quarry's Client.qml works
//! against it unchanged.
//!
//!   reeld [--socket PATH]

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{Mutex, Notify};

const VIDEO_EXT: &[&str] = &[
    "mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "ts", "m2ts", "ogv", "3gp",
];
/// Closer than this to the end counts as watched: the next open starts over
/// rather than on the credits.
const FINISHED_TAIL_S: f64 = 30.0;
const FINISHED_SHARE: f64 = 0.95;
const RECENT_MAX: usize = 300;

// ── protocol (quarry's frames) ──────────────────────────────────────────

#[derive(Deserialize)]
struct Request {
    id: u64,
    m: String,
    #[serde(default)]
    p: Value,
}

#[derive(Serialize)]
struct Response {
    t: &'static str,
    id: u64,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    p: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    err: Option<String>,
}

impl Response {
    fn ok(id: u64, p: Value) -> Self {
        Response { t: "res", id, ok: true, p: Some(p), err: None }
    }
    fn err(id: u64, e: impl Into<String>) -> Self {
        Response { t: "res", id, ok: false, p: None, err: Some(e.into()) }
    }
}

// ── the library: one JSON file ──────────────────────────────────────────

#[derive(Clone, Serialize, Deserialize, Default)]
struct Entry {
    /// Seconds into the file; 0 once it was watched to the end.
    pos: f64,
    /// Seconds long, as last reported by the player.
    dur: f64,
    /// Unix seconds of the last time it was playing.
    at: u64,
    #[serde(default)]
    finished: bool,
}

#[derive(Serialize, Deserialize, Default)]
struct Library {
    #[serde(default)]
    files: HashMap<String, Entry>,
}

struct Server {
    lib: Mutex<Library>,
    lib_path: PathBuf,
    thumb_dir: PathBuf,
    /// Wakes the writer; saves are coalesced so a position report every few
    /// seconds is not a disk write every few seconds.
    dirty: Notify,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
}

fn is_video(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| VIDEO_EXT.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

/// "ep 2" < "ep 10": digit runs compare as numbers, everything else
/// case-insensitively.
fn natural_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    let (mut a, mut b) = (a.chars().peekable(), b.chars().peekable());
    loop {
        match (a.peek().copied(), b.peek().copied()) {
            (None, None) => return std::cmp::Ordering::Equal,
            (None, _) => return std::cmp::Ordering::Less,
            (_, None) => return std::cmp::Ordering::Greater,
            (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                let take = |it: &mut std::iter::Peekable<std::str::Chars>| {
                    let mut s = String::new();
                    while let Some(c) = it.peek().copied().filter(|c| c.is_ascii_digit()) {
                        s.push(c);
                        it.next();
                    }
                    s
                };
                let (na, nb) = (take(&mut a), take(&mut b));
                let (ta, tb) = (na.trim_start_matches('0'), nb.trim_start_matches('0'));
                let ord = ta.len().cmp(&tb.len()).then_with(|| ta.cmp(tb));
                if ord != std::cmp::Ordering::Equal {
                    return ord;
                }
            }
            (Some(x), Some(y)) => {
                let ord = x.to_lowercase().cmp(y.to_lowercase());
                if ord != std::cmp::Ordering::Equal {
                    return ord;
                }
                a.next();
                b.next();
            }
        }
    }
}

fn path_param(p: &Value) -> Result<String, String> {
    p.get("path")
        .and_then(|v| v.as_str())
        .map(|s| s.trim_start_matches("file://").to_string())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "missing \"path\"".to_string())
}

impl Server {
    async fn handle(self: &Arc<Self>, req: Request) -> Response {
        let id = req.id;
        let result: Result<Value, String> = match req.m.as_str() {
            "hello" => Ok(json!({ "protocol": 1, "backend": "reel", "items": self.lib.lock().await.files.len(), "stale": false, "pid": std::process::id(), "version": env!("CARGO_PKG_VERSION") })),
            "progress.get" => self.progress_get(&req.p).await,
            "progress.set" => self.progress_set(&req.p).await,
            "forget" => self.forget(&req.p).await,
            "clear" => {
                let n = std::mem::take(&mut self.lib.lock().await.files).len();
                self.dirty.notify_one();
                Ok(json!({ "removed": n }))
            }
            "recent" => self.recent(&req.p).await,
            "folder" => folder(&req.p).await,
            "thumb" => self.thumb(&req.p).await,
            other => Err(format!("unknown method {other}")),
        };
        match result {
            Ok(p) => Response::ok(id, p),
            Err(e) => Response::err(id, e),
        }
    }

    async fn progress_get(&self, p: &Value) -> Result<Value, String> {
        let path = path_param(p)?;
        let lib = self.lib.lock().await;
        Ok(match lib.files.get(&path) {
            Some(e) => json!({ "pos": if e.finished { 0.0 } else { e.pos }, "dur": e.dur, "finished": e.finished, "at": e.at }),
            None => json!({ "pos": 0.0, "dur": 0.0, "finished": false, "at": 0 }),
        })
    }

    async fn progress_set(&self, p: &Value) -> Result<Value, String> {
        let path = path_param(p)?;
        let pos = p.get("pos").and_then(|v| v.as_f64()).unwrap_or(0.0).max(0.0);
        let dur = p.get("dur").and_then(|v| v.as_f64()).unwrap_or(0.0).max(0.0);
        let finished = dur > 0.0 && (pos >= dur - FINISHED_TAIL_S.min(dur * 0.1) || pos >= dur * FINISHED_SHARE);
        {
            let mut lib = self.lib.lock().await;
            lib.files.insert(path, Entry { pos: if finished { 0.0 } else { pos }, dur, at: now(), finished });
            if lib.files.len() > RECENT_MAX {
                // Drop the oldest; nobody resumes something from 300 files ago.
                let mut by_age: Vec<(String, u64)> = lib.files.iter().map(|(k, e)| (k.clone(), e.at)).collect();
                by_age.sort_by_key(|(_, at)| *at);
                for (k, _) in by_age.into_iter().take(lib.files.len() - RECENT_MAX) {
                    lib.files.remove(&k);
                }
            }
        }
        self.dirty.notify_one();
        Ok(json!({ "finished": finished }))
    }

    async fn forget(&self, p: &Value) -> Result<Value, String> {
        let path = path_param(p)?;
        let removed = self.lib.lock().await.files.remove(&path).is_some();
        self.dirty.notify_one();
        Ok(json!({ "removed": removed }))
    }

    async fn recent(&self, p: &Value) -> Result<Value, String> {
        let limit = p.get("limit").and_then(|v| v.as_u64()).unwrap_or(30) as usize;
        let lib = self.lib.lock().await;
        let mut rows: Vec<(&String, &Entry)> = lib.files.iter().filter(|(k, _)| Path::new(k).exists()).collect();
        rows.sort_by(|a, b| b.1.at.cmp(&a.1.at));
        let rows: Vec<Value> = rows
            .into_iter()
            .take(limit)
            .map(|(k, e)| {
                json!({
                    "path": k,
                    "title": Path::new(k).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
                    "pos": e.pos, "dur": e.dur, "at": e.at, "finished": e.finished,
                })
            })
            .collect();
        Ok(json!({ "items": rows }))
    }

    /// A still from `path` at `at` seconds (default 10 % in), `w` px wide.
    /// Cached by path + mtime + time + width, so it is made once.
    async fn thumb(&self, p: &Value) -> Result<Value, String> {
        let path = path_param(p)?;
        let w = p.get("w").and_then(|v| v.as_u64()).unwrap_or(320).clamp(64, 1920);
        let meta = tokio::fs::metadata(&path).await.map_err(|e| format!("{path}: {e}"))?;
        let mtime = meta.modified().ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_secs()).unwrap_or(0);
        let at = match p.get("at").and_then(|v| v.as_f64()) {
            Some(a) => a.max(0.0),
            None => {
                let dur = self.lib.lock().await.files.get(&path).map(|e| e.dur).unwrap_or(0.0);
                if dur > 0.0 { dur * 0.1 } else { 3.0 }
            }
        };
        let key = {
            use std::hash::{Hash, Hasher};
            let mut h = std::collections::hash_map::DefaultHasher::new();
            (&path, mtime, (at * 10.0) as u64, w).hash(&mut h);
            format!("{:016x}", h.finish())
        };
        let out = self.thumb_dir.join(format!("{key}.jpg"));
        if !out.exists() {
            tokio::fs::create_dir_all(&self.thumb_dir).await.map_err(|e| e.to_string())?;
            let tmp = self.thumb_dir.join(format!("{key}.tmp.jpg"));
            let run = |seek: f64| {
                let mut c = tokio::process::Command::new("ffmpeg");
                c.args(["-v", "error", "-y", "-ss", &format!("{seek:.3}"), "-i"])
                    .arg(&path)
                    .args(["-frames:v", "1", "-vf", &format!("scale={w}:-2"), "-q:v", "4"])
                    .arg(&tmp)
                    .stdin(std::process::Stdio::null())
                    .kill_on_drop(true);
                c
            };
            let ok = |o: &std::io::Result<std::process::Output>| o.as_ref().map(|o| o.status.success()).unwrap_or(false);
            let first = tokio::time::timeout(Duration::from_secs(15), run(at).output()).await.map_err(|_| "ffmpeg timed out")?;
            // Past the end (a wrong duration, a short clip): take the first frame instead.
            if !ok(&first) || !tmp.exists() {
                let again = tokio::time::timeout(Duration::from_secs(15), run(0.0).output()).await.map_err(|_| "ffmpeg timed out")?;
                if !ok(&again) {
                    let msg = again.map(|o| String::from_utf8_lossy(&o.stderr).trim().to_string()).unwrap_or_else(|e| e.to_string());
                    return Err(format!("no frame: {msg}"));
                }
            }
            tokio::fs::rename(&tmp, &out).await.map_err(|e| e.to_string())?;
        }
        Ok(json!({ "path": out.to_string_lossy() }))
    }

    /// Writes the library whenever it changed, at most every two seconds,
    /// atomically (temp file + rename) so a crash never leaves half a file.
    async fn writer(self: Arc<Self>) {
        loop {
            self.dirty.notified().await;
            tokio::time::sleep(Duration::from_secs(2)).await;
            self.save().await;
        }
    }

    async fn save(&self) {
        let data = match serde_json::to_vec_pretty(&*self.lib.lock().await) {
            Ok(d) => d,
            Err(e) => return eprintln!("reeld: encode library: {e}"),
        };
        if let Some(dir) = self.lib_path.parent() {
            let _ = tokio::fs::create_dir_all(dir).await;
        }
        let tmp = self.lib_path.with_extension("json.tmp");
        if let Err(e) = tokio::fs::write(&tmp, &data).await {
            return eprintln!("reeld: write {}: {e}", tmp.display());
        }
        if let Err(e) = tokio::fs::rename(&tmp, &self.lib_path).await {
            eprintln!("reeld: save {}: {e}", self.lib_path.display());
        }
    }
}

/// The videos next to `path`, naturally sorted, and where `path` is among them.
async fn folder(p: &Value) -> Result<Value, String> {
    let path = PathBuf::from(path_param(p)?);
    let dir = if path.is_dir() { path.clone() } else { path.parent().map(Path::to_path_buf).ok_or("no folder")? };
    let mut rd = tokio::fs::read_dir(&dir).await.map_err(|e| format!("{}: {e}", dir.display()))?;
    let mut files: Vec<String> = Vec::new();
    while let Ok(Some(e)) = rd.next_entry().await {
        let p = e.path();
        let hidden = p.file_name().and_then(|n| n.to_str()).map(|n| n.starts_with('.')).unwrap_or(true);
        if !hidden && is_video(&p) && e.file_type().await.map(|t| !t.is_dir()).unwrap_or(false) {
            files.push(p.to_string_lossy().into_owned());
        }
    }
    files.sort_by(|a, b| natural_cmp(a, b));
    let index = files.iter().position(|f| Path::new(f) == path).map(|i| i as i64).unwrap_or(-1);
    Ok(json!({ "dir": dir.to_string_lossy(), "files": files, "index": index }))
}

async fn serve(server: Arc<Server>, stream: UnixStream) {
    let (read_half, write_half) = stream.into_split();
    let writer = Arc::new(Mutex::new(write_half));
    let mut lines = BufReader::new(read_half).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        if line.trim().is_empty() {
            continue;
        }
        let server = Arc::clone(&server);
        let writer = Arc::clone(&writer);
        // Each request on its own task: a slow thumbnail never holds up a
        // position report behind it.
        tokio::spawn(async move {
            let resp = match serde_json::from_str::<Request>(&line) {
                Ok(req) => server.handle(req).await,
                Err(e) => Response::err(0, format!("bad frame: {e}")),
            };
            if let Ok(mut out) = serde_json::to_string(&resp) {
                out.push('\n');
                let _ = writer.lock().await.write_all(out.as_bytes()).await;
            }
        });
    }
}

#[tokio::main]
async fn main() {
    let mut socket = std::env::var("REEL_SOCK").map(PathBuf::from).unwrap_or_else(|_| {
        PathBuf::from(std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into())).join("reel/sock")
    });
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--socket" => socket = args.next().map(PathBuf::from).unwrap_or(socket),
            "-h" | "--help" => {
                println!("reeld [--socket PATH]");
                return;
            }
            _ => {}
        }
    }

    let state = std::env::var("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|_| home().join(".local/state"));
    let cache = std::env::var("XDG_CACHE_HOME").map(PathBuf::from).unwrap_or_else(|_| home().join(".cache"));
    let lib_path = state.join("reel/library.json");
    let lib: Library = std::fs::read(&lib_path).ok().and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default();

    let server = Arc::new(Server { lib: Mutex::new(lib), lib_path, thumb_dir: cache.join("reel/thumbs"), dirty: Notify::new() });

    // One daemon: a live socket means another reeld already answers.
    if UnixStream::connect(&socket).await.is_ok() {
        eprintln!("reeld: already running on {}", socket.display());
        return;
    }
    if let Some(dir) = socket.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::remove_file(&socket);
    let listener = match UnixListener::bind(&socket) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("reeld: bind {}: {e}", socket.display());
            std::process::exit(1);
        }
    };

    tokio::spawn(Arc::clone(&server).writer());

    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).expect("signal");
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                if let Ok((stream, _)) = accepted {
                    tokio::spawn(serve(Arc::clone(&server), stream));
                }
            }
            _ = term.recv() => break,
            _ = tokio::signal::ctrl_c() => break,
        }
    }
    // Whatever changed since the last write.
    server.save().await;
    let _ = std::fs::remove_file(&socket);
}

#[cfg(test)]
mod tests {
    use super::natural_cmp;
    use std::cmp::Ordering::*;

    #[test]
    fn natural_order() {
        assert_eq!(natural_cmp("ep 2.mkv", "ep 10.mkv"), Less);
        assert_eq!(natural_cmp("Ep 10", "ep 9"), Greater);
        assert_eq!(natural_cmp("a01", "a1"), Equal);
        assert_eq!(natural_cmp("abc", "abd"), Less);
    }
}
