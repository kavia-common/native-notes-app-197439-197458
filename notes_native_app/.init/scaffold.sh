#!/usr/bin/env bash
set -euo pipefail
# Minimal, idempotent scaffold for Electron app written as devuser
WORKSPACE="/home/kavia/workspace/code-generation/native-notes-app-197439-197458/notes_native_app"
DEVUSER=devuser
sudo -u "$DEVUSER" bash -lc "mkdir -p '$WORKSPACE' && cd '$WORKSPACE' && if [ ! -f package.json ]; then npm init -y >/dev/null; fi"
# create src files as devuser
sudo -u "$DEVUSER" bash -lc "mkdir -p '$WORKSPACE/src'"
sudo -u "$DEVUSER" tee "$WORKSPACE/src/main.js" >/dev/null <<'MAIN'
// Development Electron main - nodeIntegration enabled for developer convenience (DEV-ONLY)
const { app, BrowserWindow } = require('electron');
const path = require('path');
function createWindow(){
  // nodeIntegration:true is intentionally enabled for dev only (DEV-ONLY)
  const win = new BrowserWindow({ width:800, height:600, webPreferences:{ nodeIntegration:true, contextIsolation:false } });
  win.loadFile(path.join(__dirname,'index.html'));
}
app.whenReady().then(createWindow);
// keep process alive even if windows close (dev requirement)
app.on('window-all-closed', ()=>{});
MAIN

sudo -u "$DEVUSER" tee "$WORKSPACE/src/index.html" >/dev/null <<'HTML'
<!doctype html>
<html>
  <body>
    <h1>Notes App (dev)</h1>
    <div id="root"></div>
    <script>document.body.style.fontFamily='sans-serif'</script>
  </body>
</html>
HTML

sudo -u "$DEVUSER" tee "$WORKSPACE/src/db.js" >/dev/null <<'DB'
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const db = new sqlite3.Database(path.join(__dirname,'notes.db'));
db.serialize(()=>{ db.run('CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, title TEXT, body TEXT)'); });
module.exports = db;
DB

# Ensure package.json contains required fields and dependencies (idempotent)
sudo -u "$DEVUSER" bash -lc "cd '$WORKSPACE' && cp package.json package.json.bak 2>/dev/null || true && node -e '
const fs=require("fs"),p=JSON.parse(fs.readFileSync("package.json","utf8"));
// set sensible defaults
p.main=p.main||"src/main.js"; p.scripts=p.scripts||{};
p.scripts.start=p.scripts.start||"electron .";
p.scripts.package=p.scripts.package||"electron-packager . notes-native --platform=linux --arch=x64 --overwrite --out dist";
// ensure explicit deps/devDeps required later
p.devDependencies=p.devDependencies||{};
const need={"electron":"^26.0.0","electron-packager":"^17.1.0","jest":"^29.0.0"};
const deps={"sqlite3":"^5.1.6"};
Object.keys(need).forEach(k=>{ if(!p.devDependencies[k] && !(p.dependencies&&p.dependencies[k])) p.devDependencies[k]=need[k]; });
Object.keys(deps).forEach(k=>{ if(!(p.dependencies&&p.dependencies[k]) && !p.devDependencies[k]) p.dependencies=p.dependencies||{},p.dependencies[k]=deps[k]; });
fs.writeFileSync("package.json",JSON.stringify(p,null,2));
console.log("package.json prepared with required deps/devDeps");'"

# Set ownership to devuser to be safe
sudo chown -R ${DEVUSER}:${DEVUSER} "$WORKSPACE"

echo "scaffold complete"
