// R7 offline, no-host-API Browser Lab check/uncheck/report/reset simulation.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const source = fs.readFileSync(
  path.join(__dirname, '../sample_apps/browser_lab/index.html'), 'utf8');
const script = source.match(/<script>([\s\S]*?)<\/script>/);
assert.ok(script);
const ids = [...source.matchAll(/data-r7="([a-z_]+)"/g)].map(x => x[1]);
assert.equal(ids.length, 12);
assert.equal(new Set(ids).size, 12);

function control() {
  return {
    checked: false, value: '', textContent: '', listeners: {},
    addEventListener(type, cb) { this.listeners[type] = cb; },
    run(type) { assert.equal(typeof this.listeners[type], 'function'); this.listeners[type](); },
    getAttribute(name) { return name === 'data-r7' ? this.caseId : null; },
  };
}
const inputs = ids.map(caseId => Object.assign(control(), {caseId}));
const elements = {
  progress: control(), progressText: control(), output: control(),
  report: control(), reset: control(),
};
const document = {
  querySelectorAll(selector) {
    assert.equal(selector, '[data-r7]');
    return inputs;
  },
  getElementById(id) {
    assert.ok(elements[id]);
    return elements[id];
  },
};
vm.runInNewContext(script[1], {document}, {timeout: 1000});
assert.equal(elements.progress.value, 0);
inputs[0].checked = true;
inputs[0].run('change');
assert.equal(elements.progress.value, 1);
elements.report.run('click');
assert.match(elements.output.value, /\[x\] open/);
assert.match(elements.output.value, /\[ \] public_https/);
elements.reset.run('click');
assert.equal(elements.progress.value, 0);
assert.equal(elements.output.value, '');
console.log('R7 offline Browser Lab checks and report PASS (not Android QA)');
