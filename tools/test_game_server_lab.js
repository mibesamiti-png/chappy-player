'use strict';
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');

const html=fs.readFileSync('sample_apps/game_server_lab/index.html','utf8');
const match=html.match(/<script>([\s\S]*?)<\/script>/);
assert(match,'Game Server Lab inline script missing');
new vm.Script(match[1],{filename:'Game Server Lab'});
assert(!/<script[^>]+src=/.test(html));
assert(!html.includes('http://') && !html.includes('ws://'));
const elements=new Map();
const makeNode=id=>({
  id,value:'',textContent:'',disabled:false,callbacks:new Map(),
  addEventListener(name,fn){this.callbacks.set(name,fn)}
});
const get=id=>{
  if(!elements.has(id))elements.set(id,makeNode(id));
  return elements.get(id);
};
get('wssUrl').value='wss://game.example.org/room';
get('httpsUrl').value='https://game.example.org/status';
get('message').value='{"type":"ping"}';
const events={};
let hidden=false;
const document={
  getElementById:get,
  get hidden(){return hidden},
  addEventListener(name,fn){events[name]=fn}
};
const intervals=new Map();
let intervalId=0;
const fakeSetInterval=fn=>{const id=++intervalId;intervals.set(id,fn);return id};
const fakeClearInterval=id=>intervals.delete(id);
const actions=[];
let inboundQueue=['{"type":"welcome","players":1}'];
let active=false;
const Chappy={
  network:{
    async connect(url){actions.push(['connect',url]);active=true;
      return {connected:true,origin:'wss://game.example.org:443'}},
    async close(){actions.push(['close']);active=false;return true},
    async send(text){actions.push(['send',text]);return active},
    async poll(){actions.push(['poll']);const messages=inboundQueue;
      inboundQueue=[];return {connected:active,messages,dropped:0}},
    async request(url,method,body){actions.push(['request',url,method,body]);
      return {status:200,text:'{"ok":true}'}}
  },
  motion:{async sample(type){actions.push(['sample',type]);return {
    available:true,values:[1.2,2.1,9.4]}}},
  haptics:{async play(effect){actions.push(['haptic',effect]);return true}}
};
vm.runInNewContext(match[1],{
  window:{Chappy},document,String,Number,Math,JSON,Array,Error,
  setInterval:fakeSetInterval,clearInterval:fakeClearInterval
});
async function settle(){for(let i=0;i<12;i++)await new Promise(done=>setImmediate(done))}
async function click(id){const fn=get(id).callbacks.get('click');
  assert.equal(typeof fn,'function','missing click '+id);fn();await settle()}

(async()=>{
  assert.equal(actions.length,0,'No automatic network or hardware calls');
  await click('connect');
  assert.deepEqual(actions[0],['connect','wss://game.example.org/room']);
  assert.equal(intervals.size,1);
  assert.match(get('state').textContent,/接続中/);
  for(const fn of intervals.values())fn();
  await settle();
  assert.match(get('log').textContent,/welcome/);
  await click('send');
  assert.ok(actions.some(a=>a[0]==='send'&&a[1]==='{"type":"ping"}'));
  await click('sendGravity');
  assert.ok(actions.some(a=>a[0]==='sample'&&a[1]==='gravity'));
  assert.ok(actions.some(a=>a[0]==='send'&&a[1].includes('"gravity"')));
  await click('haptic');
  assert.ok(actions.some(a=>a[0]==='haptic'&&a[1]==='tick'));
  await click('get');
  assert.ok(actions.some(a=>a[0]==='request'&&a[2]==='GET'&&a[3]===''));
  await click('post');
  assert.ok(actions.some(a=>a[0]==='request'&&a[2]==='POST'&&
    a[3]==='{"type":"ping"}'));
  hidden=true;events.visibilitychange();await settle();
  assert.equal(intervals.size,0,'Poller must stop when app hidden');
  assert.ok(actions.some(a=>a[0]==='close'));
  assert.match(get('state').textContent,/未接続/);
  await click('clearLog');
  assert.equal(get('log').textContent,'');
  console.log('Game Server Lab passed: explicit WSS, bounded poll, HTTPS, gravity, haptic and background close');
})().catch(e=>{console.error(e);process.exit(1)});
