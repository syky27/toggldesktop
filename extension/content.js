// Injected only on the user's configured Redmine host (see options.js →
// scripting.registerContentScripts). On a Redmine issue page it adds a
// "Start in Redtick" button that launches `redtick://start?issue=N&host=H`,
// which the Redtick desktop app handles (it verifies the host, then starts /
// asks to start a timer on that issue).
(function () {
  'use strict';

  // Redmine issue detail is always /issues/<id> (also /issues/<id>/edit).
  const match = location.pathname.match(/\/issues\/(\d+)/);
  if (!match) return;
  const issueId = match[1];

  if (document.getElementById('redtick-start-btn')) return;

  const link = document.createElement('a');
  link.id = 'redtick-start-btn';
  link.href = '#';
  link.textContent = '▶ Start in Redtick';
  link.title = 'Start a Redtick timer on issue #' + issueId;
  // Inline styles so we don't depend on the Redmine theme.
  link.style.cssText = [
    'display:inline-block',
    'margin-left:8px',
    'padding:2px 8px',
    'border:1px solid #A11C1C',
    'border-radius:4px',
    'background:#A11C1C',
    'color:#fff',
    'font-weight:600',
    'text-decoration:none',
    'cursor:pointer',
    'white-space:nowrap',
  ].join(';');

  link.addEventListener('click', function (e) {
    e.preventDefault();
    const url =
      'redtick://start?issue=' +
      encodeURIComponent(issueId) +
      '&host=' +
      encodeURIComponent(location.host);
    // Launch the OS protocol handler via a transient anchor click, inside this
    // user gesture (works in Chrome and Firefox; the browser may prompt once).
    const a = document.createElement('a');
    a.href = url;
    a.style.display = 'none';
    document.body.appendChild(a);
    a.click();
    a.remove();
  });

  // Prefer Redmine's top-right issue action bar inside #content. Sidebar blocks
  // can also use ".contextual", so keep the lookup scoped to the issue content.
  const contextual = document.querySelector('#content > .contextual');
  const heading = document.querySelector('#content h2');
  if (contextual) {
    contextual.appendChild(link);
  } else if (heading) {
    heading.appendChild(link);
  } else {
    link.style.cssText +=
      ';position:fixed;top:12px;right:12px;z-index:2147483647';
    document.body.appendChild(link);
  }
})();
