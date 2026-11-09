// Pure-function acoustic regression for ASMR Sound Lab's virtual ear-entry mix.
// Does not start audio, access Android permissions, or touch user data.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(
  path.join(__dirname, '..', 'sample_apps', 'asmr_sound_lab', 'index.html'),
  'utf8',
);
const declaration = html.match(/function earEntryBlend\(depth\)\s*\{[\s\S]*?\n\}/);
assert.ok(declaration, 'earEntryBlend must be defined in the mini-app');
const blend = vm.runInNewContext('(' + declaration[0] + ')');

function almost(actual, expected, label, epsilon=1e-6) {
  assert.ok(Math.abs(actual-expected) < epsilon, label + ': ' + actual + ' != ' + expected);
}
const far = blend(-1);
almost(far.progress, 0, 'far progress');
almost(far.external, 1, 'far external');
almost(far.internal, 0, 'far internal');
const inCanal = blend(2);
almost(inCanal.progress, 1, 'inside progress');
almost(inCanal.external, 0, 'inside external');
almost(inCanal.internal, 1, 'inside internal');
let lastExt = 1, lastInt = 0;
for (let n=0;n<=200;n++) {
  const v=blend(-0.1 + n*1.2/200);
  assert.ok(Number.isFinite(v.progress) && Number.isFinite(v.external) && Number.isFinite(v.internal));
  assert.ok(v.progress>=0 && v.progress<=1);
  assert.ok(v.external >= -1e-8 && v.external <= 1+1e-8);
  assert.ok(v.internal >= -1e-8 && v.internal <= 1+1e-8);
  assert.ok(v.external <= lastExt+1e-8, 'external should never grow while entering');
  assert.ok(v.internal >= lastInt-1e-8, 'internal should never shrink while entering');
  almost(v.external*v.external + v.internal*v.internal,1,'equal-power envelope',1e-6);
  lastExt=v.external; lastInt=v.internal;
}
const midway = blend(0.46);
assert.ok(midway.external > 0.6 && midway.internal > 0.6,
  'middle of transition must keep both routes audible');
assert.ok(html.includes('const exterior=entryBlend.external;'),
  'all free-field routing must use the equal-power exterior envelope');
assert.ok(html.includes('binaural?entryBlend.internal:1'),
  'binaural-to-canal sample route must use the internal envelope');
assert.ok(html.includes('nearBoost*entryBlend.external'),
  'preserved-stereo route must fade toward zero inside the ear');
assert.ok(html.includes('insideIsolation/100'),
  'existing opposite-ear isolation must be retained');
// A single physical touch should not generate many taps from noisy boundary readings.
const latchDeclaration=html.match(/function contactLatch\(wasTouching,strength,engage,release\)\s*\{[\s\S]*?\n\}/);
assert.ok(latchDeclaration, 'contactLatch must be a pure, testable helper');
const contactLatch=vm.runInNewContext('(' + latchDeclaration[0] + ')');
assert.equal(contactLatch(false,0.15,0.20,0.07),false,'engage needs a definite touch');
assert.equal(contactLatch(false,0.21,0.20,0.07),true,'touch engages at high threshold');
assert.equal(contactLatch(true,0.11,0.20,0.07),true,'minor motion must not release');
assert.equal(contactLatch(true,0.06,0.20,0.07),false,'withdrawal releases');
assert.equal(contactLatch(false,NaN,0.20,0.07),false,'invalid strength fails closed');

function countTouches(values,engage,release) {
  let latched=false, count=0;
  for (const value of values) {
    const now=contactLatch(latched,value,engage,release);
    if(now&&!latched)count++;
    latched=now;
  }
  return {count,latched};
}
assert.equal(countTouches([0,.24,.16,.10,.13,.075,.15,.04,.24],.20,.07).count,2,
  'ear/gel contact should count two actual touches, not jitter');
assert.equal(countTouches([0,.31,.19,.11,.20,.10,.08,.33],.28,.09).count,2,
  'bone event must reject small contact fluctuations');
