'use strict';

const api = globalThis.browser ?? globalThis.chrome;

api.storage.local.get('redmineHost').then((stored) => {
  const el = document.getElementById('state');
  if (stored && stored.redmineHost) {
    el.textContent = 'Active on ' + stored.redmineHost;
  } else {
    el.textContent = 'Not configured yet — open Settings to set your Redmine URL.';
  }
});

document.getElementById('settings').addEventListener('click', () => {
  api.runtime.openOptionsPage();
  window.close();
});
