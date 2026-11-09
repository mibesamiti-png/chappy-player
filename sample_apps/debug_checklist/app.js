'use strict';

// Chappy QA Checklist v1. No native bridge, no network or device access.
// Human-marked results only; no automatic PASS claims.
const QA_ITEMS = Object.freeze([
  {id:'QA-01', area:'基本動作', title:'起動・セルフチェック',
    steps:'Chappy Player Debugを起動 →「端末セルフチェック」→「実行」→結果コピー。',
    expected:'起動し、4項目それぞれのPASS/FAILが表示され、結果をコピーできる。4/4成功を前提としない。'},
  {id:'QA-02', area:'基本動作', title:'Network Lab画面移動',
    steps:'ホーム → Network Lab。ブラウザ、端末一覧、ルーター識別、通信解析画面に移動して戻る。',
    expected:'クラッシュせず、各画面に移動できる。'},
  {id:'QA-03', area:'ルーター', title:'Wi-Fiルーター自動識別',
    steps:'接続中のルーターを自動識別 → 同意前/同意後の動作を確認。',
    expected:'同意前は探索しない。Wi-Fi・VPNなしでゲートウェイ候補を表示。UPnP非対応時の「型番不明」は正常。'},
  {id:'QA-04', area:'ルーター', title:'通信変更・バックグラウンド',
    steps:'ルーター識別中にWi-Fiからモバイル回線へ切替、またはアプリを背景化・復帰。',
    expected:'不適切なネットワークで取得を拒否。背景化時に取得結果・同意を破棄。'},
  {id:'QA-05', area:'BUFFALO', title:'端末一覧の手動取込',
    steps:'BUFFALO端末一覧へ、検証用2行「192.168.11.10 AA:BB:CC:DD:EE:01 TestPhone」と「192.168.11.20 AA:BB:CC:DD:EE:02 TestLaptop」を入力。',
    expected:'2台を認識。識別済み・未登録表示の切替、結果消去が動作。未知端末を不正アクセスと断定しない。'},
  {id:'QA-06', area:'PCAP', title:'ファイル選択の同意・キャンセル',
    steps:'通信解析画面で同意前ボタンと、同意後のファイル選択キャンセルを試す。',
    expected:'同意前は読み込まず、キャンセル時は結果を勝手に変更しない。'},
  {id:'QA-07', area:'PCAP', title:'合成PCAP・本文OFF',
    steps:'合成6パケットのchappy_debug_synthetic_traffic.pcapを本文プレビューOFFで読み込む。',
    expected:'DNSの質問/応答、HTTP GET /help・POST /demo、TLS SNI候補、UDP/443を表示。本文は表示しない。'},
  {id:'QA-08', area:'PCAP', title:'本文ON・データ消去',
    steps:'本文プレビューONで同じ合成PCAPを再読込 →「結果を消去」→背景化して戻る。',
    expected:'合成本文「Hello from Chappy Lab!」を表示。消去・背景化で結果と同意を破棄する。'},
  {id:'QA-09', area:'PCAP', title:'異常ファイル・再起動耐性',
    steps:'わざと壊したPCAP・未対応PCAPNGを読み込む。画面を戻して再入場する。',
    expected:'分かりやすい形式エラーが出てクラッシュせず、個人の通信記録を残さない。'}
]);
const VALUES = Object.freeze(['todo','pass','fail','blocked']);
const LABELS = Object.freeze({todo:'未実施',pass:'成功',fail:'失敗',blocked:'保留'});
const STORE_KEY = 'local.chappy.qa_checklist.v1.status';

function normalizeStates(raw) {
  const result = {};
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return result;
  for (const item of QA_ITEMS) {
    const v = raw[item.id];
    if (VALUES.includes(v)) result[item.id] = v;
  }
  return result;
}
function safeStored(value) {
  if (typeof value !== 'string' || value.length > 2048) return {};
  try { return normalizeStates(JSON.parse(value)); } catch (_) { return {}; }
}
function cleanNote(input) {
  return String(input || '').replace(/[\u0000-\u001f\u007f]/g, ' ').slice(0, 240).trim();
}
function formatReport(states, notes, meta) {
  const status = normalizeStates(states);
  const lines = [
    'Chappy Player 実機デバッグ レポート（本人の手動判定）',
    'Debug APK / GitHub run: ' + cleanNote(meta.run || '未記入'),
    'Androidバージョン: ' + cleanNote(meta.android || '未記入'),
    '記録時刻: ' + cleanNote(meta.time || '端末時刻未取得'),
    '※ このレポートは自動診断・実機PASSの証明ではありません。',
    ''
  ];
  for (const item of QA_ITEMS) {
    const v = status[item.id] || 'todo';
    lines.push(item.id + ' [' + LABELS[v] + '] ' + item.title);
    const note = cleanNote(notes && notes[item.id]);
    if (note) lines.push('  メモ: ' + note);
  }
  const done = QA_ITEMS.filter(x => (status[x.id] || 'todo') !== 'todo').length;
  const pass = QA_ITEMS.filter(x => status[x.id] === 'pass').length;
  lines.push('', '実施: ' + done + '/9件（成功 ' + pass + '件）');
  lines.push('※ 共有前に個人情報・IP/MAC・認証情報が含まれていないか確認してください。');
  return lines.join('\n');
}
function counts(states) {
  const status = normalizeStates(states);
  return VALUES.reduce((a, v) => {
    a[v] = QA_ITEMS.filter(x => (status[x.id] || 'todo') === v).length;
    return a;
  }, {});
}

