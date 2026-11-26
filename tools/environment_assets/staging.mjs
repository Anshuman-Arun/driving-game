import fs from 'node:fs';
import path from 'node:path';

const prefix = 'assets/environment_overhaul/';
const safeName = /^(?:LICENSE\.txt|manifest\.json|[a-z]+_lod[01]\.gltf)$/;

function plan(root, expected, create) {
  const entries = Object.entries(expected);
  if (!entries.length) throw Error('empty staging plan');
  for (const [relative, contents] of entries) {
    if (!relative.startsWith(prefix) || !safeName.test(relative.slice(prefix.length)) || typeof contents !== 'string') {
      throw Error('unsafe staging path: ' + relative);
    }
  }
  let dir = fs.realpathSync(root);
  for (const part of ['assets', 'environment_overhaul']) {
    dir = path.join(dir, part);
    let st = fs.lstatSync(dir, {throwIfNoEntry: false});
    if (!st && create) {
      fs.mkdirSync(dir);
      st = fs.lstatSync(dir);
    }
    if (!st || st.isSymbolicLink() || !st.isDirectory()) throw Error('unsafe staging directory: ' + dir);
  }
  const files = entries.map(([relative, contents]) => {
    const dest = path.join(dir, relative.slice(prefix.length));
    const st = fs.lstatSync(dest, {throwIfNoEntry: false});
    if (st && (!st.isFile() || st.isSymbolicLink())) throw Error('unsafe staging destination: ' + relative);
    return {relative, dest, contents, exists: !!st};
  });
  return {dir, files};
}

export function readFiles(root, expected) {
  const {files} = plan(root, expected, false);
  return Object.fromEntries(files.map(({relative, dest, exists, contents}) => {
    if (!exists) throw Error('missing staging file: ' + relative);
    const bytes = fs.readFileSync(dest);
    if (!bytes.equals(Buffer.from(contents, 'utf8'))) throw Error('stale or modified staging output: ' + relative);
    return [relative, bytes.toString('utf8')];
  }));
}

export function stageFiles(root, expected) {
  const {dir} = plan(root, expected, true);
  const lock = path.join(dir, '.stage-lock');
  fs.mkdirSync(lock); // Exclusive: do not remove another process's lock.
  let scratch;
  try {
    const {files} = plan(root, expected, false);
    const changes = files.filter(f => !f.exists || !fs.readFileSync(f.dest).equals(Buffer.from(f.contents, 'utf8')));
    if (!changes.length) return 0;
    scratch = fs.mkdtempSync(path.join(dir, '.stage-'));
    changes.sort((a, b) => Number(a.relative.endsWith('/manifest.json')) - Number(b.relative.endsWith('/manifest.json')));
    // Stage all bytes before modifying any published file. Commit the manifest last.
    for (let i = 0; i < changes.length; i++) {
      fs.writeFileSync(path.join(scratch, String(i)), changes[i].contents, {flag: 'wx'});
    }
    for (let i = 0; i < changes.length; i++) fs.renameSync(path.join(scratch, String(i)), changes[i].dest);
    readFiles(root, expected);
    return changes.length;
  } finally {
    try { if (scratch) fs.rmSync(scratch, {recursive: true, force: true}); }
    finally { fs.rmdirSync(lock); }
  }
}
