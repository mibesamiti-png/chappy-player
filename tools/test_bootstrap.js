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
  const zip = window.Chappy.video.backupZip();
  assert.equal(sent[11].method, 'video.backupZip');
  assert.equal(Object.keys(sent[11].params).length, 0);
  window.__chappyResolve({requestId: sent[11].requestId, ok: true,
    value: {status: 'saved', files: 2, sizeBytes: 3000000}});
  assert.equal((await zip).files, 2);
  const restore = window.Chappy.video.restoreZip();
  assert.equal(sent[12].method, 'video.restoreZip');
  assert.equal(Object.keys(sent[12].params).length, 0);
  window.__chappyResolve({requestId: sent[12].requestId, ok: true,
    value: {status: 'restored', restored: 2, skipped: 1, total: 3}});
  assert.equal((await restore).restored, 2);
  const importAsset = window.Chappy.files.importAsset();
  assert.equal(sent[13].method,'files.importAsset');
  window.__chappyResolve({requestId:sent[13].requestId,ok:true,
    value:{status:'imported',file:{id:'0123456789abcdef0123456789abcdef',
      name:'project.blend',sizeBytes:2048}}});
  assert.equal((await importAsset).file.name,'project.blend');
  const listed = window.Chappy.files.listAssets();
  assert.equal(sent[14].method,'files.listAssets');
  window.__chappyResolve({requestId:sent[14].requestId,ok:true,
    value:[{id:'0123456789abcdef0123456789abcdef',name:'project.blend'}]});
  assert.equal((await listed)[0].name,'project.blend');
  const exported = window.Chappy.files.exportAsset('0123456789abcdef0123456789abcdef');
  assert.equal(sent[15].method,'files.exportAsset');
  assert.equal(sent[15].params.id,'0123456789abcdef0123456789abcdef');
  window.__chappyResolve({requestId:sent[15].requestId,ok:true,
    value:{status:'saved',sizeBytes:2048}});
  assert.equal((await exported).status,'saved');
  const deleted = window.Chappy.files.deleteAsset('0123456789abcdef0123456789abcdef');
  assert.equal(sent[16].method,'files.deleteAsset');
  window.__chappyResolve({requestId:sent[16].requestId,ok:true,value:true});
  assert.equal(await deleted,true);
  const transfer = window.Chappy.files.transferStatus();
  assert.equal(sent[17].method,'files.transferStatus');
  window.__chappyResolve({requestId:sent[17].requestId,ok:true,
    value:{active:true,phase:'copying',bytesDone:1024,totalBytes:4096,
      cancelable:true,cancelRequested:false}});
  assert.equal((await transfer).bytesDone,1024);
  const cancel = window.Chappy.files.cancelTransfer();
  assert.equal(sent[18].method,'files.cancelTransfer');
  window.__chappyResolve({requestId:sent[18].requestId,ok:true,value:true});
  assert.equal(await cancel,true);
  const compressed = window.Chappy.files.exportCompressedZip(
    '0123456789abcdef0123456789abcdef','max');
  assert.equal(sent[19].method,'files.exportCompressedZip');
  assert.equal(sent[19].params.id,'0123456789abcdef0123456789abcdef');
  assert.equal(sent[19].params.level,'max');
  window.__chappyResolve({requestId:sent[19].requestId,ok:true,
    value:{status:'saved',originalBytes:8192,zipBytes:512,
      savedBytes:7680,percentSmaller:93.75,compressionLevel:9}});
  assert.equal((await compressed).percentSmaller,93.75);
  const availableMotion=window.Chappy.motion.available();
  assert.equal(sent[20].method,'motion.available');
  window.__chappyResolve({requestId:sent[20].requestId,ok:true,
    value:{gravity:true,linearAcceleration:false,accelerometer:true}});
  assert.equal((await availableMotion).gravity,true);
  const availableHaptics=window.Chappy.haptics.available();
  assert.equal(sent[21].method,'haptics.available');
  window.__chappyResolve({requestId:sent[21].requestId,ok:true,value:true});
  assert.equal(await availableHaptics,true);
  const gravity=window.Chappy.motion.sample('gravity');
  assert.equal(sent[22].method,'motion.sample');
  assert.equal(sent[22].params.type,'gravity');
  window.__chappyResolve({requestId:sent[22].requestId,ok:true,
    value:{available:true,values:[0,9.8,0]}});
  assert.equal((await gravity).values[1],9.8);
  console.log('Bridge smoke tests passed: safe media/files and game motion/haptic availability');
})().catch(err => { console.error(err); process.exit(1); });
