#!/usr/bin/env node
// Stage ONLY read-only Git objects from World PR #3 into this module's ignored cache.
import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const moduleRoot = resolve(here, '..');
const repoRoot = resolve(moduleRoot, '..', '..');
const reference = process.argv[2] || 'origin/feat/worldgen';
if (!/^[a-zA-Z0-9_./-]+$/.test(reference) || reference.startsWith('-')) {
  console.error('Invalid ref. Use origin/feat/worldgen or a specific commit SHA.');
  process.exit(2);
}
const output = join(moduleRoot, '.world_source');
const artifacts = [
  'data/world/world_metadata_v1.json',
  'data/world/road_graph_v1.json',
  'data/world/terrain_height_r16le.bin',
];
mkdirSync(output, { recursive: true });
for (const remotePath of artifacts) {
  const spec = reference + ':' + remotePath;
  const proc = spawnSync('git', ['show', spec], {
    cwd: repoRoot, encoding: null, maxBuffer: 8 * 1024 * 1024,
  });
  if (proc.status !== 0) {
    console.error('Cannot read ' + spec + '\n' + proc.stderr?.toString());
    console.error('Fetch the world branch first: git fetch origin feat/worldgen');
    process.exit(1);
  }
  const local = join(output, remotePath.split('/').at(-1));
  writeFileSync(local, proc.stdout);
  console.log(remotePath + ': ' + proc.stdout.length + ' bytes (staged, not tracked)');
}
console.log('Authoritative read-only input cache: ' + output);
console.log('Now run: node modules/world_runtime/tests/verify_world_data.mjs "' + output + '"');
