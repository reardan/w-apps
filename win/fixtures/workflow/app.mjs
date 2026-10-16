import { h, render } from './vendor/preact-10.27.2.module.js';

let name = '';
let theme = localStorage.getItem('theme') || 'blue';
let message = 'Ready';
let pending = null;
function route() { return new URLSearchParams(location.search).get('view') || 'form'; }
function navigate(view) {
  history.pushState({ view }, '', '?view=' + view);
  draw();
}
function saveTheme(event) {
  theme = event.target.value;
  localStorage.setItem('theme', theme);
  draw();
}
function submit(event) {
  event.preventDefault();
  pending = new AbortController();
  message = 'Saving';
  draw();
  fetch('/api/profile', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }), signal: pending.signal })
    .then(response => { if (!response.ok) throw new Error('HTTP ' + response.status); return response.json(); })
    .then(profile => { message = 'Saved: ' + profile.name; })
    .catch(error => { message = error.name === 'AbortError' ? 'Cancelled' : 'Failed: ' + error.message; })
    .finally(() => { pending = null; draw(); });
}
function draw() {
  document.documentElement.style.setProperty('--accent', theme === 'green' ? '#286348' : '#245a78');
  render(h('main', {},
    h('h1', {}, 'Profile workflow'),
    h('nav', {}, h('button', { id: 'form-route', onClick: () => navigate('form') }, 'Profile'),
      h('button', { id: 'settings-route', onClick: () => navigate('settings') }, 'Settings')),
    route() === 'settings'
      ? h('label', {}, 'Theme ', h('select', { id: 'theme', value: theme, onChange: saveTheme },
          h('option', { value: 'blue' }, 'Blue'), h('option', { value: 'green' }, 'Green')))
      : h('form', { onSubmit: submit }, h('label', { htmlFor: 'name' }, 'Name'),
          h('input', { id: 'name', name: 'name', value: name, onInput: event => { name = event.target.value; } }),
          h('div', { className: 'actions' }, h('button', { id: 'save', type: 'submit', disabled: !!pending }, 'Save'),
            h('button', { id: 'cancel', type: 'button', disabled: !pending, onClick: () => pending.abort() }, 'Cancel'))),
    h('p', { id: 'result', role: 'status' }, message)), document.getElementById('app'));
  document.title = 'Workflow: ' + route();
}
window.addEventListener('popstate', draw);
draw();
