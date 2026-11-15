// SPDX-License-Identifier: GPL-2.0-only
import {run, available} from './bridge.mjs';
export function mount(doc) {
  const status = doc.getElementById('status');
  const notice = doc.getElementById('notice');
  const refresh = doc.getElementById('refresh');
  const nixos = doc.getElementById('nixos');
  const android = doc.getElementById('android');
  let busy = false, ready = false;
  function controls() {
    refresh.disabled = busy;
    nixos.disabled = android.disabled = busy || !ready || !available();
  }
  async function invoke(operation) {
    if (busy || (operation !== 'status' && !ready)) return;
    busy = true; controls();
    notice.textContent = operation === 'status' ? '正在读取状态（不写入、不重启）…' : '正在由原生工具验证并请求切换，请勿重复点击…';
    try {
      const result = await run(operation);
      status.textContent = [result.stdout, result.stderr].filter(Boolean).join('\n');
      if (result.errno !== 0) {
        if (operation === 'status') ready = false;
        notice.textContent = /VERIFIED|COMMITTED/.test(status.textContent)
          ? `退出码 ${result.errno}：原生工具报告已验证/提交，但清理或重启失败。保留以下日志，不会自动重试。`
          : `退出码 ${result.errno}：操作失败，以下原生输出为准；不会自动重试。`;
      } else if (operation === 'status') {
        ready = true;
        notice.textContent = '状态读取成功。只有点击下方切换按钮才会提交偏好并请求重启。';
      } else {
        notice.textContent = '原生操作成功，已请求普通系统重启；若未重启，请保留日志，不要连续点击。';
      }
    } catch (error) {
      if (operation === 'status') ready = false;
      notice.textContent = String(error);
    } finally { busy = false; controls(); }
  }
  refresh.addEventListener('click', () => invoke('status'));
  nixos.addEventListener('click', () => invoke('nixos'));
  android.addEventListener('click', () => invoke('android'));
  controls();
  // Entry has exactly one read-only status call. No URL action, timer or reset.
  return invoke('status');
}
if (typeof document !== 'undefined') mount(document);
