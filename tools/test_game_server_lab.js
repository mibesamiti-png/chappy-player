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
get('httpsBody').value='{"type":"http-post"}';
const events={};
let hidden=false;
const document={
  getElementById:get,
  get hidden(){return hidden},
  addEventListener(name,fn){events[name]=fn}
};
const intervals=new Map();
const timeouts=new Map();
let timeoutId=0;
const fakeSetTimeout=(fn,ms)=>{const id=++timeoutId;timeouts.set(id,{fn,ms});return id};
const fakeClearTimeout=id=>timeouts.delete(id);
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
  setInterval:fakeSetInterval,clearInterval:fakeClearInterval,
  setTimeout:fakeSetTimeout,clearTimeout:fakeClearTimeout
});
async function settle(){for(let i=0;i<12;i++)await new Promise(done=>setImmediate(done))}
async function click(id){const fn=get(id).callbacks.get('click');
  assert.equal(typeof fn,'function','missing click '+id);fn();await settle()}

(async()=>{
  assert.equal(actions.length,0,'No automatic network or hardware calls');
  assert.equal(get('send').disabled,true,'WSS send disabled before connection');
  assert.equal(get('sendGravity').disabled,true);
  assert.match(get('traffic').textContent,/送信 0件/);
  assert.equal(get('httpState').textContent,'HTTPS未実行');
  await click('connect');
  assert.deepEqual(actions[0],['connect','wss://game.example.org/room']);
  assert.equal(intervals.size,1);
  assert.equal(timeouts.size,0,'Successful connection clears watchdog');
  assert.match(get('state').textContent,/接続中/);
  assert.equal(get('send').disabled,false,'WSS send enabled only after connection');
  for(const fn of intervals.values())fn();
  await settle();
  assert.match(get('log').textContent,/welcome/);
  assert.match(get('traffic').textContent,/受信 1件/);
  await click('send');
  assert.ok(actions.some(a=>a[0]==='send'&&a[1]==='{"type":"ping"}'));
  await click('sendGravity');
  assert.ok(actions.some(a=>a[0]==='sample'&&a[1]==='gravity'));
  assert.ok(actions.some(a=>a[0]==='send'&&a[1].includes('"gravity"')));
  assert.match(get('traffic').textContent,/送信 2件/);
  await click('haptic');
  assert.ok(actions.some(a=>a[0]==='haptic'&&a[1]==='tick'));
  await click('fillGetExample');
  assert.equal(get('httpsUrl').value,'https://postman-echo.com/get?test=chappy');
  await click('get');
  assert.ok(actions.some(a=>a[0]==='request'&&a[2]==='GET'&&a[3]===''));
  await click('post');
  assert.ok(actions.some(a=>a[0]==='request'&&a[2]==='POST'&&
    a[3]==='{"type":"http-post"}'),'HTTPS POST must NOT reuse WSS message field');
  assert.match(get('httpState').textContent,/POST 成功/);
  const requestCount=actions.filter(a=>a[0]==='request').length;
  get('httpsBody').value='{not valid JSON';
  await click('post');
  assert.equal(actions.filter(a=>a[0]==='request').length,requestCount,
    'invalid JSON must not reach the host bridge');
  assert.match(get('httpState').textContent,/JSONオブジェクト/);
  get('httpsBody').value='"not-an-object"';
  await click('post');
  assert.equal(actions.filter(a=>a[0]==='request').length,requestCount,
    'scalar JSON must be rejected before network access');
  get('httpsBody').value=JSON.stringify({large:'あ'.repeat(3000)});
  await click('post');
  assert.equal(actions.filter(a=>a[0]==='request').length,requestCount,
    'UTF-8 payloads exceeding 8KiB must be rejected');
  assert.match(get('httpState').textContent,/8KiB/);
  get('httpsBody').value='{"type":"http-post"}';
  let finishRequest;
  const originalRequest=Chappy.network.request;
  Chappy.network.request=()=>new Promise(resolve=>{finishRequest=resolve});
  await click('post');
  assert.match(get('httpState').textContent,/実行中/);
  assert.equal(get('get').disabled,true);
  await click('get');
  assert.equal(actions.filter(a=>a[0]==='request').length,requestCount,
    'second HTTPS operation must not overlap');
  finishRequest({status:200,text:'{"ok":true}'});
  await settle();
  assert.equal(get('get').disabled,false);
  assert.equal(get('post').disabled,false);
  Chappy.network.request=async()=>{throw new Error('secret endpoint=private')};
  await click('get');
  assert.match(get('httpState').textContent,/失敗/);
  assert.ok(!get('log').textContent.includes('secret endpoint=private'),
    'HTTPS bridge exceptions are not copied to visible logs');
  Chappy.network.request=originalRequest;
  assert.equal(get('message').value,'{"type":"ping"}');
  await click('fillPostExample');
  assert.equal(get('httpsUrl').value,'https://postman-echo.com/post');
  assert.equal(get('httpsBody').value,'{"type":"ping"}');
  await click('fillWssExample');
  assert.equal(get('wssUrl').value,'wss://ws.postman-echo.com/raw');
  assert.equal(actions.filter(a=>a[0]==='connect').length,1,
    'Preset buttons must not connect to network');
  hidden=true;events.visibilitychange();await settle();
  assert.equal(intervals.size,0,'Poller must stop when app hidden');
  assert.ok(actions.some(a=>a[0]==='close'));
  assert.match(get('state').textContent,/未接続/);
  assert.equal(get('send').disabled,true);
  assert.match(get('traffic').textContent,/送信 2件/);

  // A rejected TLS handshake, DNS failure or denied permission must NOT
  // strand the status label in "接続を確認中…" indefinitely.
  Chappy.network.connect=async()=>{throw new Error('TLS rejected')};
  await click('connect');
  assert.match(get('state').textContent,/接続失敗/);
  assert.match(get('log').textContent,/TLS rejected/);

  // Reproduce an unresolved host bridge request, then fire the 30s watchdog.
  Chappy.network.connect=()=>new Promise(()=>{});
  await click('connect');
  assert.match(get('state').textContent,/接続を確認中/);
  const pendingTimer=[...timeouts.values()].find(x=>x.ms===30000);
  assert.ok(pendingTimer,'WSS must have a 30-second watchdog');
  pendingTimer.fn();
  await settle();
  assert.match(get('state').textContent,/接続失敗/);
  assert.match(get('log').textContent,/30秒以内/);
  assert.equal(timeouts.size,0,'WSS timeout timer must be cleaned up');
  await click('clearLog');
  assert.equal(get('log').textContent,'');
  console.log('Game Server Lab passed: explicit WSS, bounded poll, HTTPS, gravity, haptic and background close');
})().catch(e=>{console.error(e);process.exit(1)});
