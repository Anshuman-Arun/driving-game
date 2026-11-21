#!/usr/bin/env node
// Independent source-data + meshing preflight for the exact files consumed by Godot.
// No external packages; does not generate or overwrite World Agent assets.
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const input = resolve(process.argv[2] || 'modules/world_runtime/.world_source');
const metadata = JSON.parse(readFileSync(join(input, 'world_metadata_v1.json'), 'utf8'));
const graphBytes = readFileSync(join(input, 'road_graph_v1.json'));
const graph = JSON.parse(graphBytes.toString('utf8'));
const raster = readFileSync(join(input, 'terrain_height_r16le.bin'));
const h = metadata.heightfield;
const width = h.sample_width, height = h.sample_height;
assert.equal(metadata.schema_version, 1);
assert.equal(graph.schema_version, 1);
assert.equal(metadata.coordinate_system, 'godot_y_up');
assert.equal(graph.coordinate_system, 'godot_y_up');
assert.equal(graph.units, 'meters');
assert.equal(h.format, 'uint16_le');
assert.equal(h.row_order, 'z_ascending_x_ascending');
assert.equal(raster.length, width * height * 2);
assert.equal(h.origin_x + (width - 1) * h.spacing_m, metadata.bounds.max_x);
assert.equal(h.origin_z + (height - 1) * h.spacing_m, metadata.bounds.max_z);
assert.deepEqual(graph.bounds, metadata.bounds);
const quantized = (ix, iz) => raster.readUInt16LE(2 * (iz * width + ix));
const elevation = (ix, iz) => quantized(ix, iz) * h.scale_m_per_unit + h.offset_m;
const sample = (x, z) => {
  const gx = Math.max(0, Math.min(width - 1, (x - h.origin_x) / h.spacing_m));
  const gz = Math.max(0, Math.min(height - 1, (z - h.origin_z) / h.spacing_m));
  const ix = Math.min(width - 2, Math.floor(gx)), iz = Math.min(height - 2, Math.floor(gz));
  const u = gx - ix, v = gz - iz;
  const a = elevation(ix, iz), b = elevation(ix + 1, iz);
  const c = elevation(ix, iz + 1), d = elevation(ix + 1, iz + 1);
  return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v;
};
const triangleSurface = (x, z) => {
  const gx = Math.max(0, Math.min(width - 1, (x - h.origin_x) / h.spacing_m));
  const gz = Math.max(0, Math.min(height - 1, (z - h.origin_z) / h.spacing_m));
  const ix = Math.min(width - 2, Math.floor(gx)), iz = Math.min(height - 2, Math.floor(gz));
  const u = gx - ix, v = gz - iz;
  const a = elevation(ix, iz), b = elevation(ix + 1, iz);
  const c = elevation(ix, iz + 1), d = elevation(ix + 1, iz + 1);
  return u + v <= 1 ? a + (b - a) * u + (c - a) * v :
    d + (c - d) * (1 - u) + (b - d) * (1 - v);
};
const roads = new Map(graph.roads.map(r => [r.id, r]));
const lanes = new Map(graph.lanes.map(l => [l.id, l]));
assert.equal(roads.size, graph.roads.length);
assert.equal(lanes.size, graph.lanes.length);
let badEndpoints = 0, maxLaneToRasterM = 0, maxLinkGapM = 0, maxTravelGrade = 0;
for (const lane of graph.lanes) {
  assert(roads.has(lane.road_id));
  assert(lane.points.length >= 2);
  assert(lane.width_m > 0 && lane.speed_limit_kph >= 0);
  assert(['asphalt', 'gravel'].includes(lane.surface));
  for (const p of lane.points) {
    assert(p.every(Number.isFinite));
    assert(p[0] >= graph.bounds.min_x - 0.5 && p[0] <= graph.bounds.max_x + 0.5);
    assert(p[2] >= graph.bounds.min_z - 0.5 && p[2] <= graph.bounds.max_z + 0.5);
    maxLaneToRasterM = Math.max(maxLaneToRasterM, Math.abs(p[1] - sample(p[0], p[2])));
  }
  for (let i = 1; i < lane.points.length; i++) {
    const a = lane.points[i - 1], b = lane.points[i];
    const horizontal = Math.hypot(a[0] - b[0], a[2] - b[2]);
    assert(horizontal > 0.00001);
    if (lane.id.startsWith('lane_')) {
      maxTravelGrade = Math.max(maxTravelGrade, Math.abs(b[1] - a[1]) / horizontal);
    }
  }
  for (const successor of lane.next_lane_ids) {
    assert(lanes.has(successor));
    const a = lane.points.at(-1), b = lanes.get(successor).points[0];
    const gap = Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    maxLinkGapM = Math.max(maxLinkGapM, gap);
    if (gap > 0.025) badEndpoints++;
  }
}
for (const road of graph.roads) {
  for (const lid of road.lane_ids) {
    assert(lanes.has(lid));
    assert.equal(lanes.get(lid).road_id, road.id);
  }
}
assert.equal(badEndpoints, 0);
assert(maxLaneToRasterM < 0.015);
assert(maxTravelGrade < 0.17);
const physical = graph.roads.filter(r => lanes.has('lane_' + r.id + '_ab') &&
  lanes.has('lane_' + r.id + '_ba'));
