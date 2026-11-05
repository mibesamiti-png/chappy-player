'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('sample_apps/media_probe/index.html', 'utf8');
const scripts = [...html.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)];
assert.equal(scripts.length, 1, 'expected one inline Media Lab script');
new vm.Script(scripts[0][1], {filename: 'media_probe/index.html'});
for (const fragment of [
  'id="cameraResolution"',
  'id="cameraLens"',
  'value="720"',
  'value="1080"',
  'value="2160"',
  "video.width = {ideal: preference[0]};",
  "video.height = {ideal: preference[1]};",
  "async function diagnoseMicrophone()",
  "audio: true",
  "NotReadableError",
  "'cameraStatus'",
]) {
  assert.ok(html.includes(fragment), 'missing required feature: ' + fragment);
}
assert.ok(!html.includes('devices.map(item => item.label)'), 'do not log device labels');
console.log('Media Lab inline JS syntax, camera resolution and microphone checks passed');
