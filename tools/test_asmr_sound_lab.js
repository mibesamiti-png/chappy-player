// Pure-function acoustic regression for ASMR Sound Lab's virtual ear-entry mix.
// Does not start audio, access Android permissions, or touch user data.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(
  path.join(__dirname, '..', 'sample_apps', 'asmr_sound_lab', 'index.html'),
  'utf8',
);
const declaration = html.match(/function earEntryBlend\(depth\)\s*\{[\s\S]*?\n\}/);
assert.ok(declaration, 'earEntryBlend must be defined in the mini-app');
const blend = vm.runInNewContext('(' + declaration[0] + ')');

function almost(actual, expected, label, epsilon=1e-6) {
  assert.ok(Math.abs(actual-expected) < epsilon, label + ': ' + actual + ' != ' + expected);
}
const far = blend(-1);
almost(far.progress, 0, 'far progress');
almost(far.external, 1, 'far external');
almost(far.internal, 0, 'far internal');
const inCanal = blend(2);
almost(inCanal.progress, 1, 'inside progress');
almost(inCanal.external, 0, 'inside external');
almost(inCanal.internal, 1, 'inside internal');
let lastExt = 1, lastInt = 0;
for (let n=0;n<=200;n++) {
  const v=blend(-0.1 + n*1.2/200);
  assert.ok(Number.isFinite(v.progress) && Number.isFinite(v.external) && Number.isFinite(v.internal));
  assert.ok(v.progress>=0 && v.progress<=1);
  assert.ok(v.external >= -1e-8 && v.external <= 1+1e-8);
  assert.ok(v.internal >= -1e-8 && v.internal <= 1+1e-8);
  assert.ok(v.external <= lastExt+1e-8, 'external should never grow while entering');
  assert.ok(v.internal >= lastInt-1e-8, 'internal should never shrink while entering');
  almost(v.external*v.external + v.internal*v.internal,1,'equal-power envelope',1e-6);
  lastExt=v.external; lastInt=v.internal;
}
const midway = blend(0.46);
assert.ok(midway.external > 0.6 && midway.internal > 0.6,
  'middle of transition must keep both routes audible');
assert.ok(html.includes('const exterior=entryBlend.external;'),
  'all free-field routing must use the equal-power exterior envelope');
assert.ok(html.includes('binaural?entryBlend.internal:1'),
  'binaural-to-canal sample route must use the internal envelope');
assert.ok(html.includes('nearBoost*entryBlend.external'),
  'preserved-stereo route must fade toward zero inside the ear');
assert.ok(html.includes('insideIsolation/100'),
  'existing opposite-ear isolation must be retained');
console.log('ASMR ear-entry equal-power/mono/side-isolation regression passed');
