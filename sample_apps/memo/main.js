'use strict';
const input = document.querySelector('#notes');
const status = document.querySelector('#status');
const lengthLabel = document.querySelector('#length');
let saveTimer;
let lastSaved = '';

function updateCount() { lengthLabel.textContent = `${input.value.length}文字`; }
async function save() {
  clearTimeout(saveTimer);
  const text = input.value;
  status.textContent = '保存中…';
  try {
    await Chappy.storage.set('notes', text);
    lastSaved = text;
    status.textContent = '保存しました ✓';
  } catch (error) {
    status.textContent = '保存に失敗しました';
    console.error('Save failed:', error);
  }
}
async function boot() {
  try {
    const saved = await Chappy.storage.get('notes');
    input.value = typeof saved === 'string' ? saved : '';
    lastSaved = input.value;
    updateCount();
    status.textContent = '準備完了';
    const info = await Chappy.info();
    await Chappy.log(`Memo initialized: ${info.version}`);
  } catch (error) {
    status.textContent = 'データ読み込みに失敗';
    console.error(error);
  }
}
input.addEventListener('input', () => {
  updateCount();
  status.textContent = '編集中…';
  clearTimeout(saveTimer);
  saveTimer = setTimeout(save, 500);
});
document.querySelector('#save').addEventListener('click', save);
document.querySelector('#test').addEventListener('click', () => {
  throw new Error('Chappy DEBUG TEST: intentional error from memo');
});
window.addEventListener('pagehide', () => {
  if (input.value !== lastSaved) save().catch(console.error);
});
boot();
