'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync('sample_apps/media_probe/index.html', 'utf8');
const found = html.match(/<script>([\s\S]*?)<\/script>/);
assert(found, 'Media Lab inline script missing');
new vm.Script(found[1], {filename:'Chappy Media Lab'});

const nodes = new Map();
function newElement(id) {
  const callbacks = new Map();
  const element = {
    id, textContent:'', value:'', checked:false, disabled:false,
    hidden:false, width:640, height:128, children:[],
    addEventListener:(name,fn)=>{callbacks.set(name,fn);},
    callback:name=>callbacks.get(name),
    appendChild(child){element.children.push(child);},
    getContext(){return {fillRect(){},beginPath(){},moveTo(){},lineTo(){},stroke(){}};},
    pause(){}, play(){return Promise.resolve();}, focus(){}, select(){}
  };
  return element;
}
function get(id) {if (!nodes.has(id))nodes.set(id,newElement(id));return nodes.get(id);}
get('videoLens').value = 'back';
get('videoQuality').value = '720';
get('videoStorage').value = 'private';
get('videoAudio').checked = true;

const document = {
  getElementById: get,
  createElement: tag=>newElement(tag),
  addEventListener:()=>{}
};
const events = {videoStart:[],stop:0,dark:[],list:0,open:[],remove:[]};
let deleted = false;
let current = 'idle';
const video = {
  async start(options) {
    events.videoStart.push(options);
    current='recording';
    return {state:'starting'};
  },
  async status() {
    return current === 'idle'
      ? {state:'idle',storage:'private',fileName:'Chappy_20261106_092500_001.mp4',bytes:30000}
      : {state:'recording',storage:'private',elapsedMs:6400,bytes:2097152};
  },
  async stop(){events.stop++;current='idle';return {state:'stopping'};},
  async dark(enabled){events.dark.push(enabled);return true;},
  async list(){events.list++;return deleted ? [] : [
    {id:'Chappy_20261106_092500_001.mp4',bytes:30000,createdMs:Date.now()}];},
  async open(id){events.open.push(id);return true;},
  async delete(id){events.remove.push(id);deleted=true;return true;}
};
const window = {Chappy:{video, microphone:{
  async start(){return {running:false}},async levels(){return {running:false}},
  async stop(){return true;}},log:()=>Promise.resolve()},addEventListener:()=>{}};
let videoPollCallback = null;
const ctx={document,window,Chappy:window.Chappy,navigator:{clipboard:{writeText:async()=>{}}},
  setInterval:(callback)=>{videoPollCallback=callback;return 21;},
  clearInterval:()=>{},setTimeout:()=>1,clearTimeout:()=>{},
  requestAnimationFrame:()=>1,cancelAnimationFrame:()=>{},Uint8Array};
vm.runInNewContext(found[1],ctx,{timeout:2000});
const click = id=>{
  const fn=get(id).callback('click');
  assert.equal(typeof fn,'function',id+' no click handler');
  return fn();
};
const settle = async()=>{
  for(let i=0;i<8;i++)await new Promise(resolve=>setImmediate(resolve));
};
(async()=>{
  await click('videoOn');await settle();
  assert.equal(events.videoStart.length,1);
  assert.deepEqual({...events.videoStart[0]},
    {lens:'back',quality:'720',audio:true,storage:'private'});
  assert.equal(get('videoOff').disabled,false);
  assert.match(get('videoStatus').textContent,/recording/);
  assert.match(get('videoStatus').textContent,/2\.0 MiB/);
  await click('videoDark');await settle();
  assert.deepEqual(events.dark,[true]);
  await click('videoOff');await settle();
  assert.equal(events.stop,1);
  assert.equal(get('videoOff').disabled,true);
  // Once the old MP4 is finalized, the button must be available directly
  // from idle: one tap both starts CameraX and enters dark mode.
  assert.equal(typeof videoPollCallback,'function');
  videoPollCallback();await settle();
  assert.equal(get('videoDark').disabled,false);
  await click('videoDark');await settle();
  assert.equal(events.videoStart.length,2);
  assert.deepEqual(events.dark,[true,true]);
  assert.equal(get('videoOff').disabled,false);
  await click('videoOff');await settle();
  videoPollCallback();await settle();
  await click('videoList');await settle();
  assert.equal(get('videoLibrary').children.length,1);
  const row=get('videoLibrary').children[0];
  assert.equal(row.children.length,3);
  await row.children[1].callback('click')();await settle();
  assert.deepEqual(events.open,['Chappy_20261106_092500_001.mp4']);
  await row.children[2].callback('click')();await settle();
  assert.deepEqual(events.remove,['Chappy_20261106_092500_001.mp4']);
  assert.match(get('videoLibrary').textContent,/プライベート動画はまだありません/);
  console.log('Video UI smoke test passed: direct dark capture, normal start, playback, confirmed delete and refreshed library');
})().catch(error=>{console.error(error);process.exit(1);});
