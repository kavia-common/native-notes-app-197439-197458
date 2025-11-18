#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/native-notes-app-197439-197458/notes_native_app"
DEVUSER=devuser
LOGDIR="$WORKSPACE/logs"
TESTTMP="$WORKSPACE/tmp"
# create dirs as devuser
sudo -u "$DEVUSER" bash -lc "mkdir -p '$LOGDIR' '$TESTTMP' '$WORKSPACE/test' || true"
# ensure package.json has test script
sudo -u "$DEVUSER" bash -lc "cd '$WORKSPACE' && cp package.json package.json.test.bak 2>/dev/null || true && node -e '\nconst fs=require("fs"),p=JSON.parse(fs.readFileSync("package.json","utf8"));p.scripts=p.scripts||{};p.scripts.test=p.scripts.test||\"jest --runInBand\";fs.writeFileSync("package.json",JSON.stringify(p,null,2));console.log(\"test script ensured\");'"
# write isolated Jest test that forces DB into tmp folder
sudo -u "$DEVUSER" tee "$WORKSPACE/test/db.test.js" >/dev/null <<'T'
const fs=require('fs'), path=require('path');
const tempdir=path.join(__dirname,'..','tmp');
if(!fs.existsSync(tempdir)) fs.mkdirSync(tempdir,{ recursive: true });
const dbPath=path.join(tempdir,'notes.test.db');
afterEach(()=>{ try{ if(fs.existsSync(dbPath)) fs.unlinkSync(dbPath); }catch(e){} });
test('creates sqlite file via db module', done=>{
  // require module but override path used by src/db by copying a tiny shim
  const shim=path.join(__dirname,'..','src','db.js');
  if(!fs.existsSync(shim)) return done(new Error('src/db.js not found'));
  const content=fs.readFileSync(shim,'utf8').replace(/notes\.db/g,'notes.test.db');
  const shimPath=path.join(tempdir,'db_shim.js');
  fs.writeFileSync(shimPath,content);
  const db=require(shimPath);
  db.serialize(()=>{
    db.get("SELECT name FROM sqlite_master WHERE type='table' AND name='notes'", (err,row)=>{
      try{
        expect(err).toBeNull();
        expect(row).not.toBeUndefined();
        db.close(()=>done());
      }catch(e){ db.close(()=>done(e)); }
    });
  });
});
T
# verify local jest binary exists
if [ ! -x "$WORKSPACE/node_modules/.bin/jest" ]; then echo "ERROR: local jest not found at $WORKSPACE/node_modules/.bin/jest" >&2; exit 2; fi
# run tests and append logs
sudo -u "$DEVUSER" bash -lc "cd '$WORKSPACE' && ./node_modules/.bin/jest --runInBand 2>&1 | tee -a '$LOGDIR/jest.log'" || { echo "ERROR: tests failed; see $LOGDIR/jest.log" >&2; exit 3; }
exit 0
