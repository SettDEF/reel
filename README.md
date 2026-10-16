# reel

A video player for the ii desktop: resumes where you stopped, plays the
folder in order, keeps a library of what you watched — in the same window
style as quarry, whose modules it shares.

    ./install.sh        build reeld, install the window, launcher entry and icon
    reel FILE           play a file (a running reel takes it over)
    reel                the library

- **reeld** (Rust, `reeld/`) — the daemon: library, watch history, resume
  points. Started on demand by `reel`, one per session.
- **the window** (QML, `shell.qml` + `reel/`) — playback through QtMultimedia
  (FFmpeg), keys in Settings, `?` for the list.

The installer copies the window with the quarry modules resolved
(`~/.local/share/reel-app`), so work on quarry never changes an installed reel.
Keys are also collected for the shell's cheatsheet (keybinds-sync).
