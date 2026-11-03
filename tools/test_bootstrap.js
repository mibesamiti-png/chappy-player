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
  console.log('Bridge smoke tests passed: storage.set/get + error capture');
})().catch(err => { console.error(err); process.exit(1); });
