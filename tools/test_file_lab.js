'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('sample_apps/file_lab/index.html','utf8');
const match = source.match(/<script>([\s\S]*?)<\/script>/);
assert(match, 'File Lab missing inline script');
new vm.Script(match[1], {filename:'Chappy File Lab'});
assert(!/<script[^>]+src=/.test(source), 'File Lab must work offline');
const elements = new Map();
function makeNode(id='') {
  let content = '';
  const node = {
    id, value:'', disabled:false, className:'', type:'',
    children:[], callbacks:new Map(),
    addEventListener(name, callback){this.callbacks.set(name,callback)},
    appendChild(child){this.children.push(child);return child},
    get textContent(){return content},
    set textContent(value){content=String(value);this.children=[]},
  };
  return node;
}
const get = id => {
  if (!elements.has(id)) elements.set(id,makeNode(id));
  return elements.get(id);
};
get('fileName').value='chappy-note.txt';
const traces=[];
let stored=null, availableAssets=[], nextId='0123456789abcdef0123456789abcdef';
let slowExport=false, exportResolve=null, cancelCalls=0;
const intervals=new Map();let timerId=0;
const fakeSetInterval=(fn)=>{const id=++timerId;intervals.set(id,fn);return id};
const fakeClearInterval=id=>intervals.delete(id);
const Chappy={
  files:{
    async pickText(){traces.push('pick');return {
      status:'selected',fileName:'project.json',text:'{"hello":true}',sizeBytes:14}},
    async saveText(name,text){traces.push(['save',name,text]);return {
      status:'saved',sizeBytes:Buffer.byteLength(text,'utf8')}},
    async importAsset(){
      traces.push('import');
      const record={id:nextId,name:'model.blend',
        mime:'application/octet-stream',sizeBytes:2097152};
      availableAssets.push(record);
      return {status:'imported',file:record};
    },
    async listAssets(){traces.push('list');return availableAssets.slice()},
    async exportAsset(id){
      traces.push(['export',id]);
      if(slowExport)return new Promise(resolve=>{exportResolve=resolve});
      return {status:'saved',sizeBytes:2097152};
    },
    async transferStatus(){return {
      active:true,phase:'copying',bytesDone:1048576,totalBytes:4194304,
      cancelable:true,cancelRequested:false
    }},
    async cancelTransfer(){
      cancelCalls++;
      if(exportResolve)exportResolve({status:'cancelled'});
      return true;
    },
    async deleteAsset(id){
      traces.push(['delete',id]);
      availableAssets=availableAssets.filter(file=>file.id!==id);
      return true;
    }
  },
  storage:{
    async set(key,data){traces.push(['store',key]);stored=data;return true},
    async get(key){traces.push(['load',key]);return stored}
  }
};
const document={
  getElementById:get,
  createElement:()=>makeNode()
};
vm.runInNewContext(match[1],{
  window:{Chappy},document,String,Number,Array,Error,
  setInterval:fakeSetInterval,clearInterval:fakeClearInterval
});
const settle=async()=>{for(let i=0;i<15;i++) await new Promise(done=>setImmediate(done))};
async function click(node){
  const callback=node.callbacks.get('click');
  assert.equal(typeof callback,'function','click missing for '+node.id);
  callback();
  await settle();
}
(async()=>{
  await click(get('openFile'));
  assert.equal(get('editor').value,'{"hello":true}');
  assert.equal(get('fileName').value,'project.json');
  assert.match(get('status').textContent,/読み込み完了/);
  await click(get('saveFile'));
  assert.deepEqual(traces.find(x=>Array.isArray(x)&&x[0]==='save'),
    ['save','project.json','{"hello":true}']);
  assert.match(get('status').textContent,/照合完了/);
  await click(get('saveLocal'));
  get('editor').value='';
  await click(get('loadLocal'));
  assert.equal(get('editor').value,'{"hello":true}');
  assert.match(get('status').textContent,/読み込みました/);

  await click(get('importAsset'));
  assert.ok(traces.includes('import'));
  assert.match(get('status').textContent,/取り込み完了/);
  const list = get('assetList');
  assert.equal(list.children.length,1);
  assert.equal(list.children[0].children[0].textContent,'model.blend');
  assert.match(list.children[0].children[1].textContent,/2.0 MiB/);
  await click(list.children[0].children[2]);
  assert.deepEqual(traces.find(x=>Array.isArray(x)&&x[0]==='export'),
    ['export',nextId]);
  assert.match(get('status').textContent,/書き出して照合しました/);
  assert.equal(intervals.size,0,'Polling timers must stop on successful export');

  slowExport=true;
  await click(list.children[0].children[2]);
  assert.equal(intervals.size,1,'Polling must run during pending export');
  for(const callback of intervals.values())callback();
  await settle();
  assert.match(get('assetTransferLabel').textContent,/転送中：1.0 MiB \/ 4.0 MiB/);
  assert.equal(get('assetProgressBar').value,25);
  assert.equal(get('cancelAssetTransfer').disabled,false);
  await click(get('cancelAssetTransfer'));
  assert.equal(cancelCalls,1);
  assert.match(get('status').textContent,/書き出しをキャンセルしました/);
  assert.equal(intervals.size,0,'Cancellation must clear polling timers');
  assert.equal(get('cancelAssetTransfer').disabled,true);
  slowExport=false;

  await click(list.children[0].children[3]);
  assert.deepEqual(traces.find(x=>Array.isArray(x)&&x[0]==='delete'),
    ['delete',nextId]);
  assert.equal(list.children.length,0);
  assert.match(list.textContent,/保管されているファイルはありません/);
  assert.equal(get('importAsset').disabled,false);
  await click(get('listAssets'));
  assert.equal(list.children.length,0);
  console.log('File Lab smoke tests passed: text, asset import/export, transfer progress/cancellation, delete');
})().catch(e=>{console.error(e);process.exit(1)});
