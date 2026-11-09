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
// SURF-01/02: surface contact is a separate, bounded route independent of the bone bus.
const skinDecl=html.match(/function skinContactTargets\(mode,zone,gate,speed,strength,texture,amount\)\s*\{[\s\S]*?\n\}/);
assert.ok(skinDecl,'testable skin contact function must exist');
const skin=vm.runInNewContext('(' + skinDecl[0] + ')',
  {clamp:clampUnit,smoothstep:stepUnit});
const forehead={touch:1,isCanal:false,settings:{hardness:.95},side:-1};
const cheek={touch:1,isCanal:false,settings:{hardness:.48},side:0};
const canal={touch:1,isCanal:true,settings:{hardness:.38},side:0};
almost(skin('ear',forehead,0,70,.5,.5,1).level,0,'no air-generated skin texture');
almost(skin('ear',forehead,1,0,.5,.5,1).level,0,'stationary touch stays quiet');
almost(skin('ear',forehead,1,60,.5,.5,0).level,0,'user can switch surface texture off');
almost(skin('ear',canal,1,80,.5,.5,1).level,0,'canal is not facial skin');
almost(skin('bee',forehead,1,80,.5,.5,1).level,0,'self-producing bee does not rub facial skin');
almost(skin('heart',forehead,1,80,.5,.5,1).level,0,'heart pulse does not make contact scrape');
const fore=skin('ear',forehead,1,65,.65,.5,1);
const soft=skin('ear',cheek,1,65,.65,.5,1);
assert.ok(fore.level>0 && soft.level>0);
assert.ok(fore.cutoff>soft.cutoff,'hard forehead should sound brighter than cheek');
assert.ok(soft.left>soft.right,'left cheek contact should localize left');
assert.ok(fore.left===fore.right,'forehead should be approximately centered');
assert.ok(skin('ear',{...cheek,side:1},1,65,.65,.5,1).right>soft.right,
  'right cheek needs mirrored stereo weighting');
for(let i=0;i<=100;i++){
  const g=skin('gel',{touch:i/100,isCanal:false,side:1,settings:{hardness:.55}},
    1,i,.8,.6,1);
  assert.ok(Number.isFinite(g.level)&&g.level>=0&&g.level<=.15);
  assert.ok(g.cutoff>=450&&g.cutoff<=6800);
}
almost(skin('gel',forehead,NaN,NaN,NaN,NaN,NaN).level,0,'invalid controls silence surface');
assert.ok(html.includes('v.skinSource.start(0,'),'skin texture must have continuous synthesized source');
assert.ok(html.includes('v.skinGain.gain.value=0;'),'skin layer is initially silent');
assert.ok(html.includes('v.skinMerge.connect(this.externalMix)'),'surface sound should be external, not bone/canal');
assert.ok(html.includes('v.skinGain.gain.setTargetAtTime(surface.level,t,.032)'),
  'skin friction uses a smoothed gain envelope');
assert.ok(html.includes('contactLatch(skin.on,zone.touch,.28,.09)'),
  'surface tap must respect anti-jitter contact hysteresis');
assert.ok(html.includes('this.skinTap(this.voices[slot],zone)'),'first-contact event must be emitted');
assert.ok(html.includes('v.skinBus') && html.includes('v.boneMerge.connect(this.mix)'),
  'skin and bone routes both remain present');
assert.ok(html.includes('id="skinSurface"') && html.includes('skinSurface:65'),
  'skin intensity slider and default must exist');
assert.ok(html.includes("preset-v14"),'saved settings key must not change');
// SURF-04: both stroke bands should be stronger on scalp, responsive to slow touch,
// silent when stationary/airborne/inside the ear, and independently controllable.
const strokeDecl=html.match(/function scalpStrokeTargets\(mode,zone,gate,speed,strength,texture,surface,boost\)\s*\{[\s\S]*?\n\}/);
assert.ok(strokeDecl,'scalpStrokeTargets must be a pure testable function');
const stroke=vm.runInNewContext('(' + strokeDecl[0] + ')',
  {clamp:clampUnit,smoothstep:stepUnit});
