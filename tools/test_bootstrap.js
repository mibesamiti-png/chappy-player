// Node smoke test of JavaScript bridge protocol; no Android UI involved.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const dartSource = fs.readFileSync(require('node:path').join(__dirname, '../lib/core/local_app_server.dart'), 'utf8');
const match = dartSource.match(/const _bootScript = r'''([\s\S]*?)''';/);
assert(match, 'Could not extract boot script');
const sent = [];
const listeners = {};
const timers = new Map();
let nextTimerId = 0;
const fakeSetTimeout = (fn, ms) => {
  const id = ++nextTimerId;
  timers.set(id, {fn, ms});
  return id;
};
const fakeClearTimeout = id => timers.delete(id);
const window = {
  ChappyHost: { postMessage(input) { sent.push(JSON.parse(input)); } },
  addEventListener(name, cb) { listeners[name] = cb; }
};
vm.runInNewContext(match[1], {
  window, Object, Map, Promise,
  setTimeout:fakeSetTimeout, clearTimeout:fakeClearTimeout,
  String, Error
});
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
  const ws=window.Chappy.network.connect('wss://game.example.org/play');
  assert.equal(sent[23].method,'network.connect');
  assert.equal(sent[23].params.url,'wss://game.example.org/play');
  window.__chappyResolve({requestId:sent[23].requestId,ok:true,
    value:{connected:true,origin:'wss://game.example.org:443'}});
  assert.equal((await ws).connected,true);
  assert.equal([...timers.values()].filter(x => x.ms === 45000).length, 0,
    'Successful WSS connect must cancel the 45s watchdog');
  const send=window.Chappy.network.send('{"hello":1}');
  assert.equal(sent[24].method,'network.send');
  assert.equal(sent[24].params.text,'{"hello":1}');
  window.__chappyResolve({requestId:sent[24].requestId,ok:true,value:true});
  assert.equal(await send,true);
  const poll=window.Chappy.network.poll();
  assert.equal(sent[25].method,'network.poll');
  window.__chappyResolve({requestId:sent[25].requestId,ok:true,
    value:{connected:true,messages:['{"welcome":true}'],dropped:0}});
  assert.equal((await poll).messages[0],'{"welcome":true}');
  const http=window.Chappy.network.request('https://game.example.org/state','GET','');
  assert.equal(sent[26].method,'network.request');
  assert.equal(sent[26].params.url,'https://game.example.org/state');
  window.__chappyResolve({requestId:sent[26].requestId,ok:true,
    value:{status:200,text:'{"players":1}'}});
  assert.equal((await http).status,200);
  const close=window.Chappy.network.close();
  assert.equal(sent[27].method,'network.close');
  window.__chappyResolve({requestId:sent[27].requestId,ok:true,value:true});
  assert.equal(await close,true);

  // A host that never answers WSS must fail closed: reject caller, send a
  // best-effort host cancel, and ignore a response arriving after timeout.
  const hanging=window.Chappy.network.connect('wss://game.example.org/stuck');
  const sentConnect=sent[sent.length-1];
  assert.equal(sentConnect.method,'network.connect');
  const watchdog=[...timers.entries()].find(([,t]) => t.ms===45000);
  assert.ok(watchdog,'WSS must have a bounded 45s bridge timer');
  const [watchdogId,watchdogTimer]=watchdog;
  timers.delete(watchdogId);
  watchdogTimer.fn();
  await assert.rejects(hanging,/WSS connection timed out after 45 seconds/);
  const cancelHost=sent[sent.length-1];
  assert.equal(cancelHost.method,'network.close');
  assert.equal(cancelHost.requestId,'');
  window.__chappyResolve({requestId:sentConnect.requestId,ok:true,
    value:{connected:true,origin:'wss://game.example.org:443'}});
  assert.equal(timers.size,0,'No timers remain after WSS timeout');
  // Chappy Hub Mobile handoff is a request, not a send/completion signal.
  const copyPrompt = window.Chappy.handoff.copyPrompt('続けてー');
  let cmd = sent.at(-1);
  assert.equal(cmd.method, 'handoff.copyPrompt');
  assert.equal(cmd.params.text, '続けてー');
  assert.equal([...timers.values()].filter(x => x.ms === 12000).length, 0);
  window.__chappyResolve({requestId: cmd.requestId, ok: true, value: {status:'copied'}});
  assert.equal((await copyPrompt).status, 'copied');
  const sharePrompt = window.Chappy.handoff.sharePrompt('動作確認');
  cmd = sent.at(-1);
  assert.equal(cmd.method, 'handoff.sharePrompt');
  assert.equal(cmd.params.text, '動作確認');
  window.__chappyResolve({requestId: cmd.requestId, ok: true, value: {status:'chooser_opened'}});
  assert.equal((await sharePrompt).status, 'chooser_opened');
  const openChat = window.Chappy.handoff.openChatGPT();
  cmd = sent.at(-1);
  assert.equal(cmd.method, 'handoff.openChatGPT');
  assert.equal(Object.keys(cmd.params).length, 0);
  window.__chappyResolve({requestId: cmd.requestId, ok: true, value: {status:'cancelled'}});
  assert.equal((await openChat).status, 'cancelled');
  assert.equal(timers.size, 0, 'Handoff must not leave hanging timers');
  console.log('Bridge smoke tests passed: Hub Mobile handoff + HTTPS/WSS + motion/haptics');
})().catch(err => { console.error(err); process.exit(1); });