function init() {
  const host = document.getElementById('cases');
  const progress = document.getElementById('progress');
  const summary = document.getElementById('summary');
  const report = document.getElementById('report');
  const run = document.getElementById('run');
  const android = document.getElementById('android');
  const msg = document.getElementById('message');
  let states = {};
  let notes = {};
  try { states = safeStored(localStorage.getItem(STORE_KEY)); } catch (_) {}
  let timer = null;
  function persist() {
    try { localStorage.setItem(STORE_KEY, JSON.stringify(states)); }
    catch (_) { msg.textContent = '端末に進捗を保存できません。この画面中だけ有効です。'; }
  }
  function update() {
    const c = counts(states);
    const finished = 9-c.todo;
    progress.value = finished;
    summary.textContent = '実施 ' + finished + '/9｜成功 ' + c.pass + '｜失敗 ' + c.fail + '｜保留 ' + c.blocked;
    document.getElementById('detail').textContent = '※ 実機で確認した場合だけ「成功」を選んでください。';
    report.value = formatReport(states, notes, {
      run: run.value, android: android.value,
      time: new Date().toLocaleString('ja-JP')
    });
  }
  for (const item of QA_ITEMS) {
    const article = document.createElement('section');
    article.className = 'case';
    const top = document.createElement('div');
    top.className = 'caseHead';
    const title = document.createElement('h3');
    title.textContent = item.id + '｜' + item.title;
    top.appendChild(title);
    const area = document.createElement('span');
    area.className = 'area';
    area.textContent = item.area;
    top.appendChild(area);
    article.appendChild(top);
    const instructions = document.createElement('p');
    const strong = document.createElement('strong');
    strong.textContent = '操作';
    instructions.appendChild(strong);
    instructions.appendChild(document.createTextNode('：' + item.steps));
    article.appendChild(instructions);
    const expectation = document.createElement('p');
    const expected = document.createElement('strong');
    expected.textContent = '期待';
    expectation.appendChild(expected);
    expectation.appendChild(document.createTextNode('：' + item.expected));
    article.appendChild(expectation);
    const label = document.createElement('label');
    label.className = 'field';
    label.textContent = '判定 ';
    const select = document.createElement('select');
    select.setAttribute('aria-label', item.id + ' 判定');
    for (const value of VALUES) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = LABELS[value];
      select.appendChild(option);
    }
    select.value = states[item.id] || 'todo';
    select.addEventListener('change', () => {
      states[item.id] = select.value;
      persist();
      update();
    });
    label.appendChild(select);
    article.appendChild(label);
    const note = document.createElement('textarea');
    note.setAttribute('aria-label', item.id + ' 追加メモ（保存しない）');
    note.setAttribute('placeholder', 'エラーや確認内容。個人情報・認証情報は入力しないでください');
    note.setAttribute('maxlength','240');
    note.setAttribute('rows','2');
    note.addEventListener('input', () => {
      notes[item.id] = note.value;
      update();
    });
    article.appendChild(note);
    host.appendChild(article);
  }
  for (const input of [run, android]) input.addEventListener('input', update);
  document.getElementById('makeReport').addEventListener('click', () => {
    update();
    report.focus();
    report.select();
    msg.textContent = 'レポートを選択しました。コピー後は共有前に個人情報を確認してください。';
  });
  document.getElementById('copyReport').addEventListener('click', async () => {
    update();
    try {
      if (!navigator.clipboard || !navigator.clipboard.writeText) throw Error();
      await navigator.clipboard.writeText(report.value);
      msg.textContent = 'レポートをコピーしました。共有前に内容を確認してください。';
    } catch (_) {
      report.focus();
      report.select();
      msg.textContent = '自動コピーできません。下のレポートを長押ししてコピーしてください。';
    }
  });
  document.getElementById('reset').addEventListener('click', () => {
    if (!window.confirm('9項目の進捗・メモ・端末情報を消去しますか？')) return;
    states = {};
    notes = {};
    try { localStorage.removeItem(STORE_KEY); } catch (_) {}
    host.querySelectorAll('select').forEach(el => { el.value = 'todo'; });
    host.querySelectorAll('textarea').forEach(el => { el.value = ''; });
    run.value = '';
    android.value = '';
    update();
    msg.textContent = '全項目を未実施に戻しました。';
  });
  update();
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { QA_ITEMS, VALUES, LABELS, STORE_KEY, normalizeStates,
    safeStored, cleanNote, formatReport, counts };
}
if (typeof document !== 'undefined') init();