const scalpZone={id:'scalp',touch:1,isCanal:false,settings:{hardness:.42},side:-1};
const cheekZone={id:'cheek_L',touch:1,isCanal:false,settings:{hardness:.48},side:0};
const canalZone={id:'earCanal_L',touch:1,isCanal:true,settings:{hardness:.38},side:0};
const slowScalp=stroke('ear',scalpZone,1,17,.7,.6,.65,.88);
const slowCheek=stroke('ear',cheekZone,1,17,.7,.6,.65,.88);
assert.ok(slowScalp.hair>0&&slowScalp.drag>0,'slow scalp stroking should be audible');
assert.ok(slowScalp.hair>slowCheek.hair,'scalp hair texture exceeds cheek');
assert.ok(slowScalp.hairHz>slowCheek.hairHz,'scalp strands are brighter than cheek');
assert.ok(slowScalp.dragHz<slowCheek.dragHz,'scalp drag is warmer/softer than cheek');
const fastScalp=stroke('ear',scalpZone,1,55,.7,.6,.65,.88);
assert.ok(fastScalp.hair>slowScalp.hair&&fastScalp.drag>slowScalp.drag,
  'faster rubbing should raise grain and drag without hard switching');
for(const [zone,g,surf,boost,mode,speed] of [
 [scalpZone,0,1,1,'ear',80],[scalpZone,1,0,1,'ear',80],
 [scalpZone,1,1,0,'ear',80],[scalpZone,1,1,1,'ear',0],
 [canalZone,1,1,1,'ear',80],[scalpZone,1,1,1,'bee',80],
 [scalpZone,1,1,1,'heart',80],
]){
 const x=stroke(mode,zone,g,speed,.8,.7,surf,boost);
 almost(x.hair,0,'stroke must be silent unless contact+movement+enabled');
 almost(x.drag,0,'drag must be silent unless contact+movement+enabled');
}
let prevHair=0,prevDrag=0;
for(let i=0;i<=100;i++){
 const x=stroke('ear',scalpZone,1,i,.7,.6,1,1);
 assert.ok(Number.isFinite(x.hair)&&Number.isFinite(x.drag));
 assert.ok(x.hair>=0&&x.hair<=.22,'hair must be bounded');
 assert.ok(x.drag>=0&&x.drag<=.14,'drag must be bounded');
 assert.ok(x.hairHz>=650&&x.hairHz<=5200);
 assert.ok(x.dragHz>=160&&x.dragHz<=700);
 assert.ok(x.hair>=prevHair-1e-9&&x.drag>=prevDrag-1e-9,'stroke response should be monotonic');
 prevHair=x.hair;prevDrag=x.drag;
}
const invalidStroke=stroke('ear',scalpZone,NaN,NaN,NaN,NaN,NaN,NaN);
almost(invalidStroke.hair,0,'invalid input must silence hair');
almost(invalidStroke.drag,0,'invalid input must silence drag');
assert.ok(html.includes("v.strokeHairGain.gain.value=0"),
  'hair sound must be silent at startup');
assert.ok(html.includes("v.strokeDragGain.gain.value=0"),
  'skin drag must be silent at startup');
assert.ok(html.includes("v.strokeDragHigh.frequency.value=65"),
  'drag should filter out subsonic rumble');
assert.ok(html.includes("v.strokeHairGain.gain.setTargetAtTime(stroke.hair"),
  'hair must enter smoothly');
assert.ok(html.includes("v.strokeDragGain.gain.setTargetAtTime(stroke.drag"),
  'drag must enter smoothly');
assert.ok(html.includes("v.strokeHairGain.connect(v.skinBus)")&&
  html.includes("v.strokeDragGain.connect(v.skinBus)"),
  'additional textures should remain on the skin bus, not the bone/canal bus');
assert.ok(html.includes("strokeBoost:88")&&html.includes('id="strokeBoost"'),
  'default stroke control should be present');
assert.ok(html.includes("'skinSurface','strokeBoost','boneStrength'"),
  'stroke control must participate in save/restore and UI label updates');
assert.ok(html.includes("preset-v14"),'Chappy storage key must remain compatible');
console.log('ASMR ear-entry, bone, rumble, skin surface and scalp stroke regression passed');
