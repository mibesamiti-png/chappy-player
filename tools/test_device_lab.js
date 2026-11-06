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
assert(html.includes('data-haptic="tick"'));
assert(html.includes('data-haptic="click"'));
assert(html.includes('data-haptic="heavy"'));
assert(!/<script[^>]+src=/.test(html),'No external scripts');
const elements={};
function node(data){return {
  dataset:data,disabled:false,textContent:'',
  addEventListener(type,fn){this[type]=fn;}
}}
elements.sensorResult=node({});
elements.hapticResult=node({});
const sensors=['accelerometer','gyroscope','magnetometer'].map(sensor=>{
 const e=node({sensor});return e;});
const haptics=['tick','click','heavy'].map(haptic=>{
 const e=node({haptic});return e;});
const calls=[];
const video={
  motion:{async sample(type){calls.push(['sample',type]);return {
    available:true,values:[1.2,3.4,5.6],accuracy:3}}},
  haptics:{async play(effect){calls.push(['haptic',effect]);return true}}
};
const document={
 getElementById:id=>elements[id],
 querySelectorAll:sel=>sel==='[data-sensor]'?sensors:sel==='[data-haptic]'?haptics:[]
};
vm.runInNewContext(match[1],{window:{Chappy:video},document,Number,String}, {timeout:2000});
(async()=>{
 for(const sensor of sensors)await sensor.click();
 for(const haptic of haptics)await haptic.click();
 assert.equal(calls.length,6);
 assert.equal(calls[0][1],'accelerometer');
 assert.equal(calls[1][1],'gyroscope');
 assert.equal(calls[2][1],'magnetometer');
 assert.match(elements.sensorResult.textContent,/X = 1.200/);
 assert.match(elements.hapticResult.textContent,/振動を実行/);
 console.log('Device Lab smoke test passed: all motion sensor samples and haptic presets');
})().catch(e=>{console.error(e);process.exit(1)});
