'use strict';
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const html=fs.readFileSync('sample_apps/device_lab/index.html','utf8');
const match=html.match(/<script>([\s\S]*?)<\/script>/);
assert(match,'Device Lab inline JavaScript missing');
new vm.Script(match[1],{filename:'Chappy Device Lab'});
assert(html.includes('data-sensor="accelerometer"'));
assert(html.includes('data-sensor="gyroscope"'));
assert(html.includes('data-sensor="magnetometer"'));
assert(html.includes('data-sensor="gravity"'));
assert(html.includes('data-sensor="linearAcceleration"'));
assert(html.includes('data-haptic="tick"'));
assert(html.includes('data-haptic="click"'));
assert(html.includes('data-haptic="heavy"'));
assert(!/<script[^>]+src=/.test(html),'No external scripts');
const elements={};
function node(data){return {
  dataset:data,disabled:false,textContent:'',style:{},
  addEventListener(type,fn){this[type]=fn;}
}}
elements.sensorResult=node({});
elements.hapticResult=node({});
elements.tiltPad=node({});
elements.tiltDot=node({});
elements.tiltStatus=node({});
elements.tiltToggle=node({});
elements.probeSensors=node({});
elements.probeHaptics=node({});
elements.deviceSummary=node({});
const sensors=['accelerometer','gyroscope','magnetometer','gravity','linearAcceleration'].map(sensor=>{
 const e=node({sensor});return e;});
const haptics=['tick','click','heavy'].map(haptic=>{
 const e=node({haptic});return e;});
const calls=[];
const video={
  motion:{
    async sample(type){calls.push(['sample',type]);return {
      available:true,values:[1.2,3.4,5.6],accuracy:3}},
    async available(){calls.push(['available-motion']);return {
      accelerometer:true,gyroscope:true,magnetometer:true,gravity:true,
      linearAcceleration:false}}
  },
  haptics:{
    async play(effect){calls.push(['haptic',effect]);return true},
    async available(){calls.push(['available-haptics']);return true}
  }
};
let hidden=false;
const events={};
const document={
 get hidden(){return hidden;},
 getElementById:id=>elements[id],
 addEventListener:(name,handler)=>{events[name]=handler;},
 querySelectorAll:sel=>sel==='[data-sensor]'?sensors:sel==='[data-haptic]'?haptics:[]
};
let intervalFn=null,intervalActive=false;
const fakeSetInterval=fn=>{intervalFn=fn;intervalActive=true;return 1};
const fakeClearInterval=id=>{assert.equal(id,1);intervalActive=false};
vm.runInNewContext(match[1],{
 window:{Chappy:video},document,Number,String,Object,Math,
 setInterval:fakeSetInterval,clearInterval:fakeClearInterval
},{timeout:2000});
(async()=>{
 assert.equal(calls.length,0,'Do not probe hardware before user gesture');
 for(const sensor of sensors)await sensor.click();
 for(const haptic of haptics)await haptic.click();
 assert.match(elements.sensorResult.textContent,/X = 1.200/);
 assert.match(elements.hapticResult.textContent,/振動を実行/);
 await elements.probeSensors.click();
 await elements.probeHaptics.click();
 assert.match(elements.sensorResult.textContent,/linearAcceleration: 非対応/);
 assert.match(elements.hapticResult.textContent,/振動モーター搭載/);
 assert.match(elements.deviceSummary.textContent,/4種類対応/);
 assert.match(elements.deviceSummary.textContent,/振動 対応/);
 await elements.tiltToggle.click();
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(intervalActive,true);
 assert.match(elements.tiltDot.style.transform,/translate/);
 hidden=true;
 events.visibilitychange();
 assert.equal(intervalActive,false);
 assert.equal(elements.tiltToggle.textContent,'傾き操作を開始');
 assert.equal(calls.length,11);
 assert.equal(calls[0][1],'accelerometer');
 assert.equal(calls[1][1],'gyroscope');
 assert.equal(calls[2][1],'magnetometer');
 // A pending sample must not update the UI after the user stops tilt.
 const originalSample=video.motion.sample;
 let finishSample;
 video.motion.sample=()=>new Promise(resolve=>{finishSample=resolve});
 hidden=false;
 const beforeTilt=elements.tiltDot.style.transform;
 await elements.tiltToggle.click();
 assert.equal(typeof finishSample,'function');
 await elements.tiltToggle.click();
 finishSample({available:true,values:[8,8,9.8],accuracy:3});
 await new Promise(done=>setImmediate(done));
 assert.equal(elements.tiltDot.style.transform,beforeTilt,
   'late motion sample must not update after cancellation');
 assert.equal(intervalActive,false);

 // Reject non-finite sensor values, never display raw host exception text.
 video.motion.sample=async()=>({available:true,values:[NaN,2,3],accuracy:1});
 await sensors[0].click();
 assert.match(elements.sensorResult.textContent,/不正/);
 video.motion.sample=async()=>{throw new Error('private-path=secret-host-data')};
 await sensors[0].click();
 assert.match(elements.sensorResult.textContent,/取得失敗/);
 assert.ok(!elements.sensorResult.textContent.includes('secret-host-data'));
 await elements.tiltToggle.click();
 await new Promise(done=>setImmediate(done));
 assert.match(elements.tiltStatus.textContent,/取得に失敗/);
 assert.ok(!elements.tiltStatus.textContent.includes('secret-host-data'));
 assert.equal(intervalActive,false);
 video.motion.sample=originalSample;
 console.log('Device Lab smoke test passed: five sensors, haptic probes, bounded tilt input and lifecycle cleanup');
})().catch(e=>{console.error(e);process.exit(1)});
