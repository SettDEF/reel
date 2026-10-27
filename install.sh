#!/usr/bin/env bash
# Install reel for the current user — no root, nothing outside $HOME.
#
#   ./install.sh              build and install (or update) everything
#   ./install.sh --uninstall  remove what this script installed (your watch history stays)
#
# Puts:
#   ~/.local/bin/reeld                      the daemon (Rust): decoding, library, resume points
#   ~/.local/bin/reel                       opens a file, or the library
#   ~/.local/share/reel-app/                the window (QML) — a real copy, including the
#                                           quarry modules it shares, so later quarry work
#                                           never changes an installed reel underneath you
#   ~/.local/share/applications/reel.desktop, its icon, and the video types it opens
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
SRC=$PWD
BIN=${XDG_BIN_HOME:-$HOME/.local/bin}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
APP=$DATA/reel-app

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

for a in "$@"; do
    case $a in
        --uninstall)
            say "removing reel"
            rm -f -- "$BIN/reel" "$BIN/reeld" "$DATA/applications/reel.desktop" "$DATA/icons/hicolor/scalable/apps/reel.svg"
            [ -n "${APP:-}" ] && rm -rf -- "${APP:?}"
            say "done — watch history and settings were left in place"
            exit 0 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) die "unknown option $a (try --help)" ;;
    esac
done

command -v cargo >/dev/null || die "cargo is needed to build reeld (https://rustup.rs)"
command -v qs >/dev/null || command -v quickshell >/dev/null || die "quickshell (qs) is needed for the window"
command -v socat >/dev/null || warn "socat is not installed: reel cannot tell whether reeld is already running"

say "building reeld"
(cd reeld && nice -n 19 cargo build --release --quiet -j 4)
TARGET=${CARGO_TARGET_DIR:-$SRC/reeld/target}/release/reeld
[ -x "$TARGET" ] || die "build produced no binary at $TARGET"

say "installing reeld to $BIN"
mkdir -p "$BIN"
# a new inode: a running reeld keeps its binary until it restarts
cp -f "$TARGET" "$BIN/reeld.new"; chmod 755 "$BIN/reeld.new"; mv -f "$BIN/reeld.new" "$BIN/reeld"

say "installing the window to $APP"
rm -rf -- "${APP:?}.new"
mkdir -p "$APP.new"
cp -rL shell.qml Momentum.qml MomentumInjector.qml reel.sh reel viewers modules services "$APP.new/"
rm -rf -- "${APP:?}"
mv "$APP.new" "$APP"
# the launcher is the app's own reel.sh (it finds shell.qml beside itself)
ln -sfn "$APP/reel.sh" "$BIN/reel"

say "installing the launcher entry and icon"
mkdir -p "$DATA/applications" "$DATA/icons/hicolor/scalable/apps"
cp -f packaging/reel.svg "$DATA/icons/hicolor/scalable/apps/reel.svg"
sed "s|^Exec=reel|Exec=$BIN/reel|" packaging/reel.desktop > "$DATA/applications/reel.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$DATA/applications" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$DATA/icons/hicolor" 2>/dev/null || true

say "installed: 'reel FILE' or reel in your launcher (it also opens videos from your file manager)"
