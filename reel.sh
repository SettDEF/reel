#!/bin/bash
# reel [FILE]
#
# Starts reeld if it is not answering, then hands FILE to a running reel
# window, or opens a new one. The UI is a quickshell config (shell.qml);
# quarry's daemon client inside it is pointed at reeld's socket.
set -u
HERE=$(dirname "$(readlink -f "$0")")
SHELL_QML=$HERE/shell.qml
REELD=${REELD:-$(command -v reeld || echo /mnt/storage/dev-cache/targets/release/reeld)}
export REEL_SOCK=${REEL_SOCK:-${XDG_RUNTIME_DIR:-/tmp}/reel/sock}
export QUARRY_SOCK=$REEL_SOCK
export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$HOME/.local/lib/qt6/qml}

file=${1:-}
if [ -n "$file" ]; then
  case $file in
    file://*) file=${file#file://} ;;
  esac
  file=$(readlink -f -- "$file" || echo "$file")
fi

# The daemon: one per session, started on demand.
if ! [ -S "$REEL_SOCK" ] || ! printf '' | timeout 1 socat - "UNIX-CONNECT:$REEL_SOCK" 2>/dev/null; then
  setsid "$REELD" --socket "$REEL_SOCK" </dev/null >/dev/null 2>&1 &
  for _ in $(seq 1 20); do [ -S "$REEL_SOCK" ] && break; sleep 0.05; done
fi

# A reel already open takes the file; otherwise a new window.
if [ -n "$file" ] && qs -p "$SHELL_QML" ipc call reel open "$file" >/dev/null 2>&1; then
  exit 0
fi
REEL_OPEN=$file exec qs -n -p "$SHELL_QML"
