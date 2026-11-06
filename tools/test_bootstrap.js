// Node smoke test of JavaScript bridge protocol; no Android UI involved.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const dartSource = fs.readFileSync(require('node:path').join(__dirname, '../lib/core/local_app_server.dart'), 'utf8');
const match = dartSource.match(/const _bootScript = r'''([\s\S]*?)''';/);
assert(match, 'Could not extract boot script');
const sent = [];
const listeners = {};
const window = {
  ChappyHost: { postMessage(input) { sent.push(JSON.parse(input)); } },
  addEventListener(name, cb) { listeners[name] = cb; }
};
vm.runInNewContext(match[1], {window, Object, Map, Promise, setTimeout, clearTimeout, String, Error});
(async () => {
  const pending = window.Chappy.storage.set('key', 'value');
  assert.equal(sent[0].method, 'storage.set');
  assert.equal(sent[0].params.key, 'key');
  window.__chappyResolve({requestId: sent[0].requestId, ok: true, value: true});
  assert.equal(await pending, true);
  const read = window.Chappy.storage.get('key');
  window.__chappyResolve({requestId: sent[1].requestId, ok: true, value: 'hello'});
  assert.equal(await read, 'hello');
  listeners.error({message: 'oops', error: {stack: 'trace'}});
  assert.equal(sent[2].method, 'diagnostic.error');
  const mic = window.Chappy.microphone.start();
  assert.equal(sent[3].method, 'microphone.start');
  window.__chappyResolve({requestId: sent[3].requestId, ok: true,
    value: {running: true, sampleRate: 16000}});
  assert.equal((await mic).sampleRate, 16000);
  const levels = window.Chappy.microphone.levels();
  assert.equal(sent[4].method, 'microphone.levels');
  window.__chappyResolve({requestId: sent[4].requestId, ok: true,
    value: {running: true, rms: 0.25, levels: [0.1, 0.2]}});
  assert.equal((await levels).rms, 0.25);
  const stop = window.Chappy.microphone.stop();
  assert.equal(sent[5].method, 'microphone.stop');
  window.__chappyResolve({requestId: sent[5].requestId, ok: true, value: true});
  assert.equal(await stop, true);
  const sample = window.Chappy.motion.sample('gyroscope');
  assert.equal(sent[6].method, 'motion.sample');
  assert.equal(sent[6].params.type, 'gyroscope');
  window.__chappyResolve({requestId: sent[6].requestId, ok: true,
    value: {available: true, values: [1, 2, 3]}});
  assert.equal((await sample).available, true);
  const haptic = window.Chappy.haptics.play('tick');
  assert.equal(sent[7].method, 'haptics.play');
  assert.equal(sent[7].params.effect, 'tick');
  window.__chappyResolve({requestId: sent[7].requestId, ok: true, value: true});
  assert.equal(await haptic, true);
  const exportVideo = window.Chappy.video.export('Chappy_20261106_123456_001.mp4');
  assert.equal(sent[8].method, 'video.export');
  window.__chappyResolve({requestId: sent[8].requestId, ok: true,
    value: {status: 'cancelled'}});
  assert.equal((await exportVideo).status, 'cancelled');
  const pickText = window.Chappy.files.pickText();
  assert.equal(sent[9].method, 'files.pickText');
  window.__chappyResolve({requestId: sent[9].requestId, ok: true,
    value: {status: 'selected', fileName: 'demo.txt', text: 'hello'}});
  assert.equal((await pickText).text, 'hello');
  const saveText = window.Chappy.files.saveText('demo.txt', 'こんにちは');
  assert.equal(sent[10].method, 'files.saveText');
  assert.equal(sent[10].params.fileName, 'demo.txt');
  assert.equal(sent[10].params.text, 'こんにちは');
  window.__chappyResolve({requestId: sent[10].requestId, ok: true,
    value: {status: 'saved', sizeBytes: 15}});
  assert.equal((await saveText).status, 'saved');
  console.log('Bridge smoke tests passed: storage, microphone, motion/haptics, verified video export and selected document text I/O');
})().catch(err => { console.error(err); process.exit(1); });