let stripTriangles = 0, stripVertices = 0, corridorSampleCount = 0;
let maxPairedVerticalDifferenceM = 0, maxShoulderDiscrepancyM = 0;
for (const road of physical) {
  const ab = lanes.get('lane_' + road.id + '_ab');
  const ba = lanes.get('lane_' + road.id + '_ba');
  assert.equal(ab.points.length, ba.points.length);
  assert.equal(ab.surface, ba.surface);
  corridorSampleCount += ab.points.length;
  const center = ab.points.map((p, i) => {
    const q = ba.points[ba.points.length - i - 1];
    maxPairedVerticalDifferenceM = Math.max(maxPairedVerticalDifferenceM, Math.abs(p[1] - q[1]));
    return p.map((v, k) => (v + q[k]) / 2);
  });
  for (let i = 0; i < center.length; i++) {
    const prev = center[Math.max(0, i - 1)];
    const next = center[Math.min(center.length - 1, i + 1)];
    const t = [next[0] - prev[0], next[2] - prev[2]];
    const norm = Math.hypot(...t);
    assert(norm > 0);
    const side = [-t[1] / norm, t[0] / norm];
    for (const sign of [-1, 1]) {
      const x = center[i][0] + side[0] * ab.width_m * sign;
      const z = center[i][2] + side[1] * ab.width_m * sign;
      const deckY = Math.max(center[i][1], triangleSurface(x, z)) + 0.075;
      assert(deckY - triangleSurface(x, z) >= 0.074999);
      maxShoulderDiscrepancyM = Math.max(maxShoulderDiscrepancyM, Math.abs(deckY - center[i][1]));
    }
  }
  stripTriangles += (ab.points.length - 1) * 8;
  stripVertices += (ab.points.length - 1) * 24;
}
assert.equal(physical.length, metadata.roads.unique_corridor_count);
assert.equal(graph.lanes.length, metadata.roads.directed_travel_lane_count + metadata.roads.junction_connector_count);
const turns = graph.lanes.filter(l => l.id.startsWith('turn_'));
assert.equal(turns.length, metadata.roads.junction_connector_count);
const junctions = new Map();
for (const turn of turns) {
  const key = turn.id.split('_')[1];
  if (!junctions.has(key)) junctions.set(key, []);
  junctions.get(key).push(turn);
}
const cross = (a, b, p) => (b[0] - a[0]) * (p[1] - a[1]) -
  (b[1] - a[1]) * (p[0] - a[0]);
