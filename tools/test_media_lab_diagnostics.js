'use strict';
// Runtime smoke test of the Media Lab diagnostic UI, without a real microphone.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('sample_apps/media_probe/index.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/);
assert(script, 'Missing the Media Lab script');

const controls = new Map();
function element(id) {
  if (!controls.has(id)) {
    const handlers = new Map();
    const input = {
      id, textContent: '', value: '', disabled: false,
      hidden: id === 'diagHistory',
      width: id === 'wave' ? 640 : undefined,
      height: id === 'wave' ? 128 : undefined,
      addEventListener: (kind, cb) => handlers.set(kind, cb),
      callback: kind => handlers.get(kind),
      getContext: () => ({
        fillRect() {}, beginPath() {}, moveTo() {}, lineTo() {}, stroke() {}
      }),
      focus() { input.focused = true; },
      select() { input.selected = true; },
      pause() {}, play() { return Promise.resolve(); }
    };
    controls.set(id, input);
  }
  return controls.get(id);
}
let copied = '';
let started = 0, stopped = 0, read = 0, log = 0;
const chappy = {
  microphone: {
    async start() {
      started++;
      return {running:true, sampleRate:16000, channels:1, source:'mic'};
    },
    async levels() {
      read++;
      return {running:true, rms:0.15, framesRead:2048,
        levels:Array(64).fill(0.2)};
    },
    async stop() { stopped++; return true; }
  },
  log: () => { log++; return Promise.resolve(true); }
};
const listeners = {};
const document = {
  getElementById: element,
  addEventListener: (key, cb) => { listeners[key] = cb; }
};
const window = {
  Chappy: chappy,
  addEventListener: (key, cb) => { listeners[key] = cb; }
};
const navigator = {clipboard: {async writeText(value) { copied = value; }}};
vm.runInNewContext(script[1], {
  document, window, navigator, Chappy:chappy,
  setInterval: () => 42, clearInterval: () => {},
  requestAnimationFrame: () => 12, cancelAnimationFrame: () => {},
  Uint8Array, setTimeout, clearTimeout
}, {timeout:3000});
const click = id => {
  const handler = element(id).callback('click');
  assert.equal(typeof handler, 'function', 'No click handler: ' + id);
  return handler();
};
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  assert.match(element('diagHistory').value, /準備完了/);
  await click('nativeMicOn');
  assert.equal(started, 1);
  assert.equal(read, 1);
  assert.match(element('micStatus').textContent, /RMS: 0.150/);
  assert.match(element('diagHistory').value, /音声入力を検出/);
  click('diagCopy');
  await flush();
  assert.match(copied, /Android AudioRecord取得成功/);
  assert.match(copied, /音声入力を検出/);
  assert.match(element('diagCopyStatus').textContent, /コピーしました/);
  await click('nativeMicOff');
  await flush();
  assert.ok(stopped >= 1);

  // When clipboard access is blocked, the same bounded log remains selectable.
  delete navigator.clipboard;
  click('diagCopy');
  await flush();
  assert.equal(element('diagHistory').hidden, false);
  assert.equal(element('diagHistory').selected, true);
  assert.match(element('diagCopyStatus').textContent, /長押しでコピー/);
  assert.ok(log >= 2);
  console.log('Media Lab diagnostics test passed: native RMS, copy and selection fallback');
})().catch(error => { console.error(error); process.exit(1); });
