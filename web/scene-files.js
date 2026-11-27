/* Browser transport only; Godot validates the scene before changing the world. */
(() => {
  'use strict';
  const MAX_BYTES = 32 * 1024 * 1024;
  const dialog = document.getElementById('scene-dialog');
  const fileInput = document.getElementById('scene-file');
  const urlInput = document.getElementById('scene-url');
  const loadButton = document.getElementById('scene-load');
  const cancelButton = document.getElementById('scene-cancel');
  const message = document.getElementById('scene-message');
  let receive = null;
  let controller = null;
  let generation = 0;
  let applying = false;

  function busy(value) {
    fileInput.disabled = value;
    urlInput.disabled = value;
    loadButton.disabled = value;
    cancelButton.disabled = applying;
  }

  function open() {
    if (dialog.open) return;
    message.textContent = '';
    fileInput.value = '';
    dialog.showModal();
  }

  function cancel() {
    if (applying) return;
    generation++;
    controller?.abort();
    controller = null;
    busy(false);
    dialog.close();
    document.getElementById('canvas').focus();
  }

  async function transfer(read) {
    if (!receive || applying) return;
    controller?.abort();
    const current = ++generation;
    const requestController = new AbortController();
    controller = requestController;
    const signal = requestController.signal;
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; requestController.abort(); }, 30000);
    busy(true);
    message.textContent = '正在读取场景…';
    try {
      const text = await read(signal);
      if (current !== generation) return;
      applying = true;
      busy(true);
      message.textContent = '正在校验并加载场景…';
      receive(text);
    } catch (error) {
      if (current !== generation) return;
      applying = false;
      busy(false);
      message.textContent = timedOut ? '加载超时，请检查网址或网络后重试。' :
        error instanceof TypeError ? '无法读取网址，请检查网络、HTTPS 和服务器的跨域访问（CORS）设置。也可下载后选择本地文件。' : String(error.message || error);
    } finally {
      clearTimeout(timer);
      if (current === generation) controller = null;
    }
  }

  async function readUrl(value, signal) {
    if (!value.trim()) throw new Error('请输入场景文件的 URL。');
    const url = new URL(value.trim(), document.baseURI);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
      throw new Error('只支持 HTTP/HTTPS 场景网址或相对地址。');
    }
    const response = await fetch(url, { signal, credentials: 'same-origin' });
    if (!response.ok) throw new Error('读取失败：HTTP ' + response.status);
    if (Number(response.headers.get('Content-Length')) > MAX_BYTES) throw new Error('场景文件不能超过 32 MiB。');
    const reader = response.body.getReader();
    const decoder = new TextDecoder('utf-8', { fatal: true });
    const chunks = [];
    let size = 0;
    try {
      while (true) {
        const { done, value: chunk } = await reader.read();
        if (done) break;
        size += chunk.byteLength;
        if (size > MAX_BYTES) throw new Error('场景文件不能超过 32 MiB。');
        chunks.push(decoder.decode(chunk, { stream: true }));
      }
      chunks.push(decoder.decode());
      return chunks.join('');
    } finally {
      await reader.cancel();
      reader.releaseLock();
    }
  }

  fileInput.addEventListener('change', () => {
    const file = fileInput.files[0];
    if (!file) return;
    transfer(async () => {
      if (file.size > MAX_BYTES) throw new Error('场景文件不能超过 32 MiB。');
      return file.text();
    });
  });
  document.getElementById('scene-url-form').addEventListener('submit', event => {
    event.preventDefault();
    transfer(signal => readUrl(urlInput.value, signal));
  });
  cancelButton.addEventListener('click', cancel);
  dialog.addEventListener('cancel', event => { event.preventDefault(); cancel(); });

  window.TrackPlaygroundFiles = Object.freeze({
    open,
    register(callback) {
      receive = callback;
      const scene = new URL(location.href).searchParams.get('scene');
      if (scene) setTimeout(() => {
        open();
        urlInput.value = scene;
        transfer(signal => readUrl(scene, signal));
      }, 0);
    },
    complete(success, detail) {
      applying = false;
      busy(false);
      message.textContent = detail;
      fileInput.value = '';
      if (success) {
        dialog.close();
        document.getElementById('canvas').focus();
      }
    }
  });
})();