const hull = (points) => {
  const p = points.toSorted((a, b) => a[0] - b[0] || a[1] - b[1]);
  const lower = [];
  for (const v of p) {
    while (lower.length > 1 && cross(lower.at(-2), lower.at(-1), v) <= 0) lower.pop();
    lower.push(v);
  }
  const upper = [];
  for (const v of p.toReversed()) {
    while (upper.length > 1 && cross(upper.at(-2), upper.at(-1), v) <= 0) upper.pop();
    upper.push(v);
  }
  lower.pop(); upper.pop();
  return lower.concat(upper);
};
// Mirrors the Godot 2 m convex-polygon grid clipping to predict pad triangle count.
const clipConvexCell = (cell, boundary) => {
  let polygon = cell;
  for (let i = 0; i < boundary.length; i++) {
    if (!polygon.length) break;
    const a = boundary[i], b = boundary[(i + 1) % boundary.length];
    const clipped = [];
    let prev = polygon.at(-1), prevSide = cross(a, b, prev);
    for (const point of polygon) {
      const side = cross(a, b, point);
      if ((prevSide >= -0.00001) !== (side >= -0.00001)) {
        const denominator = prevSide - side;
        if (Math.abs(denominator) > 0.000001) {
          const w = prevSide / denominator;
          clipped.push([prev[0] + w * (point[0] - prev[0]),
            prev[1] + w * (point[1] - prev[1])]);
        }
      }
      if (side >= -0.00001) clipped.push(point);
      prev = point;
      prevSide = side;
    }
    polygon = clipped;
  }
  return polygon;
};
let coveredTurns = 0, totalPadSquareMeters = 0, minTurnMarginM = Infinity;
let predictedPadTriangles = 0, predictedPadCells = 0;
let totalClippedPadAreaM2 = 0;
for (const [name, group] of junctions) {
  const buffered = [];
  for (const lane of group) {
    const pts = lane.points;
    const reach = lane.width_m / 2 + 3.0;
    for (let i = 0; i < pts.length; i++) {
      const prev = pts[Math.max(i - 1, 0)], next = pts[Math.min(i + 1, pts.length - 1)];
      const dx = next[0] - prev[0], dz = next[2] - prev[2];
      const n = Math.hypot(dx, dz);
      assert(n > 0);
      const nx = -dz / n, nz = dx / n;
      buffered.push([pts[i][0] + nx * reach, pts[i][2] + nz * reach]);
      buffered.push([pts[i][0] - nx * reach, pts[i][2] - nz * reach]);
      buffered.push([pts[i][0] + reach, pts[i][2]], [pts[i][0] - reach, pts[i][2]]);
      buffered.push([pts[i][0], pts[i][2] + reach], [pts[i][0], pts[i][2] - reach]);
    }
  }
  const boundary = hull(buffered);
  assert(boundary.length >= 3, 'Bad hull at ' + name);
  let area = 0;
  for (let i = 0; i < boundary.length; i++) {
    const a = boundary[i], b = boundary[(i + 1) % boundary.length];
    area += a[0] * b[1] - a[1] * b[0];
  }
  assert(area > 0, 'Pad winding not CCW at ' + name);
  totalPadSquareMeters += area / 2;
  const gridM = 2;
  const minX = Math.floor(Math.min(...boundary.map(p => p[0])) / gridM);
  const maxX = Math.ceil(Math.max(...boundary.map(p => p[0])) / gridM);
  const minZ = Math.floor(Math.min(...boundary.map(p => p[1])) / gridM);
  const maxZ = Math.ceil(Math.max(...boundary.map(p => p[1])) / gridM);
  for (let iz = minZ; iz < maxZ; iz++) {
    for (let ix = minX; ix < maxX; ix++) {
      const x = ix * gridM, z = iz * gridM;
      const polygon = clipConvexCell([[x, z], [x + gridM, z],
        [x + gridM, z + gridM], [x, z + gridM]], boundary);
      if (polygon.length < 3) continue;
      let cellArea = 0;
      for (let k = 0; k < polygon.length; k++) {
        const p = polygon[k], q = polygon[(k + 1) % polygon.length];
        cellArea += p[0] * q[1] - p[1] * q[0];
      }
      if (cellArea < 0.00000002) continue;
      totalClippedPadAreaM2 += cellArea / 2;
      predictedPadTriangles += polygon.length - 2;
      predictedPadCells++;
    }
  }
  for (const lane of group) {
    for (const p of lane.points) {
      for (let i = 0; i < boundary.length; i++) {
        const a = boundary[i], b = boundary[(i + 1) % boundary.length];
        const distance = cross(a, b, [p[0], p[2]]) / Math.hypot(b[0] - a[0], b[1] - a[1]);
        assert(distance >= -0.001, 'Turn point outside pad at ' + name);
        minTurnMarginM = Math.min(minTurnMarginM, distance);
      }
    }
    coveredTurns++;
  }
}
assert.equal(coveredTurns, turns.length);
assert(minTurnMarginM >= 2.8, 'Insufficient clearance inside junction pad polygons');
assert(Math.abs(totalPadSquareMeters - totalClippedPadAreaM2) < 0.01,
  'Junction grid coverage loses surface area');