assert.equal(countTouches([.15,.18,.13,.19,.14],.20,.07).count,0,
  'grazing below the threshold should not tap');
assert.equal(countTouches([.29,.19,.12,.16],.28,.09).latched,true,
  'sustained touch remains engaged');
assert.ok(html.includes('contactLatch(ts.on,em.contact.gain,.20,.07)'),
  'ear and gel touch events must use hysteresis');
assert.ok(html.includes('contactLatch(bt.on,zone.touch,.28,.09)'),
  'bone transient events must use hysteresis');
assert.ok(html.includes('em.active&&em.gate>.03'),
  'inactive sound source must not latch or play transients');
// Two independently controlled low-noise layers must remain bounded and safe.
const rumbleDecl=html.match(/function bodyRumbleTargets\(closure,near,rim,sealBoost,bassBoost,bodyGain,insideGain\)\s*\{[\s\S]*?\n\}/);
assert.ok(rumbleDecl,'the ear-only rumble target helper must be present');
const clampUnit=(n,lo,hi)=>Math.min(hi,Math.max(lo,n));
const lerpUnit=(a,b,t)=>a+(b-a)*t;
const stepUnit=x=>{const t=clampUnit(x,0,1);return t*t*(3-2*t);};
const rumble=vm.runInNewContext('(' + rumbleDecl[0] + ')',
  {clamp:clampUnit,lerp:lerpUnit,smoothstep:stepUnit});
const off=rumble(1,1,1,1,1,0,1);
almost(off.airy,0,'off surface noise');
almost(off.deep,0,'off deep noise');
const unsealed=rumble(0,1,1,1,1,1,1);
assert.ok(unsealed.airy>0,'nearby soft noise remains');
almost(unsealed.deep,0,'deep rumble must not appear outside canal');
const sealed=rumble(1,1,1,1,1,1,1);
assert.ok(sealed.airy>unsealed.airy,'sealing increases the body-noise texture');
assert.ok(sealed.deep>0,'full seal should have deep brown texture');
assert.ok(sealed.airy<=.26 && sealed.deep<=.125,'gain caps must prevent excessive layering');
assert.ok(sealed.cutoff<unsealed.cutoff,'full seal should shift airy noise to lower frequencies');
let lastAiry=0,lastDeep=0;
for(let k=0;k<=100;k++){
  const value=rumble(k/100,0,0,.66,.62,.84,.88);
  assert.ok(Number.isFinite(value.airy)&&Number.isFinite(value.deep)&&Number.isFinite(value.cutoff));
  assert.ok(value.airy>=0&&value.airy<=.26);
  assert.ok(value.deep>=0&&value.deep<=.125);
  assert.ok(value.cutoff>=320&&value.cutoff<=9200);
  assert.ok(value.airy+1e-9>=lastAiry,'airy ramp must be monotonic');
  assert.ok(value.deep+1e-9>=lastDeep,'deep rumble must be monotonic');
  lastAiry=value.airy;lastDeep=value.deep;
}
const invalid=rumble(Infinity,NaN,-12,Infinity,NaN,Infinity,NaN);
assert.ok(Number.isFinite(invalid.airy) && Number.isFinite(invalid.deep));
almost(invalid.airy,0,'nonfinite invalid controls fail closed');
almost(invalid.deep,0,'nonfinite deep controls fail closed');
assert.ok(html.includes('bassGain.gain.value=0; // both layers start silent'),
  'deep noise must be silent on AudioContext startup');
assert.ok(html.includes("bassHigh.type='highpass';bassHigh.frequency.value=48"),
  'rumble must discard infrasonic content');
assert.ok(html.includes('node.bassGain.gain.setTargetAtTime(target.deep'),
  'deep rumble gain must be smoothed, not hard-switched');
assert.ok(html.includes('node.lastAiry=target.airy;node.lastDeep=target.deep;'),
  'each ear requires independent attack/release state');
assert.ok(html.includes('this.limiter.connect(this.safety)'),
  'existing output peak limiter and soft-clipping safety route must remain');
console.log('ASMR ear-entry + contact + bounded dual-layer rumble regressions passed');
