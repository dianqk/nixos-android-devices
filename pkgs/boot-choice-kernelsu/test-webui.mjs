// SPDX-License-Identifier: GPL-2.0-only
// Real packaged app/bridge with fake DOM + exact pinned three-argument KSU API.
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {readFileSync} from 'node:fs';
const root=process.argv[2];
const html=readFileSync(root+'/index.html','utf8');
const ids=[...html.matchAll(/id="([^"]+)"/g)].map(x=>x[1]);
assert.deepEqual([...ids].sort(),['android','nixos','notice','refresh','status']);
assert.match(html,/<script type="module" src="app.mjs"><\/script>/);
assert.match(html,/切换到 NixOS/);assert.match(html,/切换到 Android/);
assert(!/onload=|onclick=|https?:\/\//i.test(html));
const {mount}=await import(pathToFileURL(root+'/app.mjs'));
const {run}=await import(pathToFileURL(root+'/bridge.mjs'));
globalThis.window={};
globalThis.location={search:'?action=reboot&target=nixos',hash:'#android'};
function dom(){const nodes={};for(const id of ids) nodes[id]={disabled:false,textContent:'',addEventListener(type,fn){assert.equal(type,'click');this.handler=fn;},click(){if(!this.disabled)return this.handler();}};return {nodes,getElementById:id=>nodes[id]};}
const calls=[];let errno=0,stdout='{"preference":"nixos"}',stderr='',hold;
globalThis.ksu={exec(command,options,callback){assert.equal(arguments.length,3);assert.equal(options,'{}');calls.push(command);const reply=()=>window[callback](errno,stdout,stderr);if(hold)hold.push(reply);else queueMicrotask(reply);}};
const d=dom();await mount(d);assert.deepEqual(calls,["'/data/adb/modules/android-devices-dodge-boot-choice/bin/boot-choice' status"]);
assert.equal(Object.keys(window).length,0);
for(const target of ['nixos','android']){const n=calls.length;await d.nodes[target].click();assert.equal(calls.length,n+1);assert.equal(calls.at(-1),"'/data/adb/modules/android-devices-dodge-boot-choice/bin/boot-choice' reboot "+target);}
hold=[];const pending=d.nodes.nixos.click();const n=calls.length;assert(d.nodes.nixos.disabled&&d.nodes.android.disabled&&d.nodes.refresh.disabled);await d.nodes.android.click();assert.equal(calls.length,n);hold.pop()();hold=null;await pending;
errno=9;stdout='';stderr='preference VERIFIED/COMMITTED; standard reboot failed: example';await d.nodes.android.click();assert.match(d.nodes.notice.textContent,/已验证\/提交/);assert.match(d.nodes.status.textContent,/standard reboot failed/);
errno=17;stderr='identity refused';await d.nodes.refresh.click();assert(d.nodes.nixos.disabled);assert.match(d.nodes.status.textContent,/identity refused/);
delete globalThis.ksu;const absent=dom();const before=calls.length;await mount(absent);assert.equal(calls.length,before);assert(absent.nodes.nixos.disabled);await absent.nodes.nixos.click();assert.equal(calls.length,before);
await assert.rejects(run('nixos; reboot'));assert.equal(calls.length,before);
globalThis.ksu={exec(){throw Error('bridge exception');}};await run('status').catch(e=>assert.match(String(e),/bridge exception/));assert.equal(Object.keys(window).length,0);
console.log('PASS WebUI: entry/refresh status only, exact3arg API, each explicit target one command, busy lock, errors/committed reset failure, absent API, no URL action or callback leaks');
