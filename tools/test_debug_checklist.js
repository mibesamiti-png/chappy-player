// Offline mini-app unit/regression smoke test: no WebView, router or Android API.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const appPath = path.join(root, 'sample_apps', 'debug_checklist', 'app.js');
const html = fs.readFileSync(path.join(root,'sample_apps','debug_checklist','index.html'),'utf8');
const js = fs.readFileSync(appPath,'utf8');
const {
  QA_ITEMS, VALUES, LABELS, STORE_KEY, normalizeStates,
  safeStored, cleanNote, formatReport, counts
} = require(appPath);

assert.equal(QA_ITEMS.length,9);
assert.deepEqual(QA_ITEMS.map(x=>x.id),
  ['QA-01','QA-02','QA-03','QA-04','QA-05','QA-06','QA-07','QA-08','QA-09']);
assert.equal(new Set(QA_ITEMS.map(x=>x.id)).size,9);
assert.deepEqual(VALUES,['todo','pass','fail','blocked']);
assert.equal(LABELS.todo,'未実施');
assert.equal(LABELS.fail,'失敗');
assert(STORE_KEY.startsWith('local.chappy.qa_checklist.'));
for (const item of QA_ITEMS) {
  assert(item.steps.length>=15 && item.expected.length>=15);
  assert(html.includes('id="cases"'));
}
const data = normalizeStates({
  'QA-01':'pass','QA-02':'fail','QA-03':'blocked',
  'QA-04':'invalid','QA-999':'pass'
});
assert.deepEqual(data,{'QA-01':'pass','QA-02':'fail','QA-03':'blocked'});
assert.deepEqual(safeStored('{"QA-01":"pass","QA-999":"pass"}'),{'QA-01':'pass'});
assert.deepEqual(safeStored('{invalid'),{});
assert.deepEqual(safeStored('x'.repeat(2049)),{});
assert.deepEqual(counts(data),{todo:6,pass:1,fail:1,blocked:1});
assert.equal(cleanNote('a\nb\rc'), 'a b c');
assert.equal(cleanNote('a'.repeat(280)).length,240);
const report = formatReport(data,{
  'QA-01':'network test',
  'QA-02':'file not found',
}, {run:'12345',android:'Android 15',time:'2026-11-10'});
assert(report.includes('QA-01 [成功]'));
assert(report.includes('QA-02 [失敗]'));
assert(report.includes('QA-03 [保留]'));
assert(report.includes('QA-04 [未実施]'));
assert(report.includes('実施: 3/9件（成功 1件）'));
assert(report.includes('※ このレポートは自動診断・実機PASSの証明ではありません。'));
assert(!report.includes('QA-999'));
for (const id of ['progress','summary','report','run','android',
  'makeReport','copyReport','reset','message','detail']) {
  assert(html.includes('id="'+id+'"'),id);
}
for (const bad of [
  'fetch(', 'XMLHttpRequest', 'WebSocket(', 'navigator.mediaDevices',
  'navigator.geolocation', 'chappyNative', 'MethodChannel', 'eval(',
  'innerHTML', '<iframe', '<form', 'document.cookie',
]) {
  assert(!js.includes(bad) && !html.includes(bad),bad);
}
assert(js.includes("localStorage.setItem(STORE_KEY"));
assert(js.includes("localStorage.removeItem(STORE_KEY"));
assert(js.includes('window.confirm('));
assert(html.includes('script src="./app.js"'));
assert(html.includes('端末内に自動保存'));
console.log('Debug Checklist: 9 case IDs; all four statuses; report, reset and offline/no native privileges OK');
