#!/usr/bin/env bash
set -euo pipefail

# validation: build, start, stop
WORKSPACE="/home/kavia/workspace/code-generation/native-notes-app-197439-197458/notes_native_app"
DEVUSER=devuser
LOGDIR="$WORKSPACE/logs"
DIST="$WORKSPACE/dist"
mkdir -p "$LOGDIR" "$DIST"
export DISPLAY=${DISPLAY:-:99}
PKG_BIN="$WORKSPACE/node_modules/.bin/electron-packager"

if [ ! -x "$PKG_BIN" ]; then
  echo "ERROR: electron-packager not found at $PKG_BIN" >&2
  echo "REMEDY: ensure project dependencies are installed (npm i) or that electron-packager is available locally in $WORKSPACE/node_modules/.bin" >&2
  exit 2
fi

# Run packager and capture log
sudo -u "$DEVUSER" bash -lc "cd '$WORKSPACE' && '$PKG_BIN' . notes-native --platform=linux --arch=x64 --overwrite --out '$DIST' 2>&1" | tee -a "$LOGDIR/electron-packager.log"

# locate package folder e.g. dist/notes-native-linux-x64
PKG_DIR=$(find "$DIST" -maxdepth 2 -type d -name 'notes-native-linux-*' -print -quit || true)
if [ -z "$PKG_DIR" ]; then
  PKG_DIR=$(find "$DIST" -maxdepth 3 -type d -name 'notes-native*' -print -quit || true)
fi
if [ -z "$PKG_DIR" ]; then
  echo "ERROR: packaging produced no package dir; see $LOGDIR/electron-packager.log" >&2
  exit 3
fi

# determine app binary - look for executable files matching app name patterns
CANDIDATE=$(find "$PKG_DIR" -maxdepth 3 -type f -perm /111 -name 'notes-native*' -print -quit || true)
if [ -z "$CANDIDATE" ]; then
  APPNAME=$(basename "$PKG_DIR" | sed 's/-linux.*//')
  CANDIDATE=$(find "$PKG_DIR" -maxdepth 3 -type f -perm /111 -name "$APPNAME*" -print -quit || true)
fi
if [ -z "$CANDIDATE" ]; then
  echo "ERROR: no executable found in package dir $PKG_DIR" >&2
  exit 4
fi

# preflight shared libs (ldd) to surface missing deps
LDD_OUT="$LOGDIR/ldd_$(basename "$CANDIDATE").log"
if command -v ldd >/dev/null 2>&1; then
  ldd "$CANDIDATE" > "$LDD_OUT" 2>&1 || true
else
  echo "WARNING: ldd not available; skipping shared library preflight" > "$LDD_OUT"
fi

if grep -E "not found" -i "$LDD_OUT" >/dev/null 2>&1; then
  echo "ERROR: Missing shared libraries detected for packaged binary. See $LDD_OUT." >&2
  echo "REMEDY: install desktop runtime libs into the container (e.g., sudo apt-get update && sudo apt-get install -y libgtk-3-0 libnotify4 libnss3 libx11-6 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2) or run inside a VNC-enabled image that already contains them." >&2
  echo "Tail of $LDD_OUT:" >&2
  tail -n 200 "$LDD_OUT" >&2 || true
  exit 5
fi

# start the app as devuser, capture pid and stdout/stderr
APP_LOG="$LOGDIR/notes_native_app.run.log"
# ensure previous log cleared
: > "$APP_LOG"
sudo -u "$DEVUSER" bash -lc "cd '$(printf '%q' "$PKG_DIR")' && nohup '$(printf '%q' "$CANDIDATE")' > '$(printf '%q' "$APP_LOG")' 2>&1 & echo \$!" > /tmp/notes_app.pid || true
sleep 2
if [ ! -s /tmp/notes_app.pid ]; then
  echo "ERROR: failed to start app; see $APP_LOG and $LOGDIR/electron-packager.log" >&2
  [ -f "$APP_LOG" ] && tail -n 200 "$APP_LOG" >&2 || true
  exit 6
fi
PID=$(cat /tmp/notes_app.pid)
if ! kill -0 "$PID" 2>/dev/null; then
  echo "ERROR: process $PID not running after start; see $APP_LOG" >&2
  tail -n 200 "$APP_LOG" >&2 || true
  exit 7
fi

# clean stop
kill "$PID" 2>/dev/null || true
sleep 1
rm -f /tmp/notes_app.pid

# Evidence output
echo "package_dir=$PKG_DIR"
echo "executable=$CANDIDATE"
echo "run_log=$APP_LOG"

exit 0
