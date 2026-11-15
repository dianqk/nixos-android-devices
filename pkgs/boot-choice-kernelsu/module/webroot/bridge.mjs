// SPDX-License-Identifier: GPL-2.0-only
// Independent adapter for KernelSU a23184a0e0362c10f027718b309f53e0c867b02e:
// WebViewInterface.exec(cmd, optionsJSON, callbackName), callback(errno,out,err).
// No upstream implementation copied. Commands and path are never caller text.
const binary = "'/data/adb/modules/android-devices-dodge-boot-choice/bin/boot-choice'";
const commands = Object.freeze({status: `${binary} status`, nixos: `${binary} reboot nixos`, android: `${binary} reboot android`});
let serial = 0;
export function available() { return typeof globalThis.ksu?.exec === 'function'; }
export function run(operation) {
  if (!Object.prototype.hasOwnProperty.call(commands, operation)) return Promise.reject(new Error('Unknown operation'));
  if (!available()) return Promise.reject(new Error('请从 KernelSU Manager 打开本模块 WebUI；未找到 root API。'));
  return new Promise((resolve, reject) => {
    const name = `boot_choice_callback_${++serial}`;
    window[name] = (errno, stdout, stderr) => {
      delete window[name];
      resolve({errno, stdout: String(stdout ?? ''), stderr: String(stderr ?? '')});
    };
    try { globalThis.ksu.exec(commands[operation], '{}', name); }
    catch (error) { delete window[name]; reject(error); }
  });
}
