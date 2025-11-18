#!/usr/bin/env bash
set -euo pipefail
# install: install project dependencies as devuser, capture logs, verify local bins, detect native build failures
WORKSPACE="/home/kavia/workspace/code-generation/native-notes-app-197439-197458/notes_native_app"
DEVUSER=devuser
LOGDIR="$WORKSPACE/logs"
# ensure workspace and log dir exist and owned by devuser (idempotent)
sudo -u "$DEVUSER" bash -lc "mkdir -p '$WORKSPACE' '$LOGDIR' && chmod 0755 '$WORKSPACE' '$LOGDIR'"
# quick node/npm version check
NODE_V=$(node --version 2>/dev/null || echo "v0.0.0")
NPM_V=$(npm --version 2>/dev/null || echo "0.0.0")
# extract major (strip leading v)
NODE_MAJOR=$(echo "$NODE_V" | sed -E 's/^v?([0-9]+).*$/\1/') || NODE_MAJOR=0
if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
  echo "ERROR: Node major version is <18. Detected node=$NODE_V npm=$NPM_V. Please use Node >=18. Do not attempt to modify the image automatically." >&2
  exit 10
fi
# verify package.json presence
if [ ! -f "$WORKSPACE/package.json" ]; then
  echo "ERROR: package.json missing in $WORKSPACE" >&2
  exit 2
fi
# choose install command
if [ -f "$WORKSPACE/package-lock.json" ]; then
  INSTALL_CMD='npm ci --no-audit --no-fund --no-progress'
else
  INSTALL_CMD='npm i --no-audit --no-fund --no-progress'
fi
# run install as devuser and capture logs
sudo -u "$DEVUSER" bash -lc "cd '$WORKSPACE' && echo 'Running: $INSTALL_CMD' > '$LOGDIR/npm-install.log' && $INSTALL_CMD 2>&1 | tee -a '$LOGDIR/npm-install.log'"
# verify expected local binaries
MISSING=0
if [ ! -x "$WORKSPACE/node_modules/.bin/electron-packager" ]; then
  echo "ERROR: electron-packager not found after install" >&2
  MISSING=1
fi
if [ ! -x "$WORKSPACE/node_modules/.bin/jest" ]; then
  echo "ERROR: jest not found after install" >&2
  MISSING=1
fi
if [ "$MISSING" -eq 1 ]; then
  echo "See $LOGDIR/npm-install.log for details" >&2
  exit 3
fi
# quick runtime require check for sqlite3 as devuser and capture output
sudo -u "$DEVUSER" bash -lc "cd '$WORKSPACE' && node -e 'try{require(\"sqlite3\");console.log(\"sqlite3 module present\");}catch(e){console.error(\"SQLITE_REQUIRE_ERROR\",e && e.message);process.exit(5)}'" 2>&1 | tee -a "$LOGDIR/sqlite-check.log" || true
# scan logs for native build / node-gyp / sqlite issues
if grep -E "gyp|node-gyp|make:|SQLITE_REQUIRE_ERROR|unsupported|error:" -i "$LOGDIR/npm-install.log" >/dev/null 2>&1 || grep -E "gyp|node-gyp|error|SQLITE_REQUIRE_ERROR" -i "$LOGDIR/sqlite-check.log" >/dev/null 2>&1; then
  cat <<'EOF' >&2
ERROR: Detected native build failures during npm install or at sqlite require time.
Common remediation: install system build dependencies inside the container (as root):
  sudo apt-get update && sudo apt-get install -y --no-install-recommends libsqlite3-dev pkg-config python3-dev build-essential
Also ensure node-gyp prerequisites (Python 3, make, g++) are present. After installing these packages, re-run the install step.
See logs: 
  - npm install log: $WORKSPACE/logs/npm-install.log
  - sqlite require log: $WORKSPACE/logs/sqlite-check.log
EOF
  exit 4
fi
# success
echo "Dependencies installed and verified. Logs: $LOGDIR/npm-install.log"
