'use strict';
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const source=fs.readFileSync('sample_apps/file_lab/index.html','utf8');
const js=source.match(/<script>([\s\S]*?)<\/script>/);
assert(js,'File Lab source missing JS');
new vm.Script(js[1],{filename:'Chappy File Lab'});
const els=new Map();
const get=id=>{
 if(!els.has(id)){
  const e={id,value:'',textContent:'',disabled:false,callbacks:new Map(),
    addEventListener(name,fn){this.callbacks.set(name,fn)}};
  els.set(id,e);
 }
 return els.get(id);
};
get('fileName').value='chappy-note.txt';
const traces=[];
let stored=null;
const Chappy={
 files:{
  async pickText(){traces.push('pick');return {
    status:'selected',fileName:'project.json',text:'{"hello":true}',sizeBytes:14}},
  async saveText(name,text){traces.push(['save',name,text]);return {
    status:'saved',sizeBytes:Buffer.byteLength(text,'utf8')}}},
 storage:{
  async set(key,data){traces.push(['store',key]);stored=data;return true},
  async get(key){traces.push(['load',key]);return stored}
 }
};
vm.runInNewContext(js[1],{window:{Chappy},document:{getElementById:get},String,Error});
const settle=async()=>{for(let i=0;i<12;i++)await new Promise(done=>setImmediate(done))};
(async()=>{
 await get('openFile').callbacks.get('click')();await settle();
 assert.equal(get('editor').value,'{"hello":true}');
 assert.equal(get('fileName').value,'project.json');
 assert.match(get('status').textContent,/読み込み完了/);
 await get('saveFile').callbacks.get('click')();await settle();
 assert.deepEqual(traces[1],['save','project.json','{"hello":true}']);
 assert.match(get('status').textContent,/照合完了/);
 await get('saveLocal').callbacks.get('click')();await settle();
 get('editor').value='';
 await get('loadLocal').callbacks.get('click')();await settle();
 assert.equal(get('editor').value,'{"hello":true}');
 assert.match(get('status').textContent,/読み込みました/);
 assert(!get('saveFile').disabled);
 console.log('File Lab smoke test passed: explicit pick/save and per-mini-app local draft');
})().catch(e=>{console.error(e);process.exit(1)});
