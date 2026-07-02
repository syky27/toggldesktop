'use strict';

// Firefox exposes `browser` (promise-based); Chrome exposes `chrome`. Both
// support promises for the storage / permissions / scripting APIs used here.
const api = globalThis.browser ?? globalThis.chrome;

const CONTENT_SCRIPT_ID = 'redtick-issue';
const $host = document.getElementById('host');
const $status = document.getElementById('status');

function setStatus(msg, kind) {
  $status.textContent = msg;
  $status.className = kind || '';
}

/// Parse a user-entered base URL into `{ origin, pattern }`, defaulting to
/// https when the scheme is omitted. Returns null when it isn't a valid URL.
function parseHost(raw) {
  let text = (raw || '').trim();
  if (!text) return null;
  if (!/^https?:\/\//i.test(text)) text = 'https://' + text;
  try {
    const u = new URL(text);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    // Match any scheme on that host so http/https both work; the app verifies
    // the host anyway.
    return { display: u.host, pattern: `*://${u.host}/*` };
  } catch (_) {
    return null;
  }
}

async function load() {
  const stored = await api.storage.local.get('redmineHost');
  if (stored && stored.redmineHost) $host.value = 'https://' + stored.redmineHost;
}

async function save() {
  const parsed = parseHost($host.value);
  if (!parsed) {
    setStatus('Enter a valid URL, e.g. https://redmine.example.com', 'err');
    return;
  }

  // Ask for access to that host (must run from this click — a user gesture).
  let granted = true;
  try {
    granted = await api.permissions.request({ origins: [parsed.pattern] });
  } catch (e) {
    setStatus('Permission request failed: ' + e.message, 'err');
    return;
  }
  if (!granted) {
    setStatus('Permission denied — the button can’t be added without it.', 'err');
    return;
  }

  // Re-register the content script scoped to just this host.
  try {
    await api.scripting
      .unregisterContentScripts({ ids: [CONTENT_SCRIPT_ID] })
      .catch(() => {});
    await api.scripting.registerContentScripts([
      {
        id: CONTENT_SCRIPT_ID,
        matches: [parsed.pattern],
        js: ['content.js'],
        runAt: 'document_idle',
        persistAcrossSessions: true,
      },
    ]);
  } catch (e) {
    setStatus('Could not register the page script: ' + e.message, 'err');
    return;
  }

  await api.storage.local.set({ redmineHost: parsed.display });
  setStatus(
    `Enabled for ${parsed.display}. Open an issue there and reload the page.`,
    'ok'
  );
}

document.getElementById('save').addEventListener('click', save);
load();
