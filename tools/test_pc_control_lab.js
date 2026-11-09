// R6B: exercise the offline mini-app's manual QA interactions in a mock DOM.
// No network or native PC capability is installed in this test.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const vm = require('node:vm');

const html = fs.readFileSync(
  path.join(__dirname, '../sample_apps/pc_control_lab/index.html'), 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
assert.ok(match, 'Inline offline QA script exists');
const allIds = [...html.matchAll(/data-r6b="([a-z_]+)"/g)].map(x => x[1]);
assert.equal(allIds.length, 13);
assert.equal(new Set(allIds).size, 13);
function element() {
  return {
    checked: false, value: '', textContent: '',
    listeners: {},
    addEventListener(type, fn) { this.listeners[type] = fn; },
    fire(type) { assert.equal(typeof this.listeners[type], 'function'); this.listeners[type](); },
    getAttribute(name) { return name === 'data-r6b' ? this.caseId : null; },
  };
}
const checks = allIds.map(caseId => Object.assign(element(), { caseId }));
const elements = {
  progress: element(), progressText: element(),
  output: element(), report: element(), reset: element(),
};
const document = {
  querySelectorAll(selector) {
    assert.equal(selector, '[data-r6b]');
    return checks;
  },
  getElementById(id) {
    assert.ok(elements[id], 'unexpected document access');
    return elements[id];
  },
};
vm.runInNewContext(match[1], {document}, {timeout: 1000});
assert.equal(elements.progress.value, 0);
checks[0].checked = true;
checks[0].fire('change');
assert.equal(elements.progress.value, 1);
elements.report.fire('click');
assert.match(elements.output.value, /\[x\] boot/);
assert.match(elements.output.value, /\[ \] qr/);
assert.doesNotMatch(elements.output.value, /PRIVATE_KEY|BEGIN RSA PRIVATE KEY|192\.168/);
elements.reset.fire('click');
assert.equal(elements.progress.value, 0);
assert.equal(elements.output.value, '');
assert.ok(checks.every(x => !x.checked));
console.log('R6B offline PC Control Lab QA interactions PASS (simulated, not physical QA).');
