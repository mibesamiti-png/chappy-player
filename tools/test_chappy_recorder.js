'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('sample_apps/video_recorder/index.html', 'utf8');
assert(source.includes('Chappy Recorder'));
assert(source.includes('id="lensBack"') && source.includes('id="lensFront"'));
assert(source.includes('id="freeSpace"') && source.includes('id="totalSpace"'));
assert(source.includes('id="recordDark"') && source.includes('id="toggleLibrary"'));
assert(source.includes('id="recordScreenOff"'));
assert(source.includes('id="motionMode"') && source.includes('id="motionIdle"') &&
       source.includes('id="motionSensitivity"') && source.includes('id="motionFeedback"'));
assert(!/<script[^>]+src=|https:\/\/.*\.js/.test(source), 'mini app must be offline');
const match = source.match(/<script>([\s\S]*?)<\/script>/);
assert(match, 'Recorder script is missing');
new vm.Script(match[1], {filename: 'Chappy Recorder'});

const nodes = new Map();
function element(tag) {
  let text = '';
  const callbacks = new Map();
  const e = {
    tag, id: '', hidden: false, disabled: false, checked: false, value: '',
    children: [], style: {}, attrs: new Map(),
    addEventListener(name, cb){callbacks.set(name, cb)},
    callback(name){return callbacks.get(name)},
    appendChild(child){this.children.push(child)},
    setAttribute(name, value){this.attrs.set(name, value)},
    getAttribute(name){return this.attrs.get(name)},
  };
  Object.defineProperty(e,'textContent',{
    get(){return text},
    set(value){text=String(value);this.children=[]}
  });
  return e;
}
const get = id => {
  if (!nodes.has(id)){const e=element('div');e.id=id;nodes.set(id,e)}
  return nodes.get(id);
};
get('videoQuality').value = '720';
get('videoStorage').value = 'private';
get('videoAudio').checked = true;
get('motionMode').value = 'normal';
get('motionIdle').value = '60';
get('motionSensitivity').value = '40';
get('libraryPanel').hidden = true;
const docCallbacks = new Map();
const winCallbacks = new Map();
const log = {start:[],stop:0,dark:[],list:0,open:[],export:[],backup:0,restore:0,delete:[],storage:0};
let current='idle', removed=false, background=false;
let motionStatus='monitoring';
const video = {
  async storageInfo(){log.storage++;return {totalBytes:128000000000,availableBytes:32000000000}},
  async start(options){log.start.push({...options});current='recording';
    background = options.screenOff===true;return {state:'starting',background}},
  async status(){return {state:current,elapsedMs:4500,storage:'private',
    fileName:current==='idle'?'Chappy_20261106_123456_001.mp4':'',bytes:150000,
    motionMode:'normal', motionStatus, motionScore:12,
    backgroundSupported:true,background}},
  async dark(value){log.dark.push(value);return true},
  async stop(){log.stop++;current='idle';background=false;return {state:'stopping'}},
  async list(){log.list++;return removed?[]:[{
    id:'Chappy_20261106_123456_001.mp4',bytes:6000000,createdMs:Date.now()}]},
  async open(id){log.open.push(id);return true},
  async export(id){log.export.push(id);return {status:'saved',sizeBytes:6000000}},
  async backupZip(){log.backup++;return {status:'saved',files:1,sizeBytes:6010240}},
  async restoreZip(){log.restore++;return {status:'restored',total:2,restored:1,skipped:1}},
  async delete(id){log.delete.push(id);removed=true;return true}
};
const w={Chappy:{video},addEventListener(n,cb){winCallbacks.set(n,cb)}};
let poll = null;
const ctx={
  window:w,document:{
    hidden:false,getElementById:get,createElement:element,
    addEventListener:(n,cb)=>docCallbacks.set(n,cb)
  },
  setInterval(cb){poll=cb;return 99},
  clearInterval(){},
  Date,Number,Math,String,Array,Error
};
vm.runInNewContext(match[1],ctx,{timeout:2000});
const settle = async()=>{for(let i=0;i<12;i++)await new Promise(done=>setImmediate(done))};
const click = async id => {
  const callback=get(id).callback('click');
  assert.equal(typeof callback,'function','click handler missing for '+id);
  await callback();await settle();
};
(async()=>{
  await settle();
  assert.equal(get('freeSpace').textContent,'32.0 GB');
  assert.equal(get('totalSpace').textContent,'全容量：128.0 GB');
  assert.equal(get('capacityFill').style.width,'75.0%');
  await click('lensFront');
  assert.equal(get('lensFront').getAttribute('aria-pressed'),'true');
  get('videoQuality').value='1080';
  get('videoStorage').value='gallery';
  await click('recordDark');
  assert.deepEqual(JSON.parse(JSON.stringify(log.start[0])),
    {lens:'front',quality:'1080',storage:'gallery',audio:true,
      motion:{mode:'normal',idleSeconds:60,sensitivity:40},screenOff:false});
  assert.deepEqual(log.dark,[true]);
  assert.equal(get('recordDark').disabled,true);
  assert.equal(get('recordStop').disabled,false);
  assert.ok(typeof poll==='function');
  await click('recordStop');
  assert.equal(log.stop,1);
  assert.equal(get('recordDark').disabled,false);
  await click('toggleLibrary');
  assert.equal(get('libraryPanel').hidden,false);
  assert.equal(get('libraryList').children.length,1);
  let buttons=get('libraryList').children[0].children[2].children;
  await buttons[0].callback('click')();await settle();
  assert.deepEqual(log.open,['Chappy_20261106_123456_001.mp4']);
  await buttons[1].callback('click')();await settle();
  assert.deepEqual(log.export,['Chappy_20261106_123456_001.mp4']);
  assert.match(get('message').textContent,/書き出しました/);
  await click('backupVideos');
  assert.equal(log.backup,1);
  assert.match(get('message').textContent,/ZIPバックアップ完了：1本/);
  assert.equal(get('backupVideos').disabled,false);
  const callsBeforeRestore = log.list;
  await click('restoreVideos');
  assert.equal(log.restore,1);
  assert.equal(get('restoreVideos').disabled,false);
  assert.match(get('message').textContent,/ZIP復元完了：新規 1本/);
  assert.ok(log.list > callsBeforeRestore, 'Restored videos must refresh the private list');
  await buttons[2].callback('click')();await settle();
  assert.deepEqual(log.delete,['Chappy_20261106_123456_001.mp4']);
  assert.match(get('libraryList').textContent,/まだありません/);
  await click('toggleLibrary');
  assert.equal(get('libraryPanel').hidden,true);
  get('videoStorage').value='private';
  get('videoAudio').checked=false;
  await click('recordDark');
  assert.deepEqual(JSON.parse(JSON.stringify(log.start[1])),
    {lens:'front',quality:'1080',storage:'private',audio:false,
      motion:{mode:'normal',idleSeconds:60,sensitivity:40},screenOff:false});
  await winCallbacks.get('chappy-native-video-started')();
  await settle();
  assert.equal(get('recordStop').disabled,false);
  assert.ok(log.storage>=2);
  await click('recordStop');
  get('motionMode').value='pause';
  get('motionMode').callback('change')();
  assert.equal(get('motionSettings').hidden,false);
  get('motionIdle').value='30';
  get('motionSensitivity').value='70';
  get('motionSensitivity').callback('input')();
  assert.equal(get('motionSensitivityValue').textContent,'70%');
  await click('recordDark');
  assert.deepEqual(JSON.parse(JSON.stringify(log.start[2].motion)),
    {mode:'pause',idleSeconds:30,sensitivity:70});
  motionStatus='paused';
  poll();await settle();
  assert.match(get('captureStatus').textContent,/録画一時停止/);
  assert.match(get('motionFeedback').textContent,/カメラは監視継続/);
  await click('recordStop');
  get('motionMode').value='stop';
  get('motionMode').callback('change')();
  await click('recordDark');
  assert.equal(log.start[3].motion.mode,'stop');
  await click('recordStop');
  get('motionMode').value='normal';
  get('motionMode').callback('change')();
  assert.equal(get('recordScreenOff').disabled,false);
  await click('recordScreenOff');
  assert.equal(log.start[4].screenOff,true);
  assert.equal(log.dark.length,4,'Screen-off recording should not force dark overlay');
  const stopsBeforeBackground = log.stop;
  docCallbacks.get('visibilitychange')();
  await settle();
  assert.equal(log.stop,stopsBeforeBackground,
    'Explicit background service must not be stopped by page hide');
  winCallbacks.get('pagehide')();
  await settle();
  assert.equal(log.stop,stopsBeforeBackground,
    'Explicit background service must not be stopped by page navigation');
  await click('recordStop');
  assert.equal(log.stop,stopsBeforeBackground+1);
  console.log('Chappy Recorder passed: native screen-off opt-in, notification-mode lifecycle, motion and normal capture');
})().catch(e=>{console.error(e);process.exit(1)});