for (let ix = 0; ix < width - 1; ix += 7) {
  for (let iz = 0; iz < height - 1; iz += 11) {
    const x = h.origin_x + ix * h.spacing_m;
    const z = h.origin_z + iz * h.spacing_m;
    assert(Math.abs(triangleSurface(x, z) - elevation(ix, iz)) < 1e-8);
  }
}
const gitBlobSha = (b) => createHash('sha1')
  .update('blob ' + b.length + '\0').update(b).digest('hex');
const allHeights = new Uint16Array(width * height);
for (let i = 0; i < allHeights.length; i++) allHeights[i] = raster.readUInt16LE(i * 2);
let minHeight = Infinity, maxHeight = -Infinity;
for (const v of allHeights) {
  minHeight = Math.min(minHeight, v * h.scale_m_per_unit + h.offset_m);
  maxHeight = Math.max(maxHeight, v * h.scale_m_per_unit + h.offset_m);
}
const chunk = 32;
const terrainChunks = Math.ceil((width - 1) / chunk) * Math.ceil((height - 1) / chunk);
const result = {
  input, seed: metadata.seed, graphGitBlob: gitBlobSha(graphBytes),
  r16GitBlob: gitBlobSha(raster), rasterBytes: raster.length,
  heightSamples: allHeights.length, heightRangeM: [minHeight, maxHeight],
  roadRecords: graph.roads.length, physicalCorridors: physical.length,
  directedLanes: graph.lanes.length, turningPaths: turns.length,
  junctionPads: junctions.size, maxLinkGapM, maxLaneToRasterM,
  maxTravelGradePct: maxTravelGrade * 100, maxPairedVerticalDifferenceM,
  maxDeckRaiseAboveCorridorCenterM: maxShoulderDiscrepancyM,
  minTurnCenterToPadEdgeM: minTurnMarginM,
  convexPadAreaM2: totalPadSquareMeters,
  clippedPadAreaM2: totalClippedPadAreaM2,
  predictedFullPadTriangles: predictedPadTriangles,
  predictedFullPadVertices: 3 * predictedPadTriangles,
  predictedPadGridCells: predictedPadCells,
  predictedFullSurfaceTriangles: 2 * (width - 1) * (height - 1) + stripTriangles + predictedPadTriangles,
  predictedFullTerrainTriangles: 2 * (width - 1) * (height - 1),
  predictedFullTerrainChunks: terrainChunks,
  predictedFullRoadTriangles: stripTriangles,
  predictedFullRoadVertices: stripVertices,
  predictedFullRoadColliders: physical.length,
  predictedFullPadColliders: junctions.size,
  note: 'Reference geometry preflight, not measured Godot build time, mesh memory or gameplay collision.'
};
console.log(JSON.stringify(result, null, 2));
