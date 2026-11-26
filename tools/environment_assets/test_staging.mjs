import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {stageFiles, readFiles} from './staging.mjs';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'aster-vegetation-'));
const prefix = 'assets/environment_overhaul/';
const expected = {[prefix+'shrub_lod0.gltf']: 'asset\n', [prefix+'manifest.json']: 'manifest\n'};
const payload = path.join(root, prefix, 'shrub_lod0.gltf');
let checks = 0;
function verify(condition) { assert.ok(condition); checks++; }
function rejects(fn, pattern) { assert.throws(fn, pattern); checks++; }
try {
  verify(stageFiles(root, expected) === 2);
  verify(JSON.stringify(readFiles(root, expected)) === JSON.stringify(expected));
  const before = fs.statSync(payload);
  verify(stageFiles(root, expected) === 0);
  verify(fs.statSync(payload).mtimeMs === before.mtimeMs);
  fs.writeFileSync(payload, 'asset\r\n');
  rejects(() => readFiles(root, expected), /stale or modified/);
  verify(stageFiles(root, expected) === 1);
  fs.unlinkSync(payload);
  rejects(() => readFiles(root, expected), /missing staging file/);
  verify(stageFiles(root, expected) === 1);
  rejects(() => stageFiles(root, {[prefix+'../outside']: 'bad'}), /unsafe staging path/);
  rejects(() => stageFiles(root, {'/tmp/outside': 'bad'}), /unsafe staging path/);
  const outside = path.join(root, 'outside.txt');
  fs.writeFileSync(outside, 'untouched');
  fs.unlinkSync(payload);
  if (process.platform !== 'win32') {
    fs.symlinkSync(outside, payload);
    rejects(() => stageFiles(root, expected), /unsafe staging destination/);
    rejects(() => readFiles(root, expected), /unsafe staging destination/);
    verify(fs.readFileSync(outside, 'utf8') === 'untouched');
    fs.unlinkSync(payload);
  }
  fs.mkdirSync(payload);
  rejects(() => stageFiles(root, expected), /unsafe staging destination/);
  fs.rmdirSync(payload);
  verify(stageFiles(root, expected) === 1);
  const dir = path.join(root, 'assets', 'environment_overhaul');
  const lock = path.join(dir, '.stage-lock');
  fs.mkdirSync(lock);
  rejects(() => stageFiles(root, expected), /EEXIST/);
  verify(fs.existsSync(lock));
  fs.rmdirSync(lock);
  verify(fs.readdirSync(dir).every(n => !n.startsWith('.stage-')));
  if (process.platform !== 'win32') {
    fs.renameSync(dir, path.join(root, 'elsewhere'));
    fs.symlinkSync(path.join(root, 'elsewhere'), dir);
    rejects(() => stageFiles(root, expected), /unsafe staging directory/);
    rejects(() => readFiles(root, expected), /unsafe staging directory/);
  }
  console.log('Staging filesystem checks passed: ' + checks);
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
